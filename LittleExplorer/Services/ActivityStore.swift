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

    init(api: APIClient = .shared, localStore: LocalRideStore? = nil) {
        self.api = api
        self.localStore = localStore
    }

    /// All activities (API + local), sorted by rawDate (most recent
    /// first). Computed on demand so updates to either source surface
    /// immediately.
    var activities: [RideRecord] {
        (apiActivities + localActivities).sorted { lhs, rhs in
            let l = RideDate.parse(lhs.rawDate) ?? .distantPast
            let r = RideDate.parse(rhs.rawDate) ?? .distantPast
            return l > r
        }
    }

    func load(user: AppUser, force: Bool = false) async {
        if !force, loadedFor == user, state == .loaded {
            // Pick up newly-saved local rides without forcing a
            // network refetch.
            if let localStore { localActivities = localStore.rides(for: user) }
            return
        }
        state = .loading
        do {
            apiActivities = try await api.activities(user: user)
            if let localStore { localActivities = localStore.rides(for: user) }
            loadedFor = user
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
    }

    /// Activities filtered to a single sport, sorted most-recent first.
    func filtered(by sport: Sport) -> [RideRecord] {
        activities.filtered(by: sport)
    }
}
