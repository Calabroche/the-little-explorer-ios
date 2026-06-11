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
    /// Set when `requestOneShotLocation()` is called before we have permission,
    /// so we can fire the actual request the moment authorization is granted.
    private var pendingOneShot = false

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

    /// One-shot fix for features that just need "where am I right now" (e.g.
    /// finding nearby bike shops) without starting a full tracking session.
    /// The result lands in `lastLocation` via the delegate, which @Observable
    /// publishes to any watching view. If we don't have permission yet, ask
    /// first — `didChangeAuthorization` re-drives this once it's granted.
    func requestOneShotLocation() {
        switch authorizationStatus {
        case .notDetermined:
            pendingOneShot = true
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            break
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
        firePendingOneShotIfAllowed()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        firePendingOneShotIfAllowed()
    }

    private func firePendingOneShotIfAllowed() {
        guard pendingOneShot else { return }
        switch authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            pendingOneShot = false
            manager.requestLocation()
        case .denied, .restricted:
            pendingOneShot = false
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        lastLocation = last
        trackContinuation?.yield(last)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // requestLocation() requires a delegate error handler. A one-shot
        // failure is non-fatal: the view falls back to its manual flow.
        Log.app.error("location one-shot failed: \(error.localizedDescription, privacy: .public)")
    }
}
