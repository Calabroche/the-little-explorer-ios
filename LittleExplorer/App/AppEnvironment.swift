import Foundation
import Observation
import SwiftUI

@Observable
final class AppEnvironment {
    var currentUser: AppUser = .florian
    var selectedSport: Sport = .cycling
    var darkModeOverride: ColorScheme? = nil

    /// Whether saved iOS-recorded rides should also be mirrored into
    /// Apple Health as HKWorkouts. Persisted via UserDefaults — flips
    /// take effect on the next save (existing workouts stay where they
    /// are). Default ON; the user can toggle in Profil → Paramètres.
    var healthKitEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "tle.healthKitEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "tle.healthKitEnabled") }
    }

    let api = APIClient.shared
    let location = LocationManager()
    let watch = WatchSessionManager()
    let activityManager = RideActivityManager()
    let localRides: LocalRideStore
    let activityStore: ActivityStore
    let healthKit = HealthKitService()

    /// Bearer-token session, lazy-loaded from Keychain on init. RootView
    /// reads this to decide LoginView vs the tab bar.
    let session: SessionStore

    init() {
        let localRides = LocalRideStore()
        self.localRides = localRides
        self.activityStore = ActivityStore(localStore: localRides)
        self.session = SessionStore()
    }

    /// Fire-and-forget HealthKit save. Wrapped here so call sites
    /// (RideTracker save, NavigateView save dialog) don't each have to
    /// check the toggle + handle auth + swallow errors. Silent failure
    /// is fine — the local copy of the ride is already persisted.
    func saveRideToHealthKitIfEnabled(_ record: RideRecord) {
        guard healthKitEnabled, HealthKitService.isAvailable else { return }
        Task { @MainActor in
            do {
                try await healthKit.requestAuthorization()
                try await healthKit.saveRide(record)
            } catch {
                Log.tracking.error("HealthKit save failed: \(error.localizedDescription, privacy: .public)")
            }
        }
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
