import Foundation
import Observation
import WatchConnectivity

/// Two-way bridge between iPhone and Apple Watch.
///
/// Messages we exchange:
///   { "kind": "rideState", ... } — phone → watch when a ride is in progress
///   { "kind": "rideControl", "action": "start"|"pause"|"stop" } — watch → phone
///   { "kind": "rideMetrics", "heartRate": Int } — watch → phone (when watch tracks HR)
@Observable
final class WatchSessionManager: NSObject, WCSessionDelegate {
    private(set) var isReachable = false
    private(set) var isPaired = false
    var lastIncomingMessage: [String: Any] = [:]

    private let session: WCSession?

    override init() {
        self.session = WCSession.isSupported() ? WCSession.default : nil
        super.init()
        guard let session else { return }
        session.delegate = self
        session.activate()
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

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif
}
