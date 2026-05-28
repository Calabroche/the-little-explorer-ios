import SwiftUI

@main
struct LittleExplorerWatchApp: App {
    // PendingRideStore must be built BEFORE WorkoutManager — the
    // workout's End-callback writes a ride into the store, so the
    // store has to be alive and shared via the environment.
    @State private var pendingStore = PendingRideStore()
    @State private var workoutManager: WorkoutManager
    @State private var session = WatchSessionManager()

    init() {
        let store = PendingRideStore()
        _pendingStore = State(initialValue: store)
        _workoutManager = State(initialValue: WorkoutManager(store: store))
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(workoutManager)
                .environment(pendingStore)
                .environment(session)
        }
    }
}
