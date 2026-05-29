import ActivityKit
import Foundation
import Observation

@Observable
final class RideActivityManager {
    private(set) var current: Activity<RideActivityAttributes>?

    /// Wipe any Live Activities left over from a previous run of the
    /// app (force-quit during nav, crash, etc). Called once at app
    /// launch from AppEnvironment.init so the Dynamic Island pill
    /// doesn't outlive the navigation it was attached to.
    func endStaleActivities() async {
        for activity in Activity<RideActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    func start(sportLabel: String, routePolyline: [[Double]]? = nil) async {
        let auth = ActivityAuthorizationInfo()
        guard auth.areActivitiesEnabled else {
            Log.tracking.error("LiveActivity start ABORTED — areActivitiesEnabled=false. Check Réglages → Face ID → Activités en direct.")
            return
        }
        Log.tracking.notice("LiveActivity start: areActivitiesEnabled=true, sportLabel=\(sportLabel, privacy: .public), polylinePoints=\(routePolyline?.count ?? 0)")
        let attributes = RideActivityAttributes(
            sportLabel: sportLabel,
            startedAt: .now,
            routePolyline: routePolyline,
        )
        let initial = RideActivityAttributes.RideState(
            distanceKm: 0,
            durationSec: 0,
            speedKmh: 0,
            elevationGainM: 0,
            heartRate: nil,
            nextManeuver: nil,
            nextManeuverDistanceM: nil,
            nextManeuverSymbol: nil,
            userLat: nil,
            userLng: nil,
        )
        do {
            current = try Activity.request(
                attributes: attributes,
                content: .init(state: initial, staleDate: nil),
                pushType: nil,
            )
            Log.tracking.notice("LiveActivity request succeeded — id=\(self.current?.id ?? "?", privacy: .public)")
        } catch {
            Log.tracking.error("LiveActivity request FAILED: \(error.localizedDescription, privacy: .public)")
        }
    }

    func update(_ state: RideActivityAttributes.RideState) async {
        guard let activity = current else { return }
        await activity.update(.init(state: state, staleDate: nil))
    }

    func end() async {
        // Defensive: end ALL active activities, not just the one we
        // tracked locally. ActivityKit can hold an activity our
        // `current` ref lost (e.g. iPhone restarted mid-ride, or
        // WCSession races) — without this loop, those orphans stay
        // pinned to the lock screen for hours. Same pattern as
        // endStaleActivities at app launch.
        for activity in Activity<RideActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        current = nil
    }
}
