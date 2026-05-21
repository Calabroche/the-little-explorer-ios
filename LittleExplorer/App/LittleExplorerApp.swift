import SwiftUI

@main
struct LittleExplorerApp: App {
    @State private var environment = AppEnvironment()

    init() {
        // Notice-level log on every launch so the Diagnostics view
        // always has at least one entry to display — proves the
        // pipeline is alive even when nothing has gone wrong yet.
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build   = Bundle.main.infoDictionary?["CFBundleVersion"]            as? String ?? "?"
        Log.app.notice("App launched · v\(version, privacy: .public) (\(build, privacy: .public))")
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .preferredColorScheme(environment.darkModeOverride)
                .tint(AppColors.terra)
        }
    }
}
