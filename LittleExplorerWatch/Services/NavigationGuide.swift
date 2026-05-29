import AVFoundation
import CoreLocation
import Foundation
import Observation
import os

/// Voice-driven turn-by-turn coach for itinerary rides.
///
/// Reads the rider's GPS fixes against the cached `NavStep` sequence
/// of the active itinerary and fires audio announcements at two
/// thresholds per step:
///   • Pre-warning at ~200 m: "Dans 200 mètres, tourne à gauche sur rue X"
///   • Immediate at ~30 m:    "Tourne à gauche maintenant"
///
/// Each maneuver gets exactly two announcements at most — no
/// re-announcing on GPS jitter that briefly pushes the rider back
/// into the window.
///
/// Audio session config: `.playback` category with `.duckOthers`
/// option so podcasts / music keep playing but quieten under the
/// voice cue. Same pattern as in-car navigation apps.
@Observable
@MainActor
final class NavigationGuide {
    /// True once the audio session is configured. Re-firing the same
    /// `prepare()` is a no-op so callers don't need to track it.
    private(set) var isReady = false

    /// Hands-off enable/disable. Wired to a settings toggle later;
    /// for now it's just a runtime guard.
    var enabled: Bool = true

    private let logger = Logger(subsystem: "com.calabrese.little-explorer-ios.watchkitapp", category: "NavigationGuide")
    private let synthesizer = AVSpeechSynthesizer()
    private let voice = AVSpeechSynthesisVoice(language: "fr-FR")

    /// Steps for the active itinerary. Set by `setItinerary(_:)`.
    private var steps: [NavStep] = []
    /// Index of the *next* step we expect to reach. Advances when the
    /// rider crosses that step's location.
    private var nextStepIndex = 0
    /// Per-step bookkeeping so we don't re-announce a step we already
    /// covered (or already pre-warned). Sized to steps.count.
    private var preWarned: [Bool] = []
    private var immediateFired: [Bool] = []

    init() {}

    /// Configure the system audio session. Called lazily on first
    /// announce — no need for the rider to opt-in beforehand.
    private func prepareIfNeeded() {
        guard !isReady else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playback,
                mode: .voicePrompt,
                options: [.duckOthers, .mixWithOthers],
            )
            try session.setActive(true, options: [])
            isReady = true
            logger.notice("Audio session ready (.playback / .duckOthers / .voicePrompt)")
        } catch {
            logger.error("AV session setup failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func setItinerary(_ itinerary: Itinerary?) {
        steps = itinerary?.steps ?? []
        nextStepIndex = 0
        preWarned = Array(repeating: false, count: steps.count)
        immediateFired = Array(repeating: false, count: steps.count)
        if !steps.isEmpty {
            logger.notice("Loaded \(self.steps.count, privacy: .public) nav steps")
        }
    }

    /// Drive the state machine off the latest GPS fix. Cheap (a few
    /// haversine computations per call) — safe to invoke on every
    /// CLLocationManager update.
    func ingest(fix: CLLocation) {
        guard enabled, !steps.isEmpty, nextStepIndex < steps.count else { return }

        let here = Coordinate(lat: fix.coordinate.latitude, lng: fix.coordinate.longitude)
        // NavStep.start is already a Coordinate (see Shared/Models/Route.swift).
        let metersToNext = haversine(here, steps[nextStepIndex].start)

        // Pre-warning at ~200 m.
        if !preWarned[nextStepIndex] && metersToNext <= 200 && metersToNext > 30 {
            preWarned[nextStepIndex] = true
            announce(phraseForStep(steps[nextStepIndex], distance: metersToNext, immediate: false))
        }
        // Immediate at ~30 m.
        if !immediateFired[nextStepIndex] && metersToNext <= 30 {
            immediateFired[nextStepIndex] = true
            announce(phraseForStep(steps[nextStepIndex], distance: 0, immediate: true))
            nextStepIndex += 1
        }
    }

    /// Speak a phrase via AVSpeechSynthesizer. Reuses the cached
    /// fr-FR voice when available. Prepares the audio session lazily.
    private func announce(_ phrase: String) {
        prepareIfNeeded()
        let utterance = AVSpeechUtterance(string: phrase)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.preUtteranceDelay = 0
        utterance.postUtteranceDelay = 0.15
        synthesizer.speak(utterance)
        logger.notice("Announced: \(phrase, privacy: .public)")
    }

    /// Map an OSRM step to a French phrase.
    private func phraseForStep(_ step: NavStep, distance: Double, immediate: Bool) -> String {
        let direction = directionPhrase(type: step.type, modifier: step.modifier, exit: step.exit)
        let onStreet = step.name.isEmpty ? "" : " sur \(step.name)"
        if immediate {
            return "\(direction)\(onStreet) maintenant"
        } else {
            let dist = Int(distance.rounded() / 10) * 10  // round to nearest 10 m
            return "Dans \(dist) mètres, \(direction.lowercasedFirst)\(onStreet)"
        }
    }

    private func directionPhrase(type: String, modifier: String, exit: Int?) -> String {
        // OSRM step "type" + "modifier" cover ~95 % of useful cases.
        // The full list is in https://docs.mapbox.com/api/navigation/directions/#step-maneuver-object
        switch type {
        case "depart":
            return "Démarre"
        case "arrive":
            return "Tu es arrivé"
        case "roundabout", "rotary":
            if let exit { return "Au rond-point, prends la \(exit)\(exit == 1 ? "re" : "e") sortie" }
            return "Engage-toi dans le rond-point"
        case "fork":
            return "Garde \(modifierPhrase(modifier))"
        case "merge":
            return "Insère-toi \(modifierPhrase(modifier))"
        case "turn", "end of road", "continue", "new name":
            switch modifier {
            case "left":         return "Tourne à gauche"
            case "right":        return "Tourne à droite"
            case "sharp left":   return "Tourne brusquement à gauche"
            case "sharp right":  return "Tourne brusquement à droite"
            case "slight left":  return "Va légèrement à gauche"
            case "slight right": return "Va légèrement à droite"
            case "straight":     return "Continue tout droit"
            case "uturn":        return "Fais demi-tour"
            default:             return "Continue tout droit"
            }
        default:
            return "Continue"
        }
    }

    private func modifierPhrase(_ modifier: String) -> String {
        switch modifier {
        case "left":         return "à gauche"
        case "right":        return "à droite"
        case "slight left":  return "à gauche"
        case "slight right": return "à droite"
        default:             return "tout droit"
        }
    }
}

// ── Helpers ────────────────────────────────────────────────────────

private func haversine(_ a: Coordinate, _ b: Coordinate) -> Double {
    let R = 6_371_000.0
    let lat1 = a.lat * .pi / 180
    let lat2 = b.lat * .pi / 180
    let dLat = (b.lat - a.lat) * .pi / 180
    let dLng = (b.lng - a.lng) * .pi / 180
    let h = sin(dLat / 2) * sin(dLat / 2)
          + cos(lat1) * cos(lat2) * sin(dLng / 2) * sin(dLng / 2)
    return 2 * R * atan2(sqrt(h), sqrt(1 - h))
}

private extension String {
    /// Lowercase only the first character — used so "Tourne à gauche"
    /// becomes "tourne à gauche" when embedded mid-sentence.
    var lowercasedFirst: String {
        guard let first = first else { return self }
        return first.lowercased() + dropFirst()
    }
}
