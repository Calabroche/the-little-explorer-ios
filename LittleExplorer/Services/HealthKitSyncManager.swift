import Foundation
import HealthKit

/// Pulls finished workouts out of Apple Health and pushes them to the back-end
/// (POST /api/activities/ingest), so Little Explorer captures rides from ANY
/// device that writes to Health (Apple Watch, Garmin, Whoop, Wahoo…) with no
/// Strava athlete cap.
///
/// On `start` it does an initial sweep, then background delivery keeps it live:
/// whenever a new workout lands in Health the observer wakes us and we upload
/// it. Dedup is by workout UUID so nothing is sent twice.
///
/// The FIRST sweep after a user primes ingestion imports their WHOLE Apple
/// Health back-catalogue (not just recent workouts), so a brand-new account
/// arrives full instead of empty. Every subsequent sweep is incremental
/// (last 45 days) — enough to catch back-dated syncs, cheap to run.
final class HealthKitSyncManager {
    private let health: HealthKitService
    private let api: APIClient

    private var isEnabled: () -> Bool = { false }
    private var isSyncing = false
    private var observing = false

    /// Fired after at least one new workout was ingested (e.g. refresh feed).
    var onIngested: (() -> Void)?

    private let uploadedKey     = "tle.healthkit.uploadedUUIDs"
    /// Set once the user has been shown the in-app priming screen (or is a
    /// pre-existing install). Until then we don't fire the system permission
    /// sheet, so a new user always sees the explanation first.
    private let primedKey       = "tle.healthkit.primed"
    /// Set once the one-time full-history import has completed, so we only
    /// pay for the deep sweep once and stay incremental afterwards.
    private let didFullSweepKey = "tle.healthkit.didFullSweep"
    /// Mirror of AppEnvironment.hasSeenWelcome — an existing install that's
    /// already past onboarding is treated as primed so its sync never stalls.
    private let seenWelcomeKey  = "tle.hasSeenWelcome"

    init(health: HealthKitService, api: APIClient) {
        self.health = health
        self.api = api
    }

    /// Kick things off. `isEnabled` gates on the user's HealthKit toggle AND a
    /// valid session (the APIClient must have its bearer token set), so call
    /// this once the user is signed in.
    func start(isEnabled: @escaping () -> Bool) {
        self.isEnabled = isEnabled
        guard HealthKitService.isAvailable else { return }
        Task { await self.bootstrap() }
    }

    /// Explicitly grant + start ingestion from the onboarding priming screen.
    /// Flips the primed flag so the system permission sheet fires now (with the
    /// user's context on screen). Awaits only the permission request (fast) and
    /// runs the full-history import detached, so the onboarding UI never blocks
    /// on a big sweep.
    func primeAndStart() async {
        UserDefaults.standard.set(true, forKey: primedKey)
        guard isEnabled(), await ensureAuthorized() else { return }
        startObservingIfNeeded()
        Task { await self.syncNew() }
    }

    private func bootstrap() async {
        guard isEnabled() else { return }

        // Don't fire the system HealthKit permission sheet on a brand-new user
        // before they've seen the in-app priming screen. Onboarding calls
        // primeAndStart() which flips `primed`. A pre-existing install (already
        // past the welcome screen) is auto-primed so its sync keeps working.
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: primedKey) {
            if defaults.bool(forKey: seenWelcomeKey) {
                defaults.set(true, forKey: primedKey)
            } else {
                return
            }
        }

        guard await ensureAuthorized() else { return }
        await syncNew()
        startObservingIfNeeded()
    }

    /// Request READ permission on workouts/routes/HR. Returns false (and logs)
    /// if the request throws, so callers can bail cleanly.
    private func ensureAuthorized() async -> Bool {
        do {
            try await health.requestIngestAuthorization()
            return true
        } catch {
            Log.tracking.error("HK read auth failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Start background delivery once. Every new workout wakes the observer,
    /// which triggers an incremental sync.
    private func startObservingIfNeeded() {
        guard !observing else { return }
        observing = true
        health.startObservingWorkouts { [weak self] in
            Task { await self?.syncNew() }
        }
    }

    /// Fetch workouts and upload any we haven't sent yet. The first run does a
    /// full-history import; later runs only look back 45 days.
    func syncNew() async {
        guard isEnabled(), !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        let defaults = UserDefaults.standard
        let fullHistory = !defaults.bool(forKey: didFullSweepKey)

        // First sweep: import everything in Apple Health (no limit, back to the
        // epoch). Afterwards: last 45 days only, so a back-dated import (a ride
        // Garmin syncs a day late) is still caught. UUID dedup keeps both
        // idempotent, and the server upserts by a stable id, so re-sending an
        // already-imported workout is a no-op either way.
        let since = fullHistory
            ? Date(timeIntervalSince1970: 0)
            : (Calendar.current.date(byAdding: .day, value: -45, to: Date()) ?? Date(timeIntervalSince1970: 0))
        let limit = fullHistory ? HKObjectQueryNoLimit : 50
        guard let workouts = try? await health.fetchWorkouts(since: since, limit: limit) else { return }

        var uploaded = Set(defaults.stringArray(forKey: uploadedKey) ?? [])
        var didIngest = false

        for workout in workouts.sorted(by: { $0.endDate < $1.endDate }) {
            let uid = workout.uuid.uuidString
            if uploaded.contains(uid) { continue }
            guard let payload = await health.buildIngestPayload(for: workout) else { continue }
            do {
                try await api.ingestHealthWorkout(payload)
                uploaded.insert(uid)
                didIngest = true
                Log.api.notice("HK ingest OK: \(uid, privacy: .public) · \(payload.type, privacy: .public) · \(Int(payload.distance_m / 1000)) km")
            } catch {
                Log.api.error("HK ingest failed for \(uid, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        // Persist the dedup set, capped so it can't grow unbounded.
        let capped = Array(Array(uploaded).suffix(2000))
        defaults.set(capped, forKey: uploadedKey)

        // Mark the deep import done so we stay incremental from now on. Only
        // flip it once we actually completed a full-history pass without the
        // fetch failing (guarded above), so a transient error retries the
        // full sweep next time rather than silently skipping the back-catalogue.
        if fullHistory { defaults.set(true, forKey: didFullSweepKey) }

        if didIngest { onIngested?() }
    }
}
