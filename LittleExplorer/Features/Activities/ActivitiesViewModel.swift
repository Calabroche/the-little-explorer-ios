import Foundation
import Observation

@Observable
@MainActor
final class ActivitiesViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var activities: [Activity] = []
    private(set) var state: LoadState = .idle

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    func load(user: AppUser) async {
        state = .loading
        do {
            activities = try await api.activities(user: user)
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
