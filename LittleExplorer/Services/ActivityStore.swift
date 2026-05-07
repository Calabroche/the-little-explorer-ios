import Foundation
import Observation

/// Shared store for the activity list. Hoisted out of the per-view
/// model so multiple feed components (heatmap, training program,
/// records, etc.) all read from the same fetched payload without
/// re-hitting the network.
@Observable
final class ActivityStore {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var activities: [RideRecord] = []
    private(set) var state: LoadState = .idle
    private(set) var loadedFor: AppUser?

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    func load(user: AppUser, force: Bool = false) async {
        if !force, loadedFor == user, state == .loaded { return }
        state = .loading
        do {
            activities = try await api.activities(user: user)
            loadedFor = user
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Activities filtered to a single sport, sorted most-recent first.
    func filtered(by sport: Sport) -> [RideRecord] {
        activities
            .filtered(by: sport)
            .sorted { lhs, rhs in
                let l = RideDate.parse(lhs.rawDate) ?? .distantPast
                let r = RideDate.parse(rhs.rawDate) ?? .distantPast
                return l > r
            }
    }
}
