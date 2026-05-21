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
        // Clear any stale Live Activities left from a previous run
        // (e.g. force-quit mid-navigation). Without this the Dynamic
        // Island pill keeps showing even though the app is gone.
        Task { @MainActor in
            await self.activityManager.endStaleActivities()
        }
    }
}
