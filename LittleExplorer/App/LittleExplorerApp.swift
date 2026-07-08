import Foundation
import SwiftUI
import UIKit

@main
struct LittleExplorerApp: App {
    @State private var environment = AppEnvironment()
    @Environment(\.scenePhase) private var scenePhase
    // Bridges UIKit's remote-notification callbacks into our SwiftUI app so we
    // can receive the APNs device token and register it server-side.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Notice-level log on every launch so the Diagnostics view
        // always has at least one entry to display — proves the
        // pipeline is alive even when nothing has gone wrong yet.
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build   = Bundle.main.infoDictionary?["CFBundleVersion"]            as? String ?? "?"
        Log.app.notice("App launched · v\(version, privacy: .public) (\(build, privacy: .public))")

        // Catch Objective-C exceptions thrown from any system framework
        // (UIKit / MapKit / Swift Charts) and persist the reason + stack
        // trace to UserDefaults BEFORE the process dies. Next launch
        // we read it back and log it again at .error level so the
        // in-app Diagnostics view picks it up (OSLogStore's
        // .currentProcessIdentifier scope can't see logs from a prior
        // PID, but UserDefaults survives).
        NSSetUncaughtExceptionHandler { exception in
            let payload: [String: Any] = [
                "name":   exception.name.rawValue,
                "reason": exception.reason ?? "",
                "stack":  exception.callStackSymbols.joined(separator: "\n"),
                "ts":     Date().timeIntervalSince1970,
            ]
            UserDefaults.standard.set(payload, forKey: "tle.lastUncaughtException")
            Log.app.fault("UNCAUGHT NSException: \(exception.name.rawValue, privacy: .public) — \(exception.reason ?? "", privacy: .public)")
        }

        // Re-emit any exception captured on the previous run so it
        // shows up in Diagnostics.
        if let payload = UserDefaults.standard.dictionary(forKey: "tle.lastUncaughtException"),
           let name   = payload["name"]   as? String,
           let reason = payload["reason"] as? String,
           let stack  = payload["stack"]  as? String,
           let ts     = payload["ts"]     as? TimeInterval {
            Log.app.error("Previous run crashed at \(Date(timeIntervalSince1970: ts), privacy: .public) — \(name, privacy: .public): \(reason, privacy: .public)\n\(stack, privacy: .public)")
            UserDefaults.standard.removeObject(forKey: "tle.lastUncaughtException")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .preferredColorScheme(environment.darkModeOverride)
                .tint(AppColors.terra)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { environment.refreshOnForeground() }
                }
        }
    }
}

/// Receives APNs remote-notification callbacks. The token arrives here after
/// `UIApplication.registerForRemoteNotifications()` (kicked off post-login);
/// we upload it to the back-end so pushes for likes/comments/follows reach
/// this device. Uploads best-effort — a 401 (not yet signed in) is retried on
/// the next registration once the session token is set.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(hex, forKey: "tle.apnsToken")
        Log.app.notice("APNs token registered")
        Task { try? await APIClient.shared.registerDeviceToken(hex) }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Log.app.error("APNs registration failed: \(error.localizedDescription, privacy: .public)")
    }
}
