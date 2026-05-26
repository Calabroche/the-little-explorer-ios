import CoreLocation
import Foundation
import Observation

/// Drives an in-progress ride: aggregates GPS samples, computes
/// distance/speed/elevation, pushes Live Activity updates, and
/// forwards state to the watch.
///
/// Phase machine:
///   .idle      → no ride
///   .recording → actively capturing GPS
///   .paused    → temporarily not capturing (clock stopped, GPS stream
///                still open)
///   .finished  → user stopped tracking; data is held in memory
///                pending save() or discard()
@Observable
@MainActor
final class RideTracker {
    enum Phase: Equatable { case idle, recording, paused, finished }

    private(set) var phase: Phase = .idle
    private(set) var distanceMeters: Double = 0
    private(set) var elevationGainM: Double = 0
    private(set) var elevationDescentM: Double = 0
    private(set) var elapsed: TimeInterval = 0
    private(set) var currentSpeedKmh: Double = 0
    private(set) var maxSpeedKmh: Double = 0
    private(set) var path: [CLLocationCoordinate2D] = []
    private(set) var selectedSport: Sport?
    /// Granular sport subtype the user picked (VTT, RPM, Pilates, …).
    /// Stored on the resulting RideRecord as `originalType` so the
    /// detail view can show the precise label and we don't lose the
    /// distinction in the feed.
    private(set) var selectedSubtype: SportSubtype?
    /// True when the current ride is indoor (no GPS, no map). The
    /// view reads this to swap its map view for a metrics-only one.
    var isIndoor: Bool { selectedSubtype?.isOutdoor == false }

    /// Per-sample streams captured during the ride. Match the shape
    /// of `RideRecord.altitude / distanceM / speedKmh / timeS` so
    /// `commitRecord()` can pour them straight into a saved record
    /// and the existing detail view + power model just work.
    private(set) var sampledAltitude: [Double] = []
    private(set) var sampledDistanceM: [Double] = []
    private(set) var sampledSpeedKmh: [Double] = []
    private(set) var sampledTimeS: [Double] = []
    private(set) var sampledGps: [Coordinate] = []

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

    /// Start a ride for the given subtype. Outdoor subtypes spin up
    /// the GPS stream + Live Activity; indoor subtypes just start a
    /// clock + a Live Activity with the sport name (no GPS = no
    /// map, no distance). The resulting RideRecord at save time
    /// carries the subtype's rawValue as `originalType` so detail
    /// views can show "VTT" / "RPM" / "Pilates" instead of the
    /// generic "Cyclisme" Sport bucket.
    func start(subtype: SportSubtype) async {
        guard phase == .idle else { return }
        selectedSubtype = subtype
        selectedSport = subtype.canonicalSport
        startedAt = .now
        phase = .recording
        await activityManager.start(sportLabel: subtype.displayName)
        startClock()
        if subtype.isOutdoor {
            location.requestAuthorization()
            trackingTask = Task { [stream = location.startTracking()] in
                for await loc in stream {
                    await self.ingest(loc)
                }
            }
        }
        // Indoor: no GPS stream — clock + activity manager carry the
        // metrics (time, estimated calories via MET in commitRecord).
    }

    /// Legacy entry point — still used by the simulator-only sports
    /// row preview / unit tests. Picks a sensible default subtype
    /// for the Sport bucket. New callers should pass a SportSubtype.
    func start(sport: Sport) async {
        let subtype: SportSubtype
        switch sport {
        case .cycling:  subtype = .roadCycling
        case .running:  subtype = .running
        case .hiking:   subtype = .hiking
        case .ski:      subtype = .alpineSki
        case .snowshoe: subtype = .snowshoe
        case .walking:  subtype = .walking
        case .swim:     subtype = .swimming
        }
        await start(subtype: subtype)
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

    /// Stop tracking but keep the captured data in memory until the
    /// user decides to save or discard. The Live Activity ends here
    /// since the ride is no longer in progress.
    func stop() async {
        guard phase == .recording || phase == .paused else { return }
        trackingTask?.cancel()
        clockTask?.cancel()
        location.stopTracking()
        await activityManager.end()
        phase = .finished
    }

    /// Discard the current ride without saving.
    func discard() {
        reset()
    }

    /// Build a RideRecord from the captured streams. Caller persists
    /// it into the LocalRideStore.
    func commitRecord(title customTitle: String?) -> RideRecord? {
        guard let sport = selectedSport, let startedAt else { return nil }
        let endDate = Date()
        let durationSeconds = elapsed > 0 ? elapsed : endDate.timeIntervalSince(startedAt)
        let durationMin = max(0, Int((durationSeconds / 60).rounded()))
        let distanceKm = distanceMeters / 1000
        let avgSpeed = durationSeconds > 0 ? distanceMeters / durationSeconds * 3.6 : 0

        let dateFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "dd MMM yyyy"
            f.locale = Locale(identifier: "fr_FR")
            return f
        }()

        let title: String = {
            let trimmed = (customTitle ?? "").trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return trimmed }
            return "\(sport.displayName) · \(dateFormatter.string(from: startedAt))"
        }()

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let displayDate = dateFormatter.string(from: startedAt).uppercased()

        // Compute slope extrema from the captured altitude / distance
        // streams via the same windowed gradient PowerStream uses.
        let slopes = SlopeMath.windowedSlopes(
            altitude: sampledAltitude,
            distanceM: sampledDistanceM,
            window: 40,
        )
        let maxIncline = slopes.max().map { ($0 * 10).rounded() / 10 }
        let minIncline = slopes.min().map { ($0 * 10).rounded() / 10 }

        let pace: Int? = sport == .running && distanceKm > 0
            ? Int((durationSeconds / distanceKm).rounded())
            : nil

        return RideRecord(
            id: -Int(startedAt.timeIntervalSince1970),  // negative timestamp keeps local ids out of Strava's positive id space
            type: backendType(for: sport),
            originalType: selectedSubtype?.rawValue,
            title: title,
            date: displayDate,
            rawDate: isoFormatter.string(from: startedAt),
            location: nil,
            duration: formatDuration(seconds: durationSeconds),
            durationMin: durationMin,
            distance: (distanceKm * 100).rounded() / 100,
            speed: (avgSpeed * 10).rounded() / 10,
            maxSpeed: (maxSpeedKmh * 10).rounded() / 10,
            elevation: elevationGainM > 0 ? (elevationGainM * 10).rounded() / 10 : nil,
            descent: elevationDescentM > 0 ? (elevationDescentM * 10).rounded() / 10 : nil,
            gps: sampledGps,
            altitude: sampledAltitude.isEmpty ? nil : sampledAltitude,
            speedKmh: sampledSpeedKmh.isEmpty ? nil : sampledSpeedKmh,
            heartrate: nil,
            distanceM: sampledDistanceM.isEmpty ? nil : sampledDistanceM,
            timeS: sampledTimeS.isEmpty ? nil : sampledTimeS,
            maxIncline: maxIncline,
            minIncline: minIncline,
            avgHr: nil,
            maxHr: nil,
            calories: nil,
            np: nil,
            avgPower: nil,
            tss: nil,
            ifFactor: nil,
            vi: nil,
            wkg: nil,
            ef: nil,
            trimp: nil,
            vam: nil,
            ftp: nil,
            weather: nil,
            bestEfforts: nil,
            photos: nil,
            hrZones: nil,
            aed: nil,
            riderKg: nil,
            totalMass: nil,
            paceSPerKm: pace,
        )
    }

    func reset() {
        phase = .idle
        distanceMeters = 0
        elevationGainM = 0
        elevationDescentM = 0
        elapsed = 0
        currentSpeedKmh = 0
        maxSpeedKmh = 0
        path.removeAll()
        sampledAltitude.removeAll()
        sampledDistanceM.removeAll()
        sampledSpeedKmh.removeAll()
        sampledTimeS.removeAll()
        sampledGps.removeAll()
        lastLocation = nil
        startedAt = nil
        selectedSport = nil
        selectedSubtype = nil
    }

    // MARK: - Private

    private func backendType(for sport: Sport) -> String {
        switch sport {
        case .cycling:  return "cycling"
        case .running:  return "running"
        case .hiking:   return "hiking"
        case .ski:      return "ski"
        case .snowshoe: return "snowshoe"
        case .walking:  return "walking"
        case .swim:     return "swim"
        }
    }

    private func formatDuration(seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        let h = s / 3600
        let m = (s % 3600) / 60
        return h > 0 ? "\(h)h \(String(format: "%02d", m))m" : "\(m) min"
    }

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
        let coord = Coordinate(lat: loc.coordinate.latitude, lng: loc.coordinate.longitude)
        path.append(loc.coordinate)
        sampledGps.append(coord)
        sampledAltitude.append(loc.altitude)
        let speedKmh = max(0, loc.speed) * 3.6
        sampledSpeedKmh.append(speedKmh)
        currentSpeedKmh = speedKmh
        if speedKmh > maxSpeedKmh { maxSpeedKmh = speedKmh }

        if let last = lastLocation {
            let delta = loc.distance(from: last)
            if delta > 2 {
                distanceMeters += delta
                let altDelta = loc.altitude - last.altitude
                if altDelta > 0 { elevationGainM += altDelta }
                else if altDelta < 0 { elevationDescentM += -altDelta }
            }
        }
        sampledDistanceM.append(distanceMeters)
        if let startedAt {
            sampledTimeS.append(loc.timestamp.timeIntervalSince(startedAt))
        }
        lastLocation = loc
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

/// Small helper to compute the windowed slope series used by the
/// power model and by max/min incline detection. Lifted here so the
/// tracker can pre-compute slope extrema without depending on the
/// chart-only PowerStream module.
enum SlopeMath {
    static func windowedSlopes(altitude: [Double], distanceM: [Double], window: Int) -> [Double] {
        let len = min(altitude.count, distanceM.count)
        guard len > window * 2 else { return [] }
        var out: [Double] = []
        out.reserveCapacity(len)
        for i in window..<(len - window) {
            let dAlt = altitude[i + window] - altitude[i - window]
            let dDist = distanceM[i + window] - distanceM[i - window]
            if dDist >= 20 {
                let slope = (dAlt / dDist) * 100
                out.append(max(-25, min(25, slope)))
            }
        }
        return out
    }
}
