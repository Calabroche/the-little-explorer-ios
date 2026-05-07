import CoreLocation
import Foundation
import HealthKit
import Observation

/// HKWorkoutSession wrapper for the watch. Pulls heart rate from the
/// watch's sensors and exposes a simple Observable surface.
@Observable
@MainActor
final class WorkoutManager: NSObject {
    private(set) var isActive = false
    private(set) var isPaused = false
    private(set) var elapsed: TimeInterval = 0
    private(set) var distanceMeters: Double = 0
    private(set) var speedKmh: Double = 0
    private(set) var heartRate: Int?

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var startedAt: Date?
    private var clockTask: Task<Void, Never>?

    func start() async {
        guard !isActive else { return }
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
            print("HealthKit authorization failed: \(error)")
            return
        }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .cycling
        configuration.locationType = .outdoor

        do {
            session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            builder = session?.associatedWorkoutBuilder()
        } catch {
            print("Couldn't create workout session: \(error)")
            return
        }
        builder?.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
        session?.delegate = self
        builder?.delegate = self

        let now = Date()
        startedAt = now
        session?.startActivity(with: now)
        try? await builder?.beginCollection(at: now)
        isActive = true
        startClock()
    }

    func togglePause() {
        guard let session else { return }
        if isPaused {
            session.resume()
            isPaused = false
        } else {
            session.pause()
            isPaused = true
        }
    }

    func end() async {
        guard let session else { return }
        session.end()
        try? await builder?.endCollection(at: .now)
        try? await builder?.finishWorkout()
        clockTask?.cancel()
        isActive = false
        isPaused = false
    }

    private func startClock() {
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.isActive, !self.isPaused, let start = self.startedAt else { continue }
                self.elapsed = Date.now.timeIntervalSince(start)
            }
        }
    }
}

extension WorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date,
    ) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        print("Workout session failed: \(error)")
    }
}

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
            }
        case HKQuantityType(.distanceCycling):
            let unit = HKUnit.meter()
            if let value = stats.sumQuantity()?.doubleValue(for: unit) {
                distanceMeters = value
            }
        default:
            break
        }
    }
}
