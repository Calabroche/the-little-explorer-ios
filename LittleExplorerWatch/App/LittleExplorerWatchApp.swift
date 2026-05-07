import SwiftUI

@main
struct LittleExplorerWatchApp: App {
    @State private var workoutManager = WorkoutManager()
    @State private var session = WatchSessionManager()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(workoutManager)
                .environment(session)
        }
    }
}
