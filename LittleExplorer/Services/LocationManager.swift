import CoreLocation
import Foundation
import Observation

@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate {
    var lastLocation: CLLocation?
    var authorizationStatus: CLAuthorizationStatus
    var isTracking = false

    private let manager = CLLocationManager()
    private var trackContinuation: AsyncStream<CLLocation>.Continuation?

    override init() {
        self.authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .fitness
        manager.allowsBackgroundLocationUpdates = false // flipped on when ride starts
        manager.pausesLocationUpdatesAutomatically = false
    }

    func requestAuthorization() {
        switch authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse: manager.requestAlwaysAuthorization()
        default: break
        }
    }

    /// Stream of locations while a ride is active. Caller must keep the
    /// stream alive (via `for await`) — cancellation stops updates.
    func startTracking() -> AsyncStream<CLLocation> {
        manager.allowsBackgroundLocationUpdates = true
        manager.startUpdatingLocation()
        isTracking = true
        return AsyncStream { continuation in
            self.trackContinuation = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.stopTracking() }
            }
        }
    }

    func stopTracking() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        trackContinuation?.finish()
        trackContinuation = nil
        isTracking = false
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        authorizationStatus = status
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        lastLocation = last
        trackContinuation?.yield(last)
    }
}
