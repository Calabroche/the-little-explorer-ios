import AVFoundation
import CoreLocation
import Foundation
import Observation
import UIKit

/// Drives turn-by-turn navigation against a fixed BikeRoute. Subscribes
/// to GPS updates, projects the user onto the polyline, picks the next
/// upcoming step, fires voice prompts at planned distance levels, AND
/// pushes a Live Activity so the navigation keeps running with the
/// screen locked — the next maneuver + distance + km + speed + elevation
/// stay visible on the lock screen and Dynamic Island.
@Observable
final class NavigateState {
    enum Phase: Equatable { case loading, ready, finished, failed(String) }

    private(set) var phase: Phase = .loading
    private(set) var route: BikeRoute?
    private(set) var currentStepIndex: Int = 0
    private(set) var distanceToNextStep: Double = 0
    private(set) var distanceRemaining: Double = 0
    private(set) var userLocation: CLLocation?
    private(set) var lastSegmentIndex: Int = 0
    private(set) var offRoute: Bool = false

    // Live ride metrics shown on the bottom bar + Live Activity.
    private(set) var distanceTraveledM: Double = 0
    private(set) var currentSpeedKmh: Double = 0
    private(set) var avgSpeedKmh: Double = 0
    private(set) var elevationGainM: Double = 0
    private(set) var elapsedSec: Double = 0
    private var startedAt: Date?
    private var lastLocationForTracking: CLLocation?
    private var clockTask: Task<Void, Never>?

    private let api: APIClient
    private let location: LocationManager
    private let activityManager: RideActivityManager?
    private let synthesizer = AVSpeechSynthesizer()
    private var trackingTask: Task<Void, Never>?
    private var announced: [Int: Set<ManeuverFormatter.AnnounceLevel>] = [:]
    private var lastPromptedStep: Int?
    private let lang: ManeuverFormatter.Lang = .fr

    init(api: APIClient = .shared, location: LocationManager, activityManager: RideActivityManager? = nil) {
        self.api = api
        self.location = location
        self.activityManager = activityManager
    }

    func start(itinerary: Itinerary) async {
        phase = .loading
        location.requestAuthorization()

        // Grab the user's current location BEFORE asking the routing
        // service. If we have a fix that's recent enough we prepend it
        // as the first waypoint — that way "Naviguer" always plots a
        // route from where you actually are rather than from the saved
        // start point of the itinerary. If we don't have a fix yet (the
        // permission dialog just appeared, for example) we fall back to
        // the saved waypoints.
        let here = await waitForFreshLocation(maxWait: 4)

        do {
            var coords = itinerary.waypoints.map(\.coordinate)
            if let here {
                coords.insert(Coordinate(lat: here.coordinate.latitude, lng: here.coordinate.longitude), at: 0)
            }
            if itinerary.loop, let first = coords.first { coords.append(first) }
            let fresh = try await api.bikeRoute(waypoints: coords, steps: true)
            self.route = fresh
            phase = .ready
        } catch {
            phase = .failed(error.localizedDescription)
            return
        }
        UIApplication.shared.isIdleTimerDisabled = true
        startedAt = .now
        await activityManager?.start(sportLabel: "Navigation")
        startClock()
        trackingTask = Task { [stream = location.startTracking()] in
            for await loc in stream {
                await self.ingest(loc)
            }
        }
    }

    /// Returns a CLLocation that's either already cached (when fresh
    /// enough) or one captured within `maxWait` seconds via a transient
    /// listener. Nil if no fix arrives in time — caller falls back to
    /// the saved itinerary start point.
    private func waitForFreshLocation(maxWait: Double) async -> CLLocation? {
        if let cached = location.lastLocation, abs(cached.timestamp.timeIntervalSinceNow) < 30 {
            return cached
        }
        // Single-shot wait: subscribe to the next emission, but cap the
        // wait so a missing fix doesn't block the whole nav start.
        return await withTaskGroup(of: CLLocation?.self) { group in
            group.addTask {
                for await loc in self.location.startTracking() {
                    self.location.stopTracking()
                    return loc
                }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(maxWait))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    func stop() {
        trackingTask?.cancel()
        clockTask?.cancel()
        location.stopTracking()
        synthesizer.stopSpeaking(at: .immediate)
        UIApplication.shared.isIdleTimerDisabled = false
        Task { await activityManager?.end() }
    }

    /// Tick once per second so duration / avg-speed stay live even
    /// while waiting for the next GPS fix. Also pushes a Live Activity
    /// refresh so the lock-screen banner doesn't go stale.
    private func startClock() {
        clockTask?.cancel()
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                await self.tick()
            }
        }
    }

    @MainActor
    private func tick() async {
        guard let startedAt else { return }
        elapsedSec = Date().timeIntervalSince(startedAt)
        if distanceTraveledM > 0, elapsedSec > 0 {
            avgSpeedKmh = (distanceTraveledM / elapsedSec) * 3.6
        }
        await pushLiveActivity()
    }

    @MainActor
    private func ingest(_ loc: CLLocation) {
        userLocation = loc

        // Accumulate traveled distance + elevation gain, mirror RideTracker.
        // Drop the very first sample (just sets baseline) and ignore the
        // delta when accuracy is too poor or the jump is implausible (>200m
        // in one tick = a GPS spike).
        if let last = lastLocationForTracking {
            let delta = loc.distance(from: last)
            if delta < 200, loc.horizontalAccuracy < 50 {
                distanceTraveledM += delta
                let altDelta = loc.altitude - last.altitude
                if altDelta > 0 { elevationGainM += altDelta }
            }
        }
        lastLocationForTracking = loc
        currentSpeedKmh = max(0, loc.speed) * 3.6  // CLLocation.speed is in m/s, < 0 when invalid

        guard let route else { return }
        let user = Coordinate(lat: loc.coordinate.latitude, lng: loc.coordinate.longitude)
        let projection = GeoMath.closestPoint(on: route.geometry, to: user, searchFrom: lastSegmentIndex)
        lastSegmentIndex = projection.segmentIndex
        offRoute = projection.distance > 60 // > 60 m off the line

        distanceRemaining = GeoMath.distanceRemaining(
            polyline: route.geometry,
            from: projection.segmentIndex,
            t: projection.t,
        )

        guard let steps = route.steps, !steps.isEmpty else { return }

        // Pick the first step whose start lies AHEAD of the user.
        var nextIndex = currentStepIndex
        while nextIndex < steps.count - 1 {
            let dist = GeoMath.distanceAlong(
                polyline: route.geometry,
                from: projection.segmentIndex,
                t: projection.t,
                to: steps[nextIndex].start,
            )
            if dist > 5 { break }
            nextIndex += 1
        }
        currentStepIndex = nextIndex

        if currentStepIndex >= steps.count - 1, distanceRemaining < 30 {
            phase = .finished
            speak(text: ManeuverFormatter.core(steps.last!, lang: lang))
            return
        }

        let step = steps[nextIndex]
        let dist = GeoMath.distanceAlong(
            polyline: route.geometry,
            from: projection.segmentIndex,
            t: projection.t,
            to: step.start,
        )
        distanceToNextStep = dist
        maybeAnnounce(stepIndex: nextIndex, step: step, distance: dist)
    }

    private func maybeAnnounce(stepIndex: Int, step: NavStep, distance: Double) {
        let already = announced[stepIndex] ?? Set<ManeuverFormatter.AnnounceLevel>()
        guard let level = ManeuverFormatter.pickAnnouncement(distance: distance, already: already) else { return }
        announced[stepIndex, default: []].insert(level)
        let text = ManeuverFormatter.sentence(step, distance: distance, lang: lang)
        speak(text: text)
    }

    private func speak(text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: lang == .fr ? "fr-FR" : "en-US")
        utterance.rate = 0.5
        synthesizer.speak(utterance)
    }

    /// Mirror the current navigation state into the Live Activity so
    /// the lock-screen banner + Dynamic Island stay in sync. Called on
    /// every clock tick (1Hz). Cheap if there's no active activity.
    @MainActor
    private func pushLiveActivity() async {
        guard let activityManager else { return }
        var step: NavStep?
        if let route, let steps = route.steps, steps.indices.contains(currentStepIndex) {
            step = steps[currentStepIndex]
        }
        let stateUpdate = RideActivityAttributes.RideState(
            distanceKm: distanceTraveledM / 1000,
            durationSec: elapsedSec,
            speedKmh: currentSpeedKmh,
            elevationGainM: elevationGainM,
            heartRate: nil,
            nextManeuver: step.map { ManeuverFormatter.core($0, lang: lang) },
            nextManeuverDistanceM: step != nil ? distanceToNextStep : nil,
            nextManeuverSymbol: step?.maneuverSymbol,
        )
        await activityManager.update(stateUpdate)
    }
}
