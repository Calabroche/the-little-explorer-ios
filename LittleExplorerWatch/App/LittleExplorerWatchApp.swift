import SwiftUI

@main
struct LittleExplorerWatchApp: App {
    @State private var pendingStore: PendingRideStore
    @State private var workoutManager: WorkoutManager
    @State private var session: WatchSessionManager
    @State private var itineraryCache: ItineraryCache

    init() {
        // Order matters: store first (workout writes into it; session
        // reads from it to enumerate the transfer queue).
        let store = PendingRideStore()
        let cache = ItineraryCache()
        let session = WatchSessionManager()
        // Late-bind everything into the session — the itinerary cache
        // gets refreshed when the iPhone pushes a context, and the
        // pending store gets drained on every reachability change.
        session.attach(pendingStore: store, itineraryCache: cache)

        _pendingStore = State(initialValue: store)
        _itineraryCache = State(initialValue: cache)
        _workoutManager = State(initialValue: WorkoutManager(store: store, session: session))
        _session = State(initialValue: session)
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(workoutManager)
                .environment(pendingStore)
                .environment(session)
                .environment(itineraryCache)
        }
    }
}
