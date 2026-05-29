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
    /// API client used to fire the Strava upload on a successful
    /// ingestion. Optional because it's wired in `attach(...)` after
    /// the env is fully built — it stays unset until then.
    private var api: APIClient?
    /// Callback the env wires to `activityStore.refreshLocal(user:)`
    /// so the feed re-reads from the store after a Watch ride lands.
    private var onRideIngested: (@MainActor (Int) -> Void)?
    /// Live Activity manager — mirrors Watch ride state onto the
    /// iPhone's lock screen + Dynamic Island. Optional because it's
    /// wired during env build; nil before attach() runs.
    private weak var activityManager: RideActivityManager?

    override init() {
        self.session = WCSession.isSupported() ? WCSession.default : nil
        super.init()
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    /// Wire the ingestion targets after env construction. Idempotent
    /// — calling it twice just replaces the references.
    func attach(localStore: LocalRideStore, api: APIClient, itineraries: ItineraryStore, activityManager: RideActivityManager, onRideIngested: @MainActor @escaping (Int) -> Void) {
        self.localStore = localStore
        self.api = api
        self.itineraries = itineraries
        self.activityManager = activityManager
        self.onRideIngested = onRideIngested
        // Push the current itinerary library to the Watch on attach.
        // Subsequent saves trigger pushes via `syncItinerariesToWatch`.
        Task { @MainActor in self.syncItinerariesToWatch() }
    }

    private weak var itineraries: ItineraryStore?

    /// Snapshot the iPhone's current itinerary library into a compact
    /// representation and hand it to WatchConnectivity as the *latest*
    /// application context. WCSession dedupes against the previous
    /// context so re-calling this on every save is cheap.
    @MainActor
    func syncItinerariesToWatch() {
        guard let session, let itineraries else { return }
        // Encode each Itinerary as Data so we don't have to mirror
        // the struct in Swift dictionaries. Watch decodes back.
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(itineraries.items) else {
            Log.watch.warning("syncItinerariesToWatch: encode failed")
            return
        }
        do {
            try session.updateApplicationContext([
                "kind": "itineraries",
                "data": data,
            ])
            Log.watch.notice("Pushed \(itineraries.items.count) itineraries to Watch (\(data.count) bytes)")
        } catch {
            Log.watch.error("Failed to push itineraries: \(error.localizedDescription, privacy: .public)")
        }
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
        Task { @MainActor in
            self.lastIncomingMessage = message
            await self.handleRideLifecycle(message)
        }
    }

    /// Same dispatch as `didReceiveMessage`, but for messages that
    /// arrive via the durable `transferUserInfo` channel. We use
    /// this for rideStarted / rideEnded so the iPhone catches up
    /// even if it was unreachable at the moment the watch fired.
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in
            await self.handleRideLifecycle(userInfo)
        }
    }

    /// Same dispatch as the other receive entry-points, but for
    /// the Watch's `updateApplicationContext` channel. This is
    /// the path we use for in-ride live updates so the lock
    /// screen sees fresh numbers even after a reachability gap.
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            await self.handleRideLifecycle(applicationContext)
        }
    }

    /// Dispatch a "kind"-tagged WC payload from the Watch onto the
    /// iPhone's Live Activity manager. Tolerates missing fields —
    /// we want the activity to surface even with partial state.
    @MainActor
    private func handleRideLifecycle(_ payload: [String: Any]) async {
        guard let kind = payload["kind"] as? String,
              let activityManager else { return }
        switch kind {
        case "rideStarted":
            let sportLabel = payload["sportLabel"] as? String ?? "Cyclisme"
            let routePolyline = payload["routePolyline"] as? [[Double]]
            await activityManager.start(sportLabel: sportLabel, routePolyline: routePolyline)
        case "rideUpdate":
            let state = RideActivityAttributes.RideState(
                distanceKm:           payload["distanceKm"]     as? Double ?? 0,
                durationSec:          payload["durationSec"]    as? Double ?? 0,
                speedKmh:             payload["speedKmh"]       as? Double ?? 0,
                elevationGainM:       payload["elevationGainM"] as? Double ?? 0,
                heartRate:            payload["heartRate"]      as? Int,
                nextManeuver:         nil,
                nextManeuverDistanceM: nil,
                nextManeuverSymbol:   nil,
                userLat:              payload["userLat"]        as? Double,
                userLng:              payload["userLng"]        as? Double,
            )
            await activityManager.update(state)
        case "rideEnded":
            await activityManager.end()
        default:
            break
        }
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

        // Phase 3: fire-and-forget Strava upload so the ride lands in
        // the user's Strava account (and from there into our backend's
        // `activities` table via the existing webhook → sync-one
        // pipeline). The local copy stays in the feed regardless;
        // Phase 4 will deduplicate once the Strava-side activity
        // surfaces with its own positive id.
        if let api {
            Task.detached(priority: .background) { [record] in
                do {
                    let result = try await api.uploadToStrava(record: record)
                    await MainActor.run {
                        Log.watch.notice("Strava upload kicked off — uploadId=\(result.uploadId ?? -1, privacy: .public), status=\(result.status ?? "?", privacy: .public)")
                    }
                } catch {
                    await MainActor.run {
                        Log.watch.error("Strava upload failed for ride \(record.id): \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
        } else {
            Log.watch.notice("Strava upload skipped — APIClient not wired yet")
        }
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif
}
