import Foundation
import Observation
import SwiftUI

/// @MainActor: the environment owns @MainActor services
/// (`RideActivityManager`) and is created by SwiftUI's `@State` which
/// already runs on the main actor. Annotating it explicitly lets the
/// compiler verify the chain so we don't ship another off-main UIKit
/// call into a crash.
@Observable
@MainActor
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
}
