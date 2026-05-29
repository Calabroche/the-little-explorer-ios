import Foundation
import Observation
import os

/// Per-user library of saved itineraries.
///
/// Local-first with backend sync: writes hit UserDefaults
/// synchronously so the UI sees the change instantly, then push to
/// `/api/itineraries` in the background. On launch or pull-to-refresh,
/// `syncFromServer` reconciles the local cache with the server (the
/// source of truth) so itineraries created on another device — or on
/// the web — show up.
///
/// Mirrors the web's storage layout (UserDefaults key
/// `tle_itineraries_<user>`) so the same id space is shared. The
/// Watch app gets its copy via WCSession (Phase B), keyed off this
/// store's current contents.
@Observable
final class ItineraryStore {
    private(set) var items: [Itinerary] = []
    /// Reflects whether a server reconciliation is in flight — drives
    /// any "Loading…" spinner in the UI.
    private(set) var isSyncing = false
    /// Last error from a sync attempt — UI can surface a banner.
    private(set) var lastError: String?

    private var loadedFor: AppUser?
    /// API client used by the async sync helpers. Wired by AppEnv
    /// after construction (matches WatchSessionManager / LocalRideStore
    /// patterns).
    private weak var api: APIClient?

    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "com.calabrese.little-explorer-ios", category: "ItineraryStore")
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Optional callback the env can wire to push the library to the
    /// Watch on every change. Set via `attach(api:onChange:)`.
    private var onChange: (@MainActor () -> Void)?

    /// Late-binding wire from AppEnvironment so the store can talk to
    /// the backend without being constructed with a dependency that
    /// hasn't been created yet.
    func attach(api: APIClient, onChange: (@MainActor () -> Void)? = nil) {
        self.api = api
        self.onChange = onChange
    }

    // ── Local cache ────────────────────────────────────────────────

    /// Read the on-disk cache into `items`. Called once per user
    /// switch; cheap (single UserDefaults read + JSON decode of a
    /// small array).
    func load(user: AppUser) {
        guard loadedFor != user else { return }
        loadedFor = user
        if let data = defaults.data(forKey: key(for: user)),
           let decoded = try? decoder.decode([Itinerary].self, from: data) {
            items = decoded
        } else {
            items = []
        }
    }

    /// Synchronous local upsert. Stays here for backwards-compat with
    /// callers that don't need the network round-trip (e.g. unit
    /// tests, or transient drafts the user hasn't decided to keep).
    /// Most call sites should use `saveAndUpload(_:user:)` instead so
    /// the Watch eventually sees the change.
    func upsert(_ itinerary: Itinerary, user: AppUser) {
        load(user: user)
        if let idx = items.firstIndex(where: { $0.id == itinerary.id }) {
            items[idx] = itinerary
        } else {
            items.insert(itinerary, at: 0) // newest first
        }
        persist(user: user)
    }

    func remove(id: String, user: AppUser) {
        load(user: user)
        items.removeAll { $0.id == id }
        persist(user: user)
    }

    private func persist(user: AppUser) {
        guard let data = try? encoder.encode(items) else { return }
        defaults.set(data, forKey: key(for: user))
        // Notify the env so it can fan the new state out to other
        // surfaces (Watch via WCSession, etc.).
        Task { @MainActor [onChange] in onChange?() }
    }

    private func key(for user: AppUser) -> String {
        "tle_itineraries_\(user.rawValue)"
    }

    // ── Backend sync ───────────────────────────────────────────────

    /// Save locally + upload to the backend in one call. Returns
    /// immediately after the local write; the upload happens in the
    /// background and any failure is logged + surfaced via
    /// `lastError`.
    func saveAndUpload(_ itinerary: Itinerary, user: AppUser) {
        upsert(itinerary, user: user)
        guard let api else {
            logger.warning("saveAndUpload: APIClient not attached, kept locally")
            return
        }
        Task { @MainActor [weak self] in
            do {
                _ = try await api.uploadItinerary(itinerary)
                self?.logger.notice("Uploaded itinerary \(itinerary.id, privacy: .public)")
            } catch {
                self?.logger.error("Upload failed for \(itinerary.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                self?.lastError = "Save offline — \(error.localizedDescription)"
            }
        }
    }

    /// Delete locally + remotely.
    func deleteAndUpload(id: String, user: AppUser) {
        remove(id: id, user: user)
        guard let api else { return }
        Task { @MainActor [weak self] in
            do {
                try await api.deleteItinerary(id: id)
            } catch {
                self?.logger.error("Delete remote failed for \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Reconcile the local cache with the server. Strategy: pull the
    /// list of summaries, then merge with the local cache — server
    /// names/distances win, local entries that aren't on the server
    /// get pushed up (so an offline-created itinerary doesn't get
    /// lost on next sync).
    @MainActor
    func syncFromServer(user: AppUser) async {
        guard let api else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            load(user: user)
            let summaries = try await api.fetchItineraries()
            let serverIds = Set(summaries.map { $0.id })

            // Push locally-only entries (drafts saved before this user
            // had network) so the Watch / other devices can see them.
            for local in items where !serverIds.contains(local.id) {
                Task.detached { [weak api, local] in
                    _ = try? await api?.uploadItinerary(local)
                }
            }

            // Update names/distances from the server summaries — but
            // only when we already have a full local copy. Server-only
            // entries get fetched lazily by the UI when the user opens
            // them, so we don't blow bandwidth fetching every payload
            // up front.
            var merged: [Itinerary] = []
            for summary in summaries {
                if let local = items.first(where: { $0.id == summary.id }) {
                    // Keep the local payload, refresh metadata.
                    var updated = local
                    updated.name = summary.name
                    if let km = summary.distance_km { updated.distanceKm = km }
                    merged.append(updated)
                } else {
                    // Server-only stub — fetch full payload now so the
                    // user can use it immediately. Bandwidth cost is
                    // bounded (a few hundred KB per itinerary).
                    do {
                        let full = try await api.fetchItinerary(id: summary.id)
                        merged.append(full)
                    } catch {
                        logger.warning("Failed to fetch full payload for \(summary.id, privacy: .public)")
                    }
                }
            }
            items = merged
            persist(user: user)
            lastError = nil
        } catch {
            logger.error("syncFromServer failed: \(error.localizedDescription, privacy: .public)")
            lastError = "Sync échouée — \(error.localizedDescription)"
        }
    }
}
