import Foundation

/// Pulls finished workouts out of Apple Health and pushes them to the back-end
/// (POST /api/activities/ingest), so Little Explorer captures rides from ANY
/// device that writes to Health (Apple Watch, Garmin, Whoop, Wahoo…) with no
/// Strava athlete cap.
///
/// On `start` it does an initial sweep, then background delivery keeps it live:
/// whenever a new workout lands in Health the observer wakes us and we upload
/// it. Dedup is by workout UUID so nothing is sent twice.
final class HealthKitSyncManager {
    private let health: HealthKitService
    private let api: APIClient

    private var isEnabled: () -> Bool = { false }
    private var isSyncing = false
    private var observing = false

    /// Fired after at least one new workout was ingested (e.g. refresh feed).
    var onIngested: (() -> Void)?

    private let uploadedKey = "tle.healthkit.uploadedUUIDs"

    init(health: HealthKitService, api: APIClient) {
        self.health = health
        self.api = api
    }

    /// Kick things off. `isEnabled` gates on the user's HealthKit toggle AND a
    /// valid session (the APIClient must have its bearer token set), so call
    /// this once the user is signed in.
    func start(isEnabled: @escaping () -> Bool) {
        self.isEnabled = isEnabled
        guard HealthKitService.isAvailable else { return }
        Task { await self.bootstrap() }
    }

    private func bootstrap() async {
        guard isEnabled() else { return }
        do {
            try await health.requestIngestAuthorization()
        } catch {
            Log.tracking.error("HK read auth failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        await syncNew()

        if !observing {
            observing = true
            health.startObservingWorkouts { [weak self] in
                Task { await self?.syncNew() }
            }
        }
    }

    /// Fetch recent workouts and upload any we haven't sent yet.
    func syncNew() async {
        guard isEnabled(), !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        // Look back 45 days so a back-dated import (a ride Garmin syncs a day
        // late) is still caught; the UUID dedup keeps it idempotent.
        let since = Calendar.current.date(byAdding: .day, value: -45, to: Date()) ?? Date(timeIntervalSince1970: 0)
        guard let workouts = try? await health.fetchWorkouts(since: since, limit: 50) else { return }

        let defaults = UserDefaults.standard
        var uploaded = Set(defaults.stringArray(forKey: uploadedKey) ?? [])
        var didIngest = false

        for workout in workouts.sorted(by: { $0.endDate < $1.endDate }) {
            let uid = workout.uuid.uuidString
            if uploaded.contains(uid) { continue }
            guard let payload = await health.buildIngestPayload(for: workout) else { continue }
            do {
                try await api.ingestHealthWorkout(payload)
                uploaded.insert(uid)
                didIngest = true
                Log.api.notice("HK ingest OK: \(uid, privacy: .public) · \(payload.type, privacy: .public) · \(Int(payload.distance_m / 1000)) km")
            } catch {
                Log.api.error("HK ingest failed for \(uid, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        // Persist the dedup set, capped so it can't grow unbounded.
        let capped = Array(Array(uploaded).suffix(2000))
        defaults.set(capped, forKey: uploadedKey)

        if didIngest { onIngested?() }
    }
}
