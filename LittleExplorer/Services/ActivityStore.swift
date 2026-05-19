import Foundation
import Observation

/// Shared store for the activity list. Hoisted out of the per-view
/// model so multiple feed components (heatmap, training program,
/// records, etc.) all read from the same fetched payload without
/// re-hitting the network.
///
/// Activities come from two sources:
///   - the API (Strava-imported, positive IDs)
///   - the LocalRideStore (rides recorded locally via the Track tab,
///     negative timestamp IDs so they can't collide with Strava)
/// Both are merged here and exposed through the same `activities`
/// surface so every consumer (Feed cards, heatmap, FTP, Compare,
/// Wrapped, etc.) sees a single unified list.
///
/// Heavy derivations (sorting by rawDate, filtering by sport, deriving
/// the available-sports list) are cached internally and invalidated
/// only when the underlying activity arrays change. Without that
/// cache, the Feed re-sorts 50 activities and re-parses ~250 ISO
/// dates on every body re-render — which adds up to noticeable
/// latency on taps and sport switches.
@Observable
final class ActivityStore {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var apiActivities: [RideRecord] = []
    private(set) var localActivities: [RideRecord] = []
    private(set) var state: LoadState = .idle
    private(set) var loadedFor: AppUser?

    private let api: APIClient
    private let localStore: LocalRideStore?

    // Caches — @ObservationIgnored so SwiftUI doesn't track reads on
    // them. They're populated lazily on first access and rebuilt only
    // when invalidateCache() runs.
    @ObservationIgnored private var cachedSorted: [RideRecord]?
    @ObservationIgnored private var cachedFiltered: [Sport: [RideRecord]] = [:]
    @ObservationIgnored private var cachedAvailableSports: [Sport]?

    init(api: APIClient = .shared, localStore: LocalRideStore? = nil) {
        self.api = api
        self.localStore = localStore
    }

    /// All activities (API + local), sorted by rawDate (most recent
    /// first). The actual sort runs once per dataset, not per body.
    var activities: [RideRecord] {
        if let cached = cachedSorted { return cached }
        let merged = apiActivities + localActivities
        let result = merged.sorted { lhs, rhs in
            let l = RideDate.parse(lhs.rawDate) ?? .distantPast
            let r = RideDate.parse(rhs.rawDate) ?? .distantPast
            return l > r
        }
        cachedSorted = result
        return result
    }

    /// Activities filtered to a single sport, sorted most-recent first.
    /// Memoised per-sport so flipping between Vélo / Course / Rando
    /// doesn't re-scan + re-sort the full activity list each time.
    func filtered(by sport: Sport) -> [RideRecord] {
        if let cached = cachedFiltered[sport] { return cached }
        let result = activities.filtered(by: sport)
        cachedFiltered[sport] = result
        return result
    }

    /// Distinct sports present in the data, in canonical order. Used
    /// by every sport-picker chip bar.
    var availableSports: [Sport] {
        if let cached = cachedAvailableSports { return cached }
        let result = activities.availableSports
        cachedAvailableSports = result
        return result
    }

    func load(user: AppUser, force: Bool = false) async {
        if !force, loadedFor == user, state == .loaded {
            // Pick up newly-saved local rides without forcing a
            // network refetch.
            if let localStore {
                localActivities = localStore.rides(for: user)
                invalidateCache()
            }
            return
        }
        state = .loading
        do {
            apiActivities = try await api.activities(user: user)
            if let localStore { localActivities = localStore.rides(for: user) }
            loadedFor = user
            invalidateCache()
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Pull newly-saved local rides for the active user without
    /// touching the network. Called by the Track tab right after a
    /// successful save() so the Feed list updates immediately.
    func refreshLocal(user: AppUser) {
        guard let localStore else { return }
        localActivities = localStore.rides(for: user)
        invalidateCache()
    }

    private func invalidateCache() {
        cachedSorted = nil
        cachedFiltered.removeAll()
        cachedAvailableSports = nil
    }
}
