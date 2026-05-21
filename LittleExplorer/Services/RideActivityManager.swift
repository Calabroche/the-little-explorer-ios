import ActivityKit
import Foundation
import Observation

/// @MainActor: `Activity.request` and `Activity.update` from ActivityKit
/// must be called from the main actor on iOS 17+ — calling them from
/// the cooperative thread pool crashes on device.
@Observable
@MainActor
final class RideActivityManager {
    private(set) var current: Activity<RideActivityAttributes>?

    func start(sportLabel: String) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = RideActivityAttributes(sportLabel: sportLabel, startedAt: .now)
        let initial = RideActivityAttributes.RideState(
            distanceKm: 0,
            durationSec: 0,
            speedKmh: 0,
            elevationGainM: 0,
            heartRate: nil,
            nextManeuver: nil,
            nextManeuverDistanceM: nil,
            nextManeuverSymbol: nil,
        )
        do {
            current = try Activity.request(
                attributes: attributes,
                content: .init(state: initial, staleDate: nil),
                pushType: nil,
            )
        } catch {
            Log.tracking.error("Failed to start Live Activity: \(error.localizedDescription, privacy: .public)")
        }
    }

    func update(_ state: RideActivityAttributes.RideState) async {
        guard let activity = current else { return }
        await activity.update(.init(state: state, staleDate: nil))
    }

    func end() async {
        guard let activity = current else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
        current = nil
    }
}
