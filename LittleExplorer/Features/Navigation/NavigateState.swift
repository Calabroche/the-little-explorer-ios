import AVFoundation
import CoreLocation
import Foundation
import Observation
import UIKit

/// Drives turn-by-turn navigation against a fixed BikeRoute. Subscribes
/// to GPS updates, projects the user onto the polyline, picks the next
/// upcoming step, and fires voice prompts at planned distance levels.
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

    private let api: APIClient
    private let location: LocationManager
    private let synthesizer = AVSpeechSynthesizer()
    private var trackingTask: Task<Void, Never>?
    private var announced: [Int: Set<ManeuverFormatter.AnnounceLevel>] = [:]
    private var lastPromptedStep: Int?
    private let lang: ManeuverFormatter.Lang = .fr

    init(api: APIClient = .shared, location: LocationManager) {
        self.api = api
        self.location = location
    }

    func start(itinerary: Itinerary) async {
        phase = .loading
        do {
            // Need turn-by-turn steps — re-route the saved waypoints with
            // steps:true (the cached geometry was steps:false to keep
            // the planning response small).
            var coords = itinerary.waypoints.map(\.coordinate)
            if itinerary.loop, let first = coords.first { coords.append(first) }
            let fresh = try await api.bikeRoute(waypoints: coords, steps: true)
            self.route = fresh
            phase = .ready
        } catch {
            phase = .failed(error.localizedDescription)
            return
        }
        location.requestAuthorization()
        UIApplication.shared.isIdleTimerDisabled = true
        trackingTask = Task { [stream = location.startTracking()] in
            for await loc in stream {
                await self.ingest(loc)
            }
        }
    }

    func stop() {
        trackingTask?.cancel()
        location.stopTracking()
        synthesizer.stopSpeaking(at: .immediate)
        UIApplication.shared.isIdleTimerDisabled = false
    }

    @MainActor
    private func ingest(_ loc: CLLocation) {
        userLocation = loc
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
}
