import Foundation
import Observation
import SwiftUI
import UIKit
import UserNotifications

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

    /// Whether the one-time welcome screen has been shown. Flipped true
    /// the first time a signed-in user dismisses WelcomeView with
    /// "Commencer". RootView reads this imperatively (in onAppear) to
    /// decide whether to present the welcome over the tab bar, so a
    /// brand-new user lands on a greeting + "what you can do" the first
    /// time they open the app signed-in — mirroring the web's onboarding
    /// Step 0. Per-device (UserDefaults), not per-account.
    var hasSeenWelcome: Bool {
        get { UserDefaults.standard.bool(forKey: "tle.hasSeenWelcome") }
        set { UserDefaults.standard.set(newValue, forKey: "tle.hasSeenWelcome") }
    }

    let api = APIClient.shared
    let location = LocationManager()
    let watch = WatchSessionManager()
    let activityManager = RideActivityManager()
    let localRides: LocalRideStore
    let activityStore: ActivityStore
    /// Cross-feature library of saved itineraries. Backed by
    /// UserDefaults locally + /api/itineraries server-side. Watch
    /// sync pulls from this store (Phase B).
    let itineraries = ItineraryStore()
    let healthKit = HealthKitService()
    /// Reads finished workouts out of Apple Health and pushes them to the
    /// back-end, so rides from any device (Apple Watch, Garmin, Whoop…) land
    /// in the feed without going through Strava (which caps connected athletes).
    let healthKitSync: HealthKitSyncManager
    /// Live BLE heart-rate monitor. Doesn't instantiate the CB stack
    /// until the user opens the pairing screen — keeps the system
    /// Bluetooth permission prompt from firing on app launch.
    let heartRate = HeartRateMonitor()

    /// Bearer-token session, lazy-loaded from Keychain on init. RootView
    /// reads this to decide LoginView vs the tab bar.
    let session: SessionStore

    init() {
        let localRides = LocalRideStore()
        self.localRides = localRides
        let activityStore = ActivityStore(localStore: localRides)
        self.activityStore = activityStore
        self.session = SessionStore()
        self.healthKitSync = HealthKitSyncManager(health: healthKit, api: api)

        // Phase 2 + 3 wiring: when a ride file arrives from the Apple
        // Watch, the WatchSessionManager decodes it, hands it to the
        // LocalRideStore, asks the ActivityStore to re-publish so the
        // feed picks it up without a manual refresh, AND fires the
        // Strava upload via the same APIClient the rest of the app
        // uses (so the ride eventually shows up in Strava + syncs
        // back as a "real" activity).
        watch.attach(localStore: localRides, api: api, itineraries: itineraries, activityManager: activityManager) { [weak self] _ in
            guard let self else { return }
            self.activityStore.refreshLocal(user: self.currentUser)
        }

        // ItineraryStore needs the APIClient to push changes to the
        // backend when the user saves an itinerary on iOS. The
        // onChange callback fans every mutation out to the Watch.
        itineraries.attach(api: api) { [weak self] in
            self?.watch.syncItinerariesToWatch()
        }

        // When a HealthKit workout is ingested to the back-end, re-pull the
        // feed so it shows up without a manual refresh.
        healthKitSync.onIngested = { [weak self] in
            guard let self else { return }
            Task { await self.activityStore.load(user: self.currentUser, force: true) }
        }
    }

    /// Start the Apple Health → back-end ingestion. Safe to call repeatedly
    /// (it no-ops if already observing). Gated on the user's HealthKit toggle
    /// AND a live session, so call it once we're signed in (RootView does).
    @MainActor
    func startHealthKitSync() {
        // Only reached from RootView once the session token is set, so we just
        // gate on the user's HealthKit toggle here (reading it is thread-safe;
        // session.token is MainActor-isolated so we don't touch it off-actor).
        healthKitSync.start(isEnabled: { [weak self] in
            self?.healthKitEnabled ?? false
        })
    }

    /// Ask for notification permission and register for remote (APNs) push, so
    /// the user gets a notification when someone likes / comments / follows.
    /// Called once we're signed in (RootView). The device token comes back via
    /// AppDelegate and is uploaded to the back-end.
    @MainActor
    func registerForPushNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            Task { @MainActor in UIApplication.shared.registerForRemoteNotifications() }
        }
    }

    /// Explicitly prime Apple Health ingestion from the onboarding screen: this
    /// fires the system read-permission sheet WHILE the in-app explanation is on
    /// screen (Apple's recommended priming pattern), then kicks off the
    /// one-time full-history import. Turns the toggle on if the user had it off,
    /// since tapping "authorize" is an explicit opt-in.
    @MainActor
    func primeHealthKitIngestion() async {
        guard HealthKitService.isAvailable else { return }
        if !healthKitEnabled { healthKitEnabled = true }
        await healthKitSync.primeAndStart()
    }

    /// Called when the app comes to the foreground. Reconciles the
    /// itinerary library with the backend so a route created on the web
    /// (or another device) lands on the phone — and, via the store's
    /// onChange hook, gets pushed straight to the Watch — without the
    /// user having to open the Itinerary tab first.
    @MainActor
    func refreshOnForeground() {
        Task { await itineraries.syncFromServer(user: currentUser) }
        // Re-assert the current library to the Watch in case it
        // reconnected while we were backgrounded.
        watch.syncItinerariesToWatch()
    }

    /// Fire-and-forget HealthKit save. Each step is logged so the user
    /// can verify in Profil → Diagnostics exactly where the chain
    /// stops (most common cause of "nothing in the Health app" is
    /// either the toggle being off or the system permission being
    /// denied — Apple doesn't let us tell denial from grant via the
    /// API, but we surface enough breadcrumbs to spot it).
    func saveRideToHealthKitIfEnabled(_ record: RideRecord) {
        Log.tracking.notice("HealthKit: hook fired for ride id=\(record.id)")
        guard healthKitEnabled else {
            Log.tracking.notice("HealthKit: skip — toggle is off in Profil → Paramètres")
            return
        }
        guard HealthKitService.isAvailable else {
            Log.tracking.notice("HealthKit: skip — HKHealthStore.isHealthDataAvailable() is false")
            return
        }
        Task { @MainActor in
            do {
                Log.tracking.notice("HealthKit: requesting authorization…")
                try await healthKit.requestAuthorization()
                Log.tracking.notice("HealthKit: authorization request returned, attempting save")
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
