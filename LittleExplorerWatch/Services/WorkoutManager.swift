import CoreLocation
import Foundation
import HealthKit
import Observation
import os

/// Drives a standalone ride on the Apple Watch.
///
///   • `HKWorkoutSession` keeps the app alive in background + lets
///     HKLiveWorkoutBuilder auto-collect heart rate from the wrist.
///   • `CLLocationManager` provides the GPS trace — sampled, validated
///     (drop fixes with poor horizontal accuracy), and used to compute
///     distance + speed. We do NOT trust HK's accelerometer-derived
///     distance for cycling — it's only OK for running.
///   • Each accepted GPS fix is appended to the live buffer. On End,
///     the buffer is serialised into a `PendingRide` and handed to
///     `PendingRideStore` for transfer in Phase 2.
///
/// All UI-visible state lives here as `@Observable` properties so the
/// view can re-render without prop-drilling.
@Observable
@MainActor
final class WorkoutManager: NSObject {
    // ── Observable surface ─────────────────────────────────────────
    private(set) var isActive = false
    private(set) var isPaused = false
    private(set) var elapsed: TimeInterval = 0
    private(set) var distanceMeters: Double = 0
    private(set) var speedKmh: Double = 0
    private(set) var heartRate: Int?
    /// Set when the user has denied location access. The view uses
    /// this to render an "open Settings" hint instead of silently
    /// recording a ride with no GPS trace.
    private(set) var locationDenied = false

    // ── Dependencies ───────────────────────────────────────────────
    private let healthStore = HKHealthStore()
    private let store: PendingRideStore
    private weak var sessionManager: WatchSessionManager?
    private let logger = Logger(subsystem: "com.calabrese.little-explorer-ios.watchkitapp", category: "WorkoutManager")

    // ── Workout session + builder ──────────────────────────────────
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var startedAt: Date?
    private var clockTask: Task<Void, Never>?

    // ── Location ───────────────────────────────────────────────────
    // CLLocationManager itself is not Sendable — keep it main-actor
    // bound and route delegate callbacks through hops back to the
    // actor.
    private let locationManager = CLLocationManager()

    // ── Buffer for the ride being recorded ─────────────────────────
    private var bufferedFixes: [CLLocation] = []
    private var bufferedHRSamples: [(t: Date, value: Double)] = []

    init(store: PendingRideStore, session: WatchSessionManager? = nil) {
        self.store = store
        self.sessionManager = session
        super.init()
        locationManager.delegate = self
        // Best-accuracy GPS — workout sessions get fewer power-budget
        // penalties from the OS than background apps so this is OK.
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        // 5 m filter cuts redundant samples when stopped at lights
        // without losing tracking resolution.
        locationManager.distanceFilter = 5
    }

    // ── Lifecycle ──────────────────────────────────────────────────

    func start() async {
        guard !isActive else { return }
        await requestHealthKit()
        await ensureLocationAuthorization()

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .cycling
        configuration.locationType = .outdoor

        do {
            session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            builder = session?.associatedWorkoutBuilder()
        } catch {
            logger.error("Couldn't create workout session: \(error.localizedDescription, privacy: .public)")
            return
        }
        builder?.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
        session?.delegate = self
        builder?.delegate = self

        let now = Date()
        startedAt = now
        bufferedFixes.removeAll(keepingCapacity: true)
        bufferedHRSamples.removeAll(keepingCapacity: true)
        distanceMeters = 0
        speedKmh = 0
        heartRate = nil

        session?.startActivity(with: now)
        try? await builder?.beginCollection(at: now)
        locationManager.startUpdatingLocation()

        isActive = true
        isPaused = false
        startClock()
        logger.notice("Workout started")
    }

    /// Toggle pause/resume. Always flips the local `isPaused` state
    /// even if the underlying HKWorkoutSession is in a degraded state
    /// (simulator, denied permissions, etc.) — the user must be able
    /// to control the ride from the UI regardless of what HK is up to.
    func togglePause() {
        if isPaused {
            session?.resume()                            // no-op if session is nil/broken
            locationManager.startUpdatingLocation()
            isPaused = false
        } else {
            session?.pause()
            locationManager.stopUpdatingLocation()
            isPaused = true
        }
        logger.notice("togglePause -> isPaused=\(self.isPaused)")
    }

    /// End the workout. Designed to ALWAYS succeed from the user's
    /// POV: flushes whatever's in the buffer to disk and resets the
    /// state machine, even if HKWorkoutSession is broken (failed auth,
    /// simulator quirks, etc.). The HK calls are best-effort with a
    /// 3-second cap so the UI never hangs.
    func end() async {
        // No early-return: even if start() never fully kicked off, the
        // user pressed End and they deserve a state reset.
        logger.notice("end() called; isActive=\(self.isActive), session=\(self.session == nil ? "nil" : "set")")
        locationManager.stopUpdatingLocation()

        // Best-effort HK teardown with timeout. HKWorkoutSession.end()
        // is synchronous (just enqueues the state change), but the
        // builder's endCollection / finishWorkout are awaitable and
        // can hang in the simulator if the session never actually
        // started — wrap with a 3-second budget.
        session?.end()
        await withTimeout(seconds: 3) { [builder] in
            try? await builder?.endCollection(at: .now)
            _ = try? await builder?.finishWorkout()
        }
        clockTask?.cancel()

        // Flush the buffer to disk — only if we have a startedAt
        // (otherwise there's nothing meaningful to save).
        if let startedAt {
            let ride = buildPendingRide(startedAt: startedAt)
            let url = store.save(ride)
            logger.notice("Workout ended; saved pending ride \(ride.id, privacy: .public) with \(ride.gps.count) GPS points")
            // Kick off the WCSession transfer immediately. If the iPhone
            // isn't reachable, the transfer queues and resumes
            // automatically on next reachability — that's the whole point
            // of `transferFile` vs `sendMessage`.
            if let url {
                sessionManager?.transferRide(at: url, rideId: ride.id)
            }
        } else {
            logger.warning("end() called with no startedAt — nothing to save")
        }

        // Reset state so the StartView is ready for another ride.
        // Done unconditionally so the user is always returned to home.
        isActive = false
        isPaused = false
        self.session = nil
        builder = nil
        self.startedAt = nil
        elapsed = 0
        bufferedFixes.removeAll()
        bufferedHRSamples.removeAll()
    }

    /// Race an async block against a wall-clock timeout. Used to cap
    /// HK teardown so the End button never leaves the UI hung if
    /// HealthKit decides to take forever (or never reply at all,
    /// which the simulator likes to do when auth is missing).
    private func withTimeout(seconds: Double, _ block: @escaping @Sendable () async -> Void) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await block() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }
            // Take whichever finishes first, then cancel the other.
            await group.next()
            group.cancelAll()
        }
    }

    // ── Permissions ───────────────────────────────────────────────

    private func requestHealthKit() async {
        let typesToShare: Set<HKSampleType> = [HKQuantityType.workoutType()]
        let typesToRead: Set<HKObjectType> = [
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.distanceCycling),
            HKObjectType.workoutType(),
        ]
        do {
            try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
        } catch {
            logger.warning("HealthKit authorization failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func ensureLocationAuthorization() async {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
            // CLLocationManager doesn't await — we proceed optimistically
            // and the delegate callback will mark `locationDenied` if
            // the user refuses. Subsequent ride starts pick that up.
        case .denied, .restricted:
            locationDenied = true
        default:
            locationDenied = false
        }
    }

    // ── Clock loop (1 Hz UI refresh while active) ──────────────────

    private func startClock() {
        clockTask?.cancel()
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                guard self.isActive, !self.isPaused, let start = self.startedAt else { continue }
                self.elapsed = Date.now.timeIntervalSince(start)
            }
        }
    }

    // ── Build a PendingRide from the buffer ───────────────────────

    private func buildPendingRide(startedAt: Date) -> PendingRide {
        let fixes = bufferedFixes
        let baseTime = fixes.first?.timestamp ?? startedAt

        // Path + per-point timestamps (relative seconds-from-start).
        let coords = fixes.map { Coordinate(lat: $0.coordinate.latitude, lng: $0.coordinate.longitude) }
        let times  = fixes.map { $0.timestamp.timeIntervalSince(baseTime) }
        let alts   = fixes.map { $0.altitude }

        // HR samples are timestamped from HK. Align them to the GPS
        // timeline by nearest-neighbour interpolation so the iPhone
        // can chart HR over distance without re-doing the work. Empty
        // array when no HR was collected.
        let hrAligned = bufferedHRSamples.isEmpty
            ? []
            : alignHRToFixes(fixes: fixes, samples: bufferedHRSamples)

        // Total distance from the GPS chain. Strava uses the same
        // approach (sum of segment lengths), which gives nice round
        // numbers on flat rides and slightly under-counts on switchbacks.
        var totalM: Double = 0
        for i in 1..<fixes.count {
            totalM += fixes[i].distance(from: fixes[i - 1])
        }

        // ID convention: negative timestamp (ms) so it can't collide
        // with a positive Strava activity id when the iPhone merges
        // the lists. Matches LocalRideStore on iOS.
        let id = -Int64(startedAt.timeIntervalSince1970 * 1000)

        return PendingRide(
            id: id,
            date: ISO8601DateFormatter().string(from: startedAt),
            durationSeconds: Date.now.timeIntervalSince(startedAt),
            gps: coords,
            timeS: times,
            altitude: alts,
            heartrate: hrAligned,
            distanceM: totalM,
            sport: "cycling",
        )
    }

    /// Nearest-neighbour resample of (timestamped) HR samples onto the
    /// GPS fix timeline. Each output value is the HR sample closest in
    /// time to the corresponding fix. Trades accuracy for simplicity —
    /// for our chart purposes this is fine.
    private func alignHRToFixes(
        fixes: [CLLocation],
        samples: [(t: Date, value: Double)],
    ) -> [Double] {
        guard !samples.isEmpty else { return [] }
        let sorted = samples.sorted { $0.t < $1.t }
        return fixes.map { fix in
            // Linear scan; samples are small (≤ a few hundred per ride).
            var bestDiff = Double.infinity
            var best = sorted[0].value
            for s in sorted {
                let diff = abs(s.t.timeIntervalSince(fix.timestamp))
                if diff < bestDiff {
                    bestDiff = diff
                    best = s.value
                } else if diff > bestDiff {
                    // sorted timestamps → can early-exit once we start
                    // getting farther away.
                    break
                }
            }
            return best
        }
    }
}

// ── HKWorkoutSessionDelegate ──────────────────────────────────────

extension WorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date,
    ) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in
            self.logger.error("Workout session failed: \(message, privacy: .public)")
        }
    }
}

// ── HKLiveWorkoutBuilderDelegate ──────────────────────────────────

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType,
                  let statistics = workoutBuilder.statistics(for: quantityType) else { continue }
            Task { @MainActor [weak self] in
                self?.applyStatistics(statistics, for: quantityType)
            }
        }
    }

    @MainActor
    private func applyStatistics(_ stats: HKStatistics, for type: HKQuantityType) {
        switch type {
        case HKQuantityType(.heartRate):
            let unit = HKUnit.count().unitDivided(by: .minute())
            if let value = stats.mostRecentQuantity()?.doubleValue(for: unit) {
                heartRate = Int(value)
                bufferedHRSamples.append((t: Date.now, value: value))
            }
        default:
            // We deliberately ignore HK's distanceCycling — our GPS
            // chain is the source of truth (more accurate when GPS is
            // available, fails gracefully to 0 when not).
            break
        }
    }
}

// ── CLLocationManagerDelegate ─────────────────────────────────────

extension WorkoutManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let fixes = locations
        Task { @MainActor in
            self.ingest(fixes: fixes)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in
            self.logger.warning("Location error: \(message, privacy: .public)")
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.locationDenied = (status == .denied || status == .restricted)
        }
    }

    /// Per-fix ingestion. Reject low-quality samples (negative
    /// accuracy = unknown, or > 30 m horizontal error = urban canyon
    /// noise) so the trace doesn't get a "GPS spike" that adds 50 m
    /// of phantom distance every time we pass under a bridge.
    @MainActor
    private func ingest(fixes: [CLLocation]) {
        guard isActive, !isPaused else { return }
        for fix in fixes {
            guard fix.horizontalAccuracy > 0, fix.horizontalAccuracy < 30 else { continue }
            // Distance update — append, then update the running total
            // and current speed from the latest pair.
            if let last = bufferedFixes.last {
                distanceMeters += fix.distance(from: last)
            }
            bufferedFixes.append(fix)
            // CLLocation.speed is m/s; mask to >= 0 (the API returns
            // a negative value when speed is unknown).
            speedKmh = max(0, fix.speed) * 3.6
        }
    }
}
