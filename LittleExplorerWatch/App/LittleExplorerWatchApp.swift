import SwiftUI

@main
struct LittleExplorerWatchApp: App {
    @State private var pendingStore: PendingRideStore
    @State private var workoutManager: WorkoutManager
    @State private var session: WatchSessionManager

    init() {
        // Order matters: store first (workout writes into it; session
        // reads from it to enumerate the transfer queue).
        let store = PendingRideStore()
        let session = WatchSessionManager()
        // Late-bind the store into the session so it can flush the
        // queue on activation / reachability change without a
        // circular ownership.
        session.attach(pendingStore: store)

        _pendingStore = State(initialValue: store)
        _workoutManager = State(initialValue: WorkoutManager(store: store, session: session))
        _session = State(initialValue: session)
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
