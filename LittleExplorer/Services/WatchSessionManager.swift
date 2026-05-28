import Foundation
import Observation
import WatchConnectivity

/// Two-way bridge between iPhone and Apple Watch.
///
/// Two flows:
///   1. State messaging (lightweight, ephemeral) — `sendMessage` for
///      live workout state, control commands, etc.
///   2. File transfer — durable, OS-queued ride-trace JSON files
///      coming back from the Watch when a standalone ride ended.
///      Each file is decoded as a `PendingRide`, converted into a
///      `RideRecord`, and ingested into `LocalRideStore` so it shows
///      up in the Activités feed alongside Strava-imported rides.
@Observable
final class WatchSessionManager: NSObject, WCSessionDelegate {
    private(set) var isReachable = false
    private(set) var isPaired = false
    var lastIncomingMessage: [String: Any] = [:]
    /// Count of rides received from the Watch in this app session.
    /// Doesn't persist across launches — it's just a "we received
    /// something" indicator the UI can use to flash a confirmation.
    private(set) var ridesReceivedThisSession = 0

    private let session: WCSession?
    /// Late-bound from AppEnvironment after both this manager and the
    /// ride store have been instantiated. Weak so we don't form a
    /// retain cycle through the app's environment graph.
    private weak var localStore: LocalRideStore?
    /// Callback the env wires to `activityStore.refreshLocal(user:)`
    /// so the feed re-reads from the store after a Watch ride lands.
    private var onRideIngested: (@MainActor (Int) -> Void)?

    override init() {
        self.session = WCSession.isSupported() ? WCSession.default : nil
        super.init()
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    /// Wire the ingestion targets after env construction. Idempotent
    /// — calling it twice just replaces the references.
    func attach(localStore: LocalRideStore, onRideIngested: @MainActor @escaping (Int) -> Void) {
        self.localStore = localStore
        self.onRideIngested = onRideIngested
    }

    func send(_ message: [String: Any]) {
        guard let session, session.isReachable else { return }
        session.sendMessage(message, replyHandler: nil) { error in
            Log.watch.error("send error: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            self.isReachable = session.isReachable
            #if os(iOS)
            self.isPaired = session.isPaired
            #else
            self.isPaired = true
            #endif
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.isReachable = session.isReachable }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.lastIncomingMessage = message }
    }

    /// Called by the OS when a file arrives from the Watch. The
    /// `file.fileURL` points at a TEMPORARY location — read or copy
    /// the contents synchronously inside this callback; once it
    /// returns, the OS deletes the temp file.
    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let url = file.fileURL
        guard let data = try? Data(contentsOf: url) else {
            Log.watch.error("didReceive file: couldn't read \(url.lastPathComponent, privacy: .public)")
            return
        }
        let decoder = JSONDecoder()
        guard let ride = try? decoder.decode(PendingRide.self, from: data) else {
            Log.watch.error("didReceive file: decode failed for \(url.lastPathComponent, privacy: .public)")
            return
        }
        Task { @MainActor in
            self.ingest(ride)
        }
    }

    @MainActor
    private func ingest(_ ride: PendingRide) {
        guard let store = localStore else {
            Log.watch.warning("ingest: localStore not attached yet, dropping ride \(ride.id)")
            return
        }
        // Dedupe: if a ride with this id already exists for any user,
        // skip. Watch transfers can fire twice (e.g. catch-up flush
        // after a reachability gap) and `transferFile` doesn't ack
        // server-side so the OS may re-send.
        let alreadyKnown = store.ridesByUser.values
            .flatMap { $0 }
            .contains(where: { $0.id == Int(ride.id) })
        guard !alreadyKnown else {
            Log.watch.notice("ingest: ride \(ride.id) already in store, skipping")
            return
        }
        let record = ride.toRideRecord()
        // For now we attach every Watch ride to the .florian user
        // bucket — multi-user picking happens in Phase 3 (the watch
        // doesn't yet know which iOS user is logged in).
        store.add(record, for: .florian)
        ridesReceivedThisSession += 1
        Log.watch.notice("Ingested Watch ride \(ride.id) (\(record.distance ?? 0, format: .fixed(precision: 2)) km)")
        // Tell the parent (env) so it can refresh the activity store
        // and the feed picks up the new ride without the user pulling
        // to refresh.
        onRideIngested?(record.id)
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif
}
