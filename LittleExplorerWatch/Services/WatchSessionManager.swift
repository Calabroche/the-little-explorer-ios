import Foundation
import Observation
import WatchConnectivity

/// Watch-side counterpart to the iPhone's WatchSessionManager.
/// Mirrors the same message contract.
@Observable
final class WatchSessionManager: NSObject, WCSessionDelegate {
    private(set) var isReachable = false
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
            print("Watch send error: \(error)")
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.isReachable = session.isReachable }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.isReachable = session.isReachable }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.lastIncomingMessage = message }
    }
}
