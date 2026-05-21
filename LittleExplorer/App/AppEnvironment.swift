import Foundation
import Observation
import SwiftUI

@Observable
final class AppEnvironment {
    var currentUser: AppUser = .florian
    var selectedSport: Sport = .cycling
    var darkModeOverride: ColorScheme? = nil

    let api = APIClient.shared
    let location = LocationManager()
    let watch = WatchSessionManager()
    let activityManager = RideActivityManager()
    let localRides: LocalRideStore
    let activityStore: ActivityStore

    /// Bearer-token session, lazy-loaded from Keychain on init. RootView
    /// reads this to decide LoginView vs the tab bar.
    let session: SessionStore

    init() {
        let localRides = LocalRideStore()
        self.localRides = localRides
        self.activityStore = ActivityStore(localStore: localRides)
        self.session = SessionStore()
    }

    /// Clear any Live Activities left over from a previous run of the
    /// app. Called from RootView.task (not from init) so the SwiftUI
    /// scene has a chance to connect even if the ActivityKit query
    /// misbehaves — calling this from init was the suspected cause of
    /// the white-screen-on-launch regression on iOS 26.4.2.
    func endStaleLiveActivities() async {
        await activityManager.endStaleActivities()
    }
}
