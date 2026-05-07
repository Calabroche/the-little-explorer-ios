import CoreLocation
import Foundation
import Observation

/// Drives an in-progress ride: aggregates GPS samples, computes distance/speed/
/// elevation, pushes Live Activity updates, and forwards state to the watch.
@Observable
@MainActor
final class RideTracker {
    enum Phase: Equatable { case idle, recording, paused }

    private(set) var phase: Phase = .idle
    private(set) var distanceMeters: Double = 0
    private(set) var elevationGainM: Double = 0
    private(set) var elapsed: TimeInterval = 0
    private(set) var currentSpeedKmh: Double = 0
    private(set) var path: [CLLocationCoordinate2D] = []

    private var startedAt: Date?
    private var trackingTask: Task<Void, Never>?
    private var clockTask: Task<Void, Never>?
    private var lastLocation: CLLocation?

    private let location: LocationManager
    private let activityManager: RideActivityManager
    private let watch: WatchSessionManager

    init(
        location: LocationManager,
        activityManager: RideActivityManager,
        watch: WatchSessionManager,
    ) {
        self.location = location
        self.activityManager = activityManager
        self.watch = watch
    }

    func start() async {
        guard phase == .idle else { return }
        location.requestAuthorization()
        startedAt = .now
        phase = .recording
        await activityManager.start(sportLabel: "Ride")
        startClock()
        trackingTask = Task { [stream = location.startTracking()] in
            for await loc in stream {
                await self.ingest(loc)
            }
        }
    }

    func pause() {
        guard phase == .recording else { return }
        phase = .paused
        clockTask?.cancel()
    }

    func resume() {
        guard phase == .paused else { return }
        phase = .recording
        startClock()
    }

    func stop() async {
        trackingTask?.cancel()
        clockTask?.cancel()
        location.stopTracking()
        await activityManager.end()
        phase = .idle
        // Reset for next ride.
        distanceMeters = 0
        elevationGainM = 0
        elapsed = 0
        currentSpeedKmh = 0
        path.removeAll()
        lastLocation = nil
        startedAt = nil
    }

    // MARK: - Private

    private func startClock() {
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.phase == .recording, let start = self.startedAt else { continue }
                self.elapsed = Date.now.timeIntervalSince(start)
                await self.pushLiveUpdate()
            }
        }
    }

    private func ingest(_ loc: CLLocation) async {
        path.append(loc.coordinate)
        if let last = lastLocation {
            let delta = loc.distance(from: last)
            // Filter spurious GPS noise (< 2 m is below typical accuracy).
            if delta > 2 {
                distanceMeters += delta
                if loc.altitude > last.altitude {
                    elevationGainM += loc.altitude - last.altitude
                }
            }
        }
        lastLocation = loc
        currentSpeedKmh = max(0, loc.speed) * 3.6
    }

    private func pushLiveUpdate() async {
        let state = RideActivityAttributes.RideState(
            distanceKm: distanceMeters / 1000,
            durationSec: elapsed,
            speedKmh: currentSpeedKmh,
            elevationGainM: elevationGainM,
            heartRate: nil,
            nextManeuver: nil,
            nextManeuverDistanceM: nil,
            nextManeuverSymbol: nil,
        )
        await activityManager.update(state)
        watch.send([
            "kind": "rideState",
            "distanceKm": state.distanceKm,
            "durationSec": state.durationSec,
            "speedKmh": state.speedKmh,
            "elevationGainM": state.elevationGainM,
        ])
    }
}
