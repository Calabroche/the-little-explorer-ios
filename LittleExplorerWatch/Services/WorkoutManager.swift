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
    private(set) var maxSpeedKmh: Double = 0
    private(set) var heartRate: Int?
    private(set) var maxHeartRate: Int = 0
    /// Sum of positive altitude deltas with a 0.5 m noise floor. Same
    /// algorithm as the iOS PendingRide → RideRecord conversion so the
    /// number the rider sees during the ride matches what shows up in
    /// the activity feed afterwards.
    private(set) var elevationGain: Double = 0
    /// Set when the user has denied location access. The view uses
    /// this to render an "open Settings" hint instead of silently
    /// recording a ride with no GPS trace.
    private(set) var locationDenied = false

    /// Derived: average speed over the whole ride. Returns 0 until
    /// any distance has been accumulated.
    var avgSpeedKmh: Double {
        guard elapsed > 0 else { return 0 }
        return (distanceMeters / 1000) / (elapsed / 3600)
    }

    /// Derived: average HR over all collected samples. nil if no HR
    /// samples have been collected yet.
    var avgHeartRate: Int? {
        guard !bufferedHRSamples.isEmpty else { return nil }
        let sum = bufferedHRSamples.map(\.value).reduce(0, +)
        return Int(sum / Double(bufferedHRSamples.count))
    }

    // ── Dependencies ───────────────────────────────────────────────
    private let healthStore = HKHealthStore()
    private let store: PendingRideStore
    /// Crash-recovery scratch file. Persisted every ~30 s while a
    /// ride is active so a Watch reboot doesn't lose the data.
    private let inProgress = InProgressRideStore()
    /// Voice nav coach (Phase E.2). Bound to the active itinerary
    /// when start(itinerary:) is called; receives every GPS fix to
    /// fire the right announcement at the right moment.
    let navigation = NavigationGuide()
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

    /// Set on launch if the previous run crashed mid-ride and left an
    /// orphan snapshot on disk. UI checks this and prompts the user
    /// to either resume (recover whatever was buffered) or finalize
    /// (drop the snapshot, save what we have as a complete pending
    /// ride). Cleared by either action.
    private(set) var pendingRecovery: InProgressSnapshot?

    /// Itinerary id the user picked at start time. Plumbed through to
    /// the PendingRide so the iPhone (and later Strava / backend) knows
    /// which planned route was followed. nil when the user starts a
    /// freeform ride.
    private var activeItineraryId: String?

    /// Full itinerary the rider is following — keeps the geometry +
    /// metadata around so the Watch map view can render the planned
    /// route without re-fetching from the cache. Set by start(itinerary:).
    private(set) var activeItinerary: Itinerary?

    /// Most recent accepted GPS fix, exposed as a SwiftUI-friendly
    /// CLLocationCoordinate2D. Drives the map's "you are here" marker
    /// during a ride. nil before the first fix arrives.
    private(set) var latestCoordinate: CLLocationCoordinate2D?

    init(store: PendingRideStore, session: WatchSessionManager? = nil) {
        self.store = store
        self.sessionManager = session
        // Check for a crash-leftover from the previous launch — we
        // surface it to the UI without auto-resuming, so the user
        // explicitly chooses what to do with stale data.
        self.pendingRecovery = inProgress.loadIfFresh()
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

    /// Convenience overload that records the itinerary the user picked
    /// — its id is plumbed into the resulting PendingRide so the iPhone
    /// (and Strava sync-back) can correlate the ride to the planned
    /// route, and the full itinerary (incl. geometry) is kept so the
    /// Watch map view can render the planned path. Behavior is
    /// otherwise identical to `start()`.
    func start(itinerary: Itinerary) async {
        activeItineraryId = itinerary.id
        activeItinerary = itinerary
        // Load the maneuvers into the voice coach BEFORE start() so
        // the first GPS fix already has a step sequence to compare
        // against. Skips silently when steps is nil (older itineraries
        // without OSRM step data).
        navigation.setItinerary(itinerary)
        await start()
    }

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
        // Phase F: ping the iPhone so it can open a Live Activity on
        // the lock screen / Dynamic Island. Carry the itinerary
        // geometry (downsampled to ≤100 points to fit the 4KB
        // ActivityKit budget) when this is a planned ride — the
        // widget renders it as a route line on its mini map.
        let polyline = downsampleRoute(activeItinerary?.geometry, max: 100)
        sessionManager?.sendRideStarted(sportLabel: "Cyclisme", routePolyline: polyline)
        logger.notice("Workout started")
    }

    /// Stride-sample a coordinate sequence down to at most `max`
    /// points so the encoded Live Activity payload stays well under
    /// ActivityKit's 4 KB ContentState budget. Returns nil for a nil
    /// input so the call-site can spread `?? nil` without ceremony.
    private func downsampleRoute(_ coords: [Coordinate]?, max: Int) -> [[Double]]? {
        guard let coords, !coords.isEmpty else { return nil }
        guard coords.count > max else {
            return coords.map { [$0.lat, $0.lng] }
        }
        let step = Swift.max(1, coords.count / max)
        return Swift.stride(from: 0, to: coords.count, by: step).map { i in
            [coords[i].lat, coords[i].lng]
        }
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

        // Clear the crash-recovery snapshot — ride ended cleanly, no
        // need to surface a "Recover?" prompt at next launch.
        inProgress.clear()

        // Tell the iPhone to dismiss the Live Activity. Best-effort;
        // if the phone wasn't reachable a transferUserInfo retry
        // catches up (see WatchSessionManager.sendRideEnded).
        sessionManager?.sendRideEnded()

        // Reset state so the StartView is ready for another ride.
        // Done unconditionally so the user is always returned to home.
        isActive = false
        isPaused = false
        self.session = nil
        builder = nil
        self.startedAt = nil
        elapsed = 0
        activeItineraryId = nil
        activeItinerary = nil
        latestCoordinate = nil
        maxSpeedKmh = 0
        maxHeartRate = 0
        elevationGain = 0
        // Clear the nav coach so the next ride doesn't fire stale
        // announcements before its own itinerary loads.
        navigation.setItinerary(nil)
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
            var ticksSinceSnapshot = 0
            var ticksSinceLiveUpdate = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                guard self.isActive, !self.isPaused, let start = self.startedAt else { continue }
                self.elapsed = Date.now.timeIntervalSince(start)
                // Crash-recovery snapshot every 30 ticks (~30 s).
                // Cheap (a few KB written atomically) and bounded by
                // the ride length. Means a Watch reboot at most loses
                // 30 s of trace data.
                ticksSinceSnapshot += 1
                if ticksSinceSnapshot >= 30 {
                    self.persistSnapshot()
                    ticksSinceSnapshot = 0
                }
                // Live Activity push every 3 ticks (~3 s). 1 Hz is
                // faster than the lock screen redraws anyway and
                // would waste battery; 3 s is fast enough that the
                // rider's glance always sees a recent number.
                ticksSinceLiveUpdate += 1
                if ticksSinceLiveUpdate >= 3 {
                    self.sendLiveActivityUpdate()
                    ticksSinceLiveUpdate = 0
                }
            }
        }
    }

    /// Snapshot current ride state and ship it to the iPhone for the
    /// Live Activity. Cheap — just packs ~7 numbers into a dict and
    /// hands it to WCSession.sendMessage. No-op when there's no
    /// session manager wired (e.g. unit tests).
    private func sendLiveActivityUpdate() {
        sessionManager?.sendRideUpdate(
            distanceKm:     distanceMeters / 1000,
            durationSec:    elapsed,
            speedKmh:       speedKmh,
            elevationGainM: elevationGain,
            heartRate:      heartRate,
            userLat:        latestCoordinate?.latitude,
            userLng:        latestCoordinate?.longitude,
        )
    }

    /// Convert the current in-memory buffer into an InProgressSnapshot
    /// and hand it to the recovery store. Called automatically every
    /// ~30 s by the clock loop.
    private func persistSnapshot() {
        guard let startedAt else { return }
        let fixes = bufferedFixes.map {
            InProgressSnapshot.Fix(lat: $0.coordinate.latitude, lng: $0.coordinate.longitude, alt: $0.altitude, t: $0.timestamp)
        }
        let hrSamples = bufferedHRSamples.map { InProgressSnapshot.HRSample(t: $0.t, value: $0.value) }
        let snapshot = InProgressSnapshot(
            startedAt:  startedAt,
            lastUpdate: .now,
            elapsed:    elapsed,
            distanceM:  distanceMeters,
            fixes:      fixes,
            hrSamples:  hrSamples,
        )
        inProgress.save(snapshot)
    }

    /// Recovery action: take the orphan snapshot from a previous
    /// crashed run and turn it into a regular PendingRide (one that
    /// shows up in the "N en attente" pill and gets shipped to the
    /// iPhone on next WCSession activation). Use this when the user
    /// taps "Recover" on the launch dialog — we don't auto-resume
    /// recording because the user is no longer mid-ride, but we don't
    /// want to lose the buffered data either.
    func finalizeRecovery() {
        guard let snap = pendingRecovery else { return }
        // Synthesize a PendingRide from the snapshot. Same shape as
        // buildPendingRide() but reading from the on-disk snap.
        let id = -Int64(snap.startedAt.timeIntervalSince1970 * 1000)
        let coords = snap.fixes.map { Coordinate(lat: $0.lat, lng: $0.lng) }
        let times  = snap.fixes.map { $0.t.timeIntervalSince(snap.startedAt) }
        let alts   = snap.fixes.map { $0.alt }
        let hr     = snap.hrSamples.map { $0.value }
        let ride = PendingRide(
            id: id,
            date: ISO8601DateFormatter().string(from: snap.startedAt),
            durationSeconds: snap.elapsed,
            gps: coords,
            timeS: times,
            altitude: alts,
            heartrate: hr,
            distanceM: snap.distanceM,
            sport: "cycling",
            // Crash-recovery doesn't know the itinerary id (it's not
            // in the snapshot). v1: nil. Phase D will add it to the
            // snapshot persistence to round-trip cleanly.
            itineraryId: nil,
        )
        let url = store.save(ride)
        logger.notice("Recovered orphan ride \(id, privacy: .public): \(coords.count) GPS points, \(snap.distanceM, format: .fixed(precision: 0), privacy: .public) m")
        if let url {
            sessionManager?.transferRide(at: url, rideId: ride.id)
        }
        discardRecovery()
    }

    /// Drop the recovery snapshot without saving it (user tapped
    /// "Discard" on the launch dialog).
    func discardRecovery() {
        inProgress.clear()
        pendingRecovery = nil
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
        //
        // Edge case: when `fixes.count < 2` (zero GPS fixes — happens in
        // the simulator without location simulation, or on a real ride
        // ended before any fix arrived), `1..<fixes.count` becomes
        // `1..<0` which CRASHES with "Range requires lowerBound <= upperBound".
        // Guard with a positive lower-bound check.
        var totalM: Double = 0
        if fixes.count >= 2 {
            for i in 1..<fixes.count {
                totalM += fixes[i].distance(from: fixes[i - 1])
            }
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
            itineraryId: activeItineraryId,
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
                if Int(value) > maxHeartRate { maxHeartRate = Int(value) }
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

    /// Per-fix ingestion. Indoor / low-signal conditions are the
    /// hard case here: when the rider is sitting still on a bench
    /// or stuck under a roof, GPS fixes drift 5-30 m every second
    /// and `fix.speed` returns -1 (unreliable Doppler). Without a
    /// strict filter the trace accumulates 100+ m of phantom
    /// distance in 30 s of standing around.
    ///
    /// Two-stage filter:
    ///   1. **Quality gate**: drop fixes with horizontalAccuracy
    ///      > 20 m or unknown (was 30 m — too loose for indoor).
    ///   2. **Stationary gate**: classify the fix as stationary
    ///      when (a) Doppler speed is reliable and < 1 m/s, OR (b)
    ///      Doppler speed is unknown AND the implied speed
    ///      (segment / dt vs last fix) is < 1.5 m/s, OR (c) the
    ///      raw segment is < 8 m. Stationary fixes refresh the
    ///      anchor (so a long pause doesn't snap a huge jump on
    ///      resume) but don't add to distance.
    ///
    /// Same principle Strava / Garmin apply: trust nothing that
    /// looks like it could be drift, even at the cost of slightly
    /// under-reporting tight slow-speed sections.
    @MainActor
    private func ingest(fixes: [CLLocation]) {
        guard isActive, !isPaused else { return }
        for fix in fixes {
            // Tightened accuracy gate. Indoor "decent" fixes
            // still drift wildly; 20 m is the threshold Strava
            // uses for its own auto-pause heuristic.
            guard fix.horizontalAccuracy > 0, fix.horizontalAccuracy < 20 else { continue }

            let dopplerSpeed = fix.speed   // m/s, -1 = unknown
            let stationary = isStationary(fix: fix, dopplerSpeed: dopplerSpeed)

            if stationary {
                // Don't accumulate distance. DO refresh the anchor
                // and the UI fix so the map marker tracks the
                // rider's current cluster and the next real
                // movement doesn't snap a huge segment.
                speedKmh = 0
                bufferedFixes.append(fix)
                latestCoordinate = fix.coordinate
                navigation.ingest(fix: fix)
                continue
            }

            // Real movement — commit the segment.
            if let last = bufferedFixes.last {
                distanceMeters += fix.distance(from: last)
            }
            // Elevation gain: positive deltas only, with a 0.5 m
            // noise floor so altimeter jitter on flat rides
            // doesn't accumulate phantom climbing.
            if let last = bufferedFixes.last {
                let delta = fix.altitude - last.altitude
                if delta > 0.5 {
                    elevationGain += delta
                }
            }
            bufferedFixes.append(fix)
            let kmh = max(0, dopplerSpeed) * 3.6
            speedKmh = kmh
            if kmh > maxSpeedKmh { maxSpeedKmh = kmh }
            latestCoordinate = fix.coordinate
            // Feed the voice coach. No-op for freeform rides; for
            // itinerary rides this is what triggers the "in 200 m
            // turn left" announcements.
            navigation.ingest(fix: fix)
        }
    }

    /// True if the fix is consistent with the rider being still.
    /// See `ingest(fixes:)` for the full rationale — this is the
    /// drift filter that prevents 60+ m of phantom distance per
    /// minute of indoor standing.
    @MainActor
    private func isStationary(fix: CLLocation, dopplerSpeed: Double) -> Bool {
        // Gold-standard signal: reliable Doppler under 1 m/s
        // (~3.6 km/h, slower than walking) ⇒ definitely stopped.
        if dopplerSpeed >= 0 && dopplerSpeed < 1.0 { return true }

        // Doppler unknown ⇒ infer from position delta.
        guard let last = bufferedFixes.last else {
            // First fix of the ride with no Doppler — be cautious
            // and call it stationary; we need at least one anchor
            // before we can compute a segment anyway.
            return dopplerSpeed < 0
        }
        let segment = fix.distance(from: last)
        let dt = max(0.5, fix.timestamp.timeIntervalSince(last.timestamp))
        let impliedSpeed = segment / dt
        // < 8 m of position change OR < 1.5 m/s implied speed
        // ⇒ indistinguishable from drift.
        return segment < 8 || impliedSpeed < 1.5
    }
}
