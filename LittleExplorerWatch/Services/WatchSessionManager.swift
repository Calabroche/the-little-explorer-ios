import Foundation
import Observation
import WatchConnectivity
import os

/// Watch-side WCSession bridge.
///
/// Responsibilities:
///   1. State messaging (lightweight, ephemeral) — same `sendMessage`
///      contract the iPhone uses for live workout state.
///   2. File transfer of recorded rides (durable, queued, resumable
///      across reachability gaps) — Phase 2. Each PendingRide JSON
///      file in the local store gets shipped to the iPhone exactly
///      once; on success the local file is deleted.
///
/// Why `transferFile` and not `sendMessage`: `transferFile` queues
/// the transfer in the OS, persists across app suspensions, retries
/// when the phone comes back, and confirms completion via the
/// delegate. `sendMessage` would silently drop on reachability gaps —
/// useless for important payloads like a ride trace.
@Observable
final class WatchSessionManager: NSObject, WCSessionDelegate {
    private(set) var isReachable = false
    var lastIncomingMessage: [String: Any] = [:]

    private let session: WCSession?
    private let logger = Logger(subsystem: "com.calabrese.little-explorer-ios.watchkitapp", category: "WatchSession")
    /// Weak ref so the session manager doesn't keep the store alive
    /// past the app's lifetime; the store is owned by the app.
    private weak var pendingStore: PendingRideStore?
    /// Watch-side itinerary cache. Updated whenever the iPhone pushes
    /// a new application context — see `session(_:didReceiveApplicationContext:)`.
    private weak var itineraryCache: ItineraryCache?

    override init() {
        self.session = WCSession.isSupported() ? WCSession.default : nil
        super.init()
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    /// Late-binding wire-up from LittleExplorerWatchApp — we need the
    /// store reference so we can a) enumerate pending rides on
    /// startup to push the queue, and b) delete each file after a
    /// successful transfer. Also wires the itinerary cache so we can
    /// update it when the iPhone pushes a new application context.
    func attach(pendingStore: PendingRideStore, itineraryCache: ItineraryCache) {
        self.pendingStore = pendingStore
        self.itineraryCache = itineraryCache
        // If we already have an application context from a previous
        // session (i.e. the iPhone pushed before this Watch run), drain
        // it now so the picker has fresh data the moment the view
        // mounts. WCSession holds the latest context across launches.
        if let session, !session.receivedApplicationContext.isEmpty {
            ingestApplicationContext(session.receivedApplicationContext)
        }
        // Catch-up: on launch, attempt to push every ride still on disk.
        // WCSession.transferFile is idempotent on the iPhone receive
        // side (we dedupe by id) so a re-send after a missed handshake
        // is safe.
        Task { @MainActor in
            self.flushPendingQueue()
        }
    }

    /// Decode the iPhone's pushed itinerary library and hand it to
    /// the local cache. Shared between the live `didReceiveApplicationContext`
    /// callback and the on-launch drain of the previously-stored context.
    private func ingestApplicationContext(_ context: [String: Any]) {
        guard let kind = context["kind"] as? String, kind == "itineraries",
              let data = context["data"] as? Data else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode([Itinerary].self, from: data) else {
            logger.warning("ingestApplicationContext: decode failed (\(data.count) bytes)")
            return
        }
        Task { @MainActor in
            self.itineraryCache?.set(decoded)
        }
    }

    func send(_ message: [String: Any]) {
        guard let session, session.isReachable else { return }
        session.sendMessage(message, replyHandler: nil) { error in
            print("Watch send error: \(error)")
        }
    }

    // MARK: - Live Activity bridge
    //
    // While a ride is in progress on the Watch, we mirror its state
    // onto the iPhone's Live Activity (Lock Screen + Dynamic Island)
    // so the rider can glance at their phone in the bottle cage and
    // see what the watch sees. Three signals:
    //   • rideStarted  — sent once when the workout begins. Includes
    //     the sport label and (for itinerary rides) the downsampled
    //     route polyline so the lock-screen map can draw the path.
    //   • rideUpdate   — sent every ~3 s while the ride is active
    //     and not paused. Carries distance / duration / speed / HR /
    //     position. `sendMessage` for low latency when reachable.
    //   • rideEnded    — sent once when the workout finishes.
    //
    // For start / end we also use `transferUserInfo` as a durable
    // backup: if the iPhone was unreachable at the moment of the
    // start tap, the message still lands later so the activity
    // eventually appears (or is dismissed) rather than orphaning.

    /// Watch ride just began — kick the iPhone's Live Activity on.
    func sendRideStarted(sportLabel: String, routePolyline: [[Double]]?) {
        var msg: [String: Any] = [
            "kind": "rideStarted",
            "sportLabel": sportLabel,
            "startedAt": Date().timeIntervalSince1970,
        ]
        if let routePolyline {
            msg["routePolyline"] = routePolyline
        }
        send(msg)
        // Durable backup in case iPhone wasn't reachable just then.
        session?.transferUserInfo(msg)
    }

    /// Periodic in-ride snapshot (~3 s cadence). Fires through THREE
    /// channels for resilience:
    ///   1. sendMessage — low-latency push when iPhone is reachable
    ///   2. updateApplicationContext — latest-state cache so an
    ///      iPhone that wakes mid-ride still gets fresh numbers
    ///      instead of the initial zeroes (this is the "lock screen
    ///      stuck at 0" symptom we're fixing)
    ///   3. transferUserInfo (start/end only) — guaranteed delivery
    ///      for lifecycle events that absolutely must land
    ///
    /// For updates, sendMessage + applicationContext is enough:
    /// the latter ensures the *latest* snapshot wins on the iPhone
    /// side regardless of reachability state.
    func sendRideUpdate(
        distanceKm: Double,
        durationSec: Double,
        speedKmh: Double,
        elevationGainM: Double,
        heartRate: Int?,
        userLat: Double?,
        userLng: Double?,
    ) {
        var msg: [String: Any] = [
            "kind": "rideUpdate",
            "distanceKm": distanceKm,
            "durationSec": durationSec,
            "speedKmh": speedKmh,
            "elevationGainM": elevationGainM,
        ]
        if let heartRate { msg["heartRate"] = heartRate }
        if let userLat { msg["userLat"] = userLat }
        if let userLng { msg["userLng"] = userLng }
        send(msg)
        // applicationContext dedupes against the previous value
        // so spamming this every 3 s is cheap — only the *latest*
        // dict is actually transmitted to the iPhone when it
        // becomes reachable. Perfect "freshest snapshot wins"
        // semantics for a Live Activity.
        try? session?.updateApplicationContext(msg)
    }

    /// Workout finished — dismiss the iPhone's Live Activity.
    /// Wide fan-out (4 channels) so the activity never gets stuck
    /// on the lock screen: sendMessage if reachable, persisted
    /// applicationContext as the new "latest", AND transferUserInfo
    /// as a durable receipt the OS guarantees to deliver.
    func sendRideEnded() {
        let msg: [String: Any] = ["kind": "rideEnded"]
        send(msg)
        try? session?.updateApplicationContext(msg)
        session?.transferUserInfo(msg)
    }

    /// Queue a single ride file for transfer to the iPhone. Returns
    /// the WCSessionFileTransfer so callers can observe progress if
    /// they want (we don't, currently).
    @MainActor
    @discardableResult
    func transferRide(at url: URL, rideId: Int64) -> WCSessionFileTransfer? {
        guard let session else { return nil }
        // Tag the file with its rideId so the iPhone delegate can use
        // it for dedupe even before reading the JSON body.
        let metadata: [String: Any] = [
            "kind":   "pendingRide",
            "rideId": "\(rideId)",
        ]
        let transfer = session.transferFile(url, metadata: metadata)
        logger.notice("Queued file transfer for ride \(rideId, privacy: .public)")
        return transfer
    }

    /// Re-attempt transfer for everything still in the store. Called
    /// on launch and whenever the iPhone becomes reachable.
    @MainActor
    func flushPendingQueue() {
        guard let store = pendingStore, !store.pending.isEmpty else { return }
        let directory = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("pending-rides", isDirectory: true)
        for ride in store.pending {
            let url = directory.appendingPathComponent("\(ride.id).json")
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            _ = transferRide(at: url, rideId: ride.id)
        }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            self.isReachable = session.isReachable
            // Activation is the right moment to drain the queue —
            // before this we have no session to call transferFile on.
            self.flushPendingQueue()
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = session.isReachable
            if session.isReachable {
                self.flushPendingQueue()
            }
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.lastIncomingMessage = message }
    }

    /// Called when the iPhone updates its application context (Phase B
    /// itinerary push). The OS delivers the *latest* value only, with
    /// intermediate updates dropped — exactly the right semantics for
    /// a library snapshot.
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        ingestApplicationContext(applicationContext)
    }

    /// Called by the OS when a queued transfer finishes (or fails).
    /// On success we delete the local file — the iPhone has it now.
    /// On error we leave the file in place; the next reachability
    /// change will retry automatically via `flushPendingQueue`.
    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        let url = fileTransfer.file.fileURL
        let metadata = fileTransfer.file.metadata ?? [:]
        let rideIdStr = metadata["rideId"] as? String

        if let error {
            logger.error("File transfer failed for \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return
        }

        // Success — drop the local copy so we don't re-send next time.
        Task { @MainActor in
            if let rideIdStr, let rideId = Int64(rideIdStr) {
                self.pendingStore?.remove(id: rideId)
                self.logger.notice("Transfer succeeded for ride \(rideId, privacy: .public); local file removed")
            } else {
                try? FileManager.default.removeItem(at: url)
                self.logger.notice("Transfer succeeded for \(url.lastPathComponent, privacy: .public); raw file removed")
            }
        }
    }
}
