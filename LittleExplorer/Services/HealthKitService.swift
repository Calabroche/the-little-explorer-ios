import CoreLocation
import Foundation
import HealthKit

/// Bridges Little Explorer's RideRecord into Apple Health as a real
/// `HKWorkout` + optional `HKWorkoutRoute` + heart-rate samples.
///
/// The user grants permission once (system dialog at first call to
/// `requestAuthorization`); afterwards every locally-saved ride flows
/// into the Health app automatically. Rings on Apple Watch get credit,
/// other Health-aware apps (MyFitnessPal, Whoop, etc.) see your rides,
/// and the unified Health → Workouts view shows them next to walks /
/// sleep / resting HR.
///
/// We only WRITE — never read your other Health data. The
/// `requestAuthorization` toShare/read split makes that explicit.
/// HKHealthStore is documented as thread-safe so the class itself
/// stays unisolated; AppEnvironment can hold a plain stored property.
final class HealthKitService {
    /// HealthKit isn't available on iPad before iPadOS 17 nor on
    /// simulator builds without entitlement — callers can check this
    /// to short-circuit gracefully.
    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private let store = HKHealthStore()

    private var writeTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute(),
        ]
        if let hr = HKObjectType.quantityType(forIdentifier: .heartRate) {
            types.insert(hr)
        }
        if let energy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
            types.insert(energy)
        }
        for id in [HKQuantityTypeIdentifier.distanceCycling,
                   .distanceWalkingRunning,
                   .distanceSwimming] {
            if let t = HKObjectType.quantityType(forIdentifier: id) {
                types.insert(t)
            }
        }
        return types
    }

    /// Trigger the system permission dialog. Idempotent — once the
    /// user has answered, this resolves immediately without re-prompting.
    func requestAuthorization() async throws {
        guard Self.isAvailable else {
            throw HealthKitServiceError.notAvailable
        }
        try await store.requestAuthorization(toShare: writeTypes, read: [])
    }

    /// Apple's privacy policy means `authorizationStatus(for:)` returns
    /// the SAME value (`.notDetermined`) whether the user has seen the
    /// prompt and denied it or hasn't seen it at all — they don't want
    /// apps to fingerprint based on "did the user say yes to Health
    /// for app X". The only reliable way to detect denial is to TRY
    /// a tiny test write and see if it errors with .errorAuthorizationDenied.
    ///
    /// This method does exactly that: it attempts a 1-second placeholder
    /// HKWorkout, then immediately deletes it. Result tells us whether
    /// writes will succeed for real rides.
    @MainActor
    func verifyAuthorizationByProbe() async -> AuthorizationProbe {
        guard Self.isAvailable else { return .unavailable }
        do {
            try await requestAuthorization()
        } catch {
            return .unavailable
        }

        // Build a tiny test workout — 1-second walk at "now". This is
        // the cheapest possible proof of write access.
        let now = Date()
        let probe = HKWorkout(
            activityType: .walking,
            start: now,
            end: now.addingTimeInterval(1),
            duration: 1,
            totalEnergyBurned: nil,
            totalDistance: nil,
            metadata: [HKMetadataKeyExternalUUID: "tle-probe-\(UUID().uuidString)"],
        )
        do {
            try await store.save(probe)
            // Clean up immediately — we don't want the probe polluting
            // the user's workout list.
            try? await store.delete(probe)
            return .granted
        } catch let error as NSError {
            if error.code == HKError.errorAuthorizationDenied.rawValue {
                return .denied
            }
            return .denied   // any other failure also blocks the save
        }
    }

    enum AuthorizationProbe: String {
        case granted, denied, unavailable
        var displayLabel: String {
            switch self {
            case .granted:     return "Connecté à Apple Santé"
            case .denied:      return "Permission refusée"
            case .unavailable: return "Santé indisponible"
            }
        }
    }

    /// Write a single `RideRecord` as a workout + route + HR samples.
    /// Idempotent against re-submission: a workout with the same
    /// external UUID is detected and skipped so we never get
    /// duplicates if the user re-saves a ride.
    func saveRide(_ record: RideRecord) async throws {
        guard Self.isAvailable else { return }

        // Idempotency key derived from the ride id (negative for local
        // rides, positive for Strava) so re-saves don't duplicate.
        let externalUUID = "tle-ride-\(record.id)"
        if try await isAlreadySaved(externalUUID: externalUUID) {
            Log.tracking.notice("HealthKit: ride \(externalUUID, privacy: .public) already saved, skipping")
            return
        }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]
        let startDate: Date = isoFormatter.date(from: record.rawDate)
            ?? fallbackFormatter.date(from: record.rawDate)
            ?? Date()
        let endDate: Date = startDate.addingTimeInterval(TimeInterval(record.durationMin) * 60)

        // Build the workout via the modern HKWorkoutBuilder API.
        let config = HKWorkoutConfiguration()
        config.activityType = activityType(for: record.type)
        config.locationType = config.activityType == .swimming ? .unknown : .outdoor

        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        try await builder.beginCollection(at: startDate)

        var samples: [HKSample] = []

        if let distKm = record.distance, distKm > 0,
           let distanceType = distanceTypeId(for: config.activityType)
                .flatMap({ HKQuantityType.quantityType(forIdentifier: $0) }) {
            let qty = HKQuantity(unit: .meter(), doubleValue: distKm * 1000)
            samples.append(HKQuantitySample(type: distanceType, quantity: qty, start: startDate, end: endDate))
        }

        if let calories = estimateCalories(record),
           let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            let qty = HKQuantity(unit: .kilocalorie(), doubleValue: calories)
            samples.append(HKQuantitySample(type: energyType, quantity: qty, start: startDate, end: endDate))
        }

        if let heartrate = record.heartrate,
           let timeS = record.timeS,
           !heartrate.isEmpty, heartrate.count == timeS.count,
           let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) {
            let unit = HKUnit.count().unitDivided(by: .minute())
            for (idx, hr) in heartrate.enumerated() where hr > 0 {
                let timestamp = startDate.addingTimeInterval(timeS[idx])
                let qty = HKQuantity(unit: unit, doubleValue: hr)
                samples.append(HKQuantitySample(type: hrType, quantity: qty, start: timestamp, end: timestamp))
            }
        }

        if !samples.isEmpty {
            try await builder.addSamples(samples)
        }

        // Stamp the external UUID + a few extras for traceability.
        try await builder.addMetadata([
            HKMetadataKeyExternalUUID: externalUUID,
            HKMetadataKeyWorkoutBrandName: "Little Explorer",
        ])

        try await builder.endCollection(at: endDate)
        let workout = try await builder.finishWorkout()

        // Add the GPS route as a HKWorkoutRoute so the Health app's
        // workout-detail map shows the actual path you rode.
        if let workout, !record.gps.isEmpty {
            try await addRoute(record: record, startDate: startDate, workout: workout)
        }

        Log.tracking.notice("HealthKit: saved workout for \(externalUUID, privacy: .public) (\(record.distance ?? 0) km, \(record.durationMin) min)")
    }

    private func addRoute(record: RideRecord, startDate: Date, workout: HKWorkout) async throws {
        let routeBuilder = HKWorkoutRouteBuilder(healthStore: store, device: .local())
        var locations: [CLLocation] = []
        locations.reserveCapacity(record.gps.count)
        for (i, coord) in record.gps.enumerated() {
            let t: TimeInterval
            if let timeS = record.timeS, timeS.indices.contains(i) {
                t = timeS[i]
            } else {
                t = Double(i)
            }
            let altitude: CLLocationDistance
            if let alts = record.altitude, alts.indices.contains(i) {
                altitude = alts[i]
            } else {
                altitude = 0
            }
            let loc = CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: coord.lat, longitude: coord.lng),
                altitude: altitude,
                horizontalAccuracy: 5,
                verticalAccuracy: 5,
                course: -1,
                speed: -1,
                timestamp: startDate.addingTimeInterval(t),
            )
            locations.append(loc)
        }
        if !locations.isEmpty {
            try await routeBuilder.insertRouteData(locations)
        }
        _ = try await routeBuilder.finishRoute(with: workout, metadata: nil)
    }

    /// Look up existing workouts by external UUID. HealthKit doesn't
    /// expose a direct "exists?" API so we query the workout type
    /// with a metadata-key predicate and check the result.
    private func isAlreadySaved(externalUUID: String) async throws -> Bool {
        let workoutType = HKObjectType.workoutType()
        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeyExternalUUID,
            operatorType: .equalTo,
            value: externalUUID,
        )
        let query: [HKSample]? = try await withCheckedThrowingContinuation { continuation in
            let q = HKSampleQuery(
                sampleType: workoutType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: nil,
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples)
                }
            }
            store.execute(q)
        }
        return (query?.isEmpty == false)
    }

    private func activityType(for sport: String) -> HKWorkoutActivityType {
        switch sport.lowercased() {
        case "cycling", "ride", "ebikeride", "mountainbikeride", "gravelride": return .cycling
        case "running", "run", "trailrun":                                       return .running
        case "hiking", "hike":                                                   return .hiking
        case "walking", "walk":                                                  return .walking
        case "ski", "alpineski":                                                 return .downhillSkiing
        case "swim":                                                              return .swimming
        case "snowshoe":                                                          return .snowSports
        default:                                                                  return .cycling
        }
    }

    private func distanceTypeId(for activity: HKWorkoutActivityType) -> HKQuantityTypeIdentifier? {
        switch activity {
        case .cycling:  return .distanceCycling
        case .running, .walking, .hiking: return .distanceWalkingRunning
        case .swimming: return .distanceSwimming
        default:        return nil
        }
    }

    /// Quick MET-based calorie estimate. Conservative but close enough
    /// to feel useful in the daily total — Strava-synced rides bring
    /// their own calories value via the API so this only fires for
    /// iOS-recorded rides without a number.
    private func estimateCalories(_ record: RideRecord) -> Double? {
        if let cals = record.calories, cals > 0 { return Double(cals) }
        guard let distKm = record.distance, distKm > 0, record.durationMin > 0 else { return nil }
        let hours = Double(record.durationMin) / 60.0
        let speed = distKm / hours
        let met: Double
        switch activityType(for: record.type) {
        case .cycling:
            switch speed {
            case ...15:  met = 4.0
            case 15..<20: met = 6.8
            case 20..<25: met = 8.0
            case 25..<30: met = 10.0
            default:      met = 12.0
            }
        case .running:
            met = speed > 12 ? 10 : 8.5
        case .hiking:   met = 6.0
        case .walking:  met = 3.5
        case .swimming: met = 7.0
        default:        met = 5.0
        }
        let weight = record.riderKg ?? 70
        return met * weight * hours
    }
}

enum HealthKitServiceError: LocalizedError {
    case notAvailable
    var errorDescription: String? {
        switch self {
        case .notAvailable: return "Apple Health n'est pas disponible sur cet appareil."
        }
    }
}

// ── READ side: ingest workouts from Apple Health (Strava-independent) ─────────
//
// This is what lets Little Explorer capture rides recorded on ANY device that
// writes to Apple Health (Apple Watch, Garmin Connect, Whoop, Wahoo…), with no
// Strava athlete cap. We read the finished workout + its GPS route + heart
// rate, build a payload, and the sync manager POSTs it to /api/activities/ingest.
extension HealthKitService {
    /// Types we need READ access to for ingestion.
    private var ingestReadTypes: Set<HKObjectType> {
        var t: Set<HKObjectType> = [HKObjectType.workoutType(), HKSeriesType.workoutRoute()]
        if let hr = HKObjectType.quantityType(forIdentifier: .heartRate) { t.insert(hr) }
        return t
    }

    /// Ask for READ permission on workouts / routes / heart rate. Separate from
    /// `requestAuthorization()` (which asks for WRITE) so each prompt is clear.
    func requestIngestAuthorization() async throws {
        guard Self.isAvailable else { throw HealthKitServiceError.notAvailable }
        try await store.requestAuthorization(toShare: [], read: ingestReadTypes)
    }

    /// Recent workouts, newest first.
    func fetchWorkouts(since: Date, limit: Int = 50) async throws -> [HKWorkout] {
        let predicate = HKQuery.predicateForSamples(withStart: since, end: nil, options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let samples: [HKSample] = try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: limit, sortDescriptors: [sort]) { _, s, e in
                if let e { cont.resume(throwing: e) } else { cont.resume(returning: s ?? []) }
            }
            store.execute(q)
        }
        return samples.compactMap { $0 as? HKWorkout }
    }

    /// The GPS route for a workout, as time-sorted CLLocations (empty for
    /// indoor workouts with no route).
    func routeLocations(for workout: HKWorkout) async throws -> [CLLocation] {
        let routePredicate = HKQuery.predicateForObjects(from: workout)
        let routeSamples: [HKSample] = try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: HKSeriesType.workoutRoute(), predicate: routePredicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, s, e in
                if let e { cont.resume(throwing: e) } else { cont.resume(returning: s ?? []) }
            }
            store.execute(q)
        }
        guard let route = routeSamples.first as? HKWorkoutRoute else { return [] }
        var locations: [CLLocation] = []
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let q = HKWorkoutRouteQuery(route: route) { _, batch, done, error in
                if let error { cont.resume(throwing: error); return }
                if let batch { locations.append(contentsOf: batch) }
                if done { cont.resume(returning: ()) }
            }
            store.execute(q)
        }
        return locations.sorted { $0.timestamp < $1.timestamp }
    }

    /// Heart-rate samples inside the workout window, time-sorted.
    func heartRateSamples(for workout: HKWorkout) async throws -> [(date: Date, bpm: Double)] {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return [] }
        let pred = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate, options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let samples: [HKSample] = try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: hrType, predicate: pred, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, s, e in
                if let e { cont.resume(throwing: e) } else { cont.resume(returning: s ?? []) }
            }
            store.execute(q)
        }
        let unit = HKUnit.count().unitDivided(by: .minute())
        return samples.compactMap { ($0 as? HKQuantitySample).map { ($0.startDate, $0.quantity.doubleValue(for: unit)) } }
    }

    /// Strava-style type string for the ingest payload (the back-end buckets it).
    func stravaType(for t: HKWorkoutActivityType) -> String {
        switch t {
        case .cycling:            return "Ride"
        case .running:            return "Run"
        case .hiking:             return "Hike"
        case .walking:            return "Walk"
        case .swimming:           return "Swim"
        case .downhillSkiing:     return "AlpineSki"
        case .crossCountrySkiing: return "NordicSki"
        case .snowboarding:       return "Snowboard"
        case .snowSports:         return "Snowshoe"
        case .rowing:             return "Rowing"
        case .yoga:               return "Yoga"
        case .traditionalStrengthTraining, .functionalStrengthTraining, .coreTraining, .crossTraining:
            return "WeightTraining"
        default:                  return "Workout"
        }
    }

    /// Assemble a full ingest payload for a workout (route + HR + summary).
    func buildIngestPayload(for workout: HKWorkout) async -> HealthIngestPayload? {
        let start = workout.startDate
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime]

        var locs = (try? await routeLocations(for: workout)) ?? []
        // Cap the payload: a long ride can be 10k+ points; ~4000 keeps the
        // charts smooth without bloating the request.
        if locs.count > 4000 {
            let step = Int(ceil(Double(locs.count) / 4000.0))
            locs = locs.enumerated().filter { $0.offset % step == 0 }.map(\.element)
        }

        var gps: [[Double]] = []; var altitude: [Double] = []; var timeS: [Double] = []
        var distStream: [Double] = []; var speedKmh: [Double] = []
        var cumDist = 0.0
        for (i, loc) in locs.enumerated() {
            gps.append([loc.coordinate.latitude, loc.coordinate.longitude])
            altitude.append(loc.altitude.isFinite ? loc.altitude : 0)
            timeS.append(loc.timestamp.timeIntervalSince(start))
            if i > 0 {
                let d  = loc.distance(from: locs[i - 1])
                let dt = loc.timestamp.timeIntervalSince(locs[i - 1].timestamp)
                cumDist += d
                let sp = loc.speed >= 0 ? loc.speed : (dt > 0 ? d / dt : 0)
                speedKmh.append(max(0, sp) * 3.6)
            } else {
                speedKmh.append(loc.speed >= 0 ? loc.speed * 3.6 : 0)
            }
            distStream.append(cumDist)
        }

        // Heart rate: align to the route timestamps (nearest prior sample).
        let hrSamples = (try? await heartRateSamples(for: workout)) ?? []
        var heartrate: [Double] = []
        if !locs.isEmpty, !hrSamples.isEmpty {
            var j = 0
            for loc in locs {
                while j + 1 < hrSamples.count, hrSamples[j + 1].date <= loc.timestamp { j += 1 }
                heartrate.append(hrSamples[j].bpm)
            }
        }
        let hrValues = hrSamples.map(\.bpm)
        let avgHr = hrValues.isEmpty ? nil : hrValues.reduce(0, +) / Double(hrValues.count)
        let maxHr = hrValues.max()

        let totalDist = workout.totalDistance?.doubleValue(for: .meter()) ?? cumDist
        var gain = 0.0
        if altitude.count > 1 {
            for i in 1..<altitude.count {
                let d = altitude[i] - altitude[i - 1]
                if d > 0 { gain += d }
            }
        }
        let calories = workout.totalEnergyBurned?.doubleValue(for: .kilocalorie())

        return HealthIngestPayload(
            uuid:             workout.uuid.uuidString,
            type:             stravaType(for: workout.workoutActivityType),
            name:             nil,
            start_date:       iso.string(from: start),
            duration_s:       workout.duration,
            distance_m:       totalDist,
            elevation_gain_m: gain,
            calories:         calories,
            avg_hr:           avgHr.map { $0.rounded() },
            max_hr:           maxHr.map { $0.rounded() },
            gps:              gps,
            altitude:         altitude,
            time_s:           timeS,
            distance_stream:  distStream,
            heartrate:        heartrate,
            speed_kmh:        speedKmh,
        )
    }

    /// Wake the app whenever a new workout lands in Apple Health, so we can
    /// ingest it even in the background. Call once, after read authorization.
    func startObservingWorkouts(_ onNew: @escaping @Sendable () -> Void) {
        guard Self.isAvailable else { return }
        let type = HKObjectType.workoutType()
        let observer = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, error in
            if error == nil { onNew() }
            completion()
        }
        store.execute(observer)
        store.enableBackgroundDelivery(for: type, frequency: .immediate) { success, err in
            if let err {
                Log.tracking.error("HK background delivery failed: \(err.localizedDescription, privacy: .public)")
            } else {
                Log.tracking.notice("HK background delivery enabled: \(success)")
            }
        }
    }
}
