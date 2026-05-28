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
///
/// @MainActor: every method touches UIKit (UIApplication.shared),
/// ActivityKit (Activity.request), or CLLocationManager — all main-
/// thread-only. Without explicit isolation the methods would resume on
/// the cooperative thread pool after an `await`, then crash the first
/// time they touched UIApplication. On Debug-simulator builds Apple's
/// executor tends to keep us on main most of the time so the bug hides;
/// on device builds it fires reliably.
@Observable
@MainActor
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
    private(set) var elevationDescentM: Double = 0
    private(set) var maxSpeedKmh: Double = 0
    private(set) var elapsedSec: Double = 0
    private(set) var startedAt: Date?
    private var lastLocationForTracking: CLLocation?
    private var clockTask: Task<Void, Never>?

    // Sampled streams — captured so we can build a real RideRecord at
    // the end of the navigation (same shape RideTracker produces).
    private(set) var sampledGps: [Coordinate] = []
    private(set) var sampledAltitude: [Double] = []
    private(set) var sampledSpeedKmh: [Double] = []
    private(set) var sampledDistanceM: [Double] = []
    private(set) var sampledTimeS: [Double] = []

    private let api: APIClient
    private let location: LocationManager
    private let activityManager: RideActivityManager?
    private let synthesizer = AVSpeechSynthesizer()
    /// Holds onto the speech delegate so AVSpeechSynthesizer doesn't
    /// drop the reference (it's a `weak` property on the synthesizer).
    private let speechDelegate = SpeechAudioSessionManager()
    private var trackingTask: Task<Void, Never>?
    private var announced: [Int: Set<ManeuverFormatter.AnnounceLevel>] = [:]
    private var lastPromptedStep: Int?
    private let lang: ManeuverFormatter.Lang = .fr

    init(api: APIClient = .shared, location: LocationManager, activityManager: RideActivityManager? = nil) {
        self.api = api
        self.location = location
        self.activityManager = activityManager
        self.synthesizer.delegate = speechDelegate
    }

    func start(itinerary: Itinerary) async {
        Log.nav.notice("start: \(itinerary.waypoints.count) waypoints, loop=\(itinerary.loop)")
        phase = .loading
        location.requestAuthorization()

        // If we already have a recent cached location, prepend it so
        // the route starts from where the user IS, not from the saved
        // first waypoint. Don't spin up a second tracking stream to
        // wait for one — that races with the main tracking stream we
        // start below and was crashing the app. A few minutes of
        // tolerance on the cache is plenty: if there's no recent fix
        // we just route from the saved waypoints and the GPS will
        // catch up once tracking starts.
        let here = currentLocationIfFresh()

        do {
            var coords = itinerary.waypoints.map(\.coordinate)
            if let here {
                coords.insert(Coordinate(lat: here.coordinate.latitude, lng: here.coordinate.longitude), at: 0)
                Log.nav.notice("prepended current location to route")
            }
            if itinerary.loop, let first = coords.first { coords.append(first) }
            Log.nav.notice("requesting bike route, \(coords.count) coords")
            let fresh = try await api.bikeRoute(waypoints: coords, steps: true)
            Log.nav.notice("route ready: \(Int(fresh.distance)) m, \(fresh.steps?.count ?? 0) steps")
            self.route = fresh
            phase = .ready
        } catch {
            Log.nav.error("route failed: \(error.localizedDescription, privacy: .public)")
            phase = .failed(error.localizedDescription)
            return
        }
        UIApplication.shared.isIdleTimerDisabled = true
        startedAt = .now
        let polyline = downsampledPolyline(self.route?.geometry ?? [], maxPoints: 100)
        await activityManager?.start(sportLabel: "Navigation", routePolyline: polyline)
        startClock()
        trackingTask = Task { [stream = location.startTracking()] in
            for await loc in stream {
                await self.ingest(loc)
            }
        }
    }

    /// Returns the most recently cached CLLocation if it's recent
    /// enough to be useful as a starting point. Doesn't trigger any
    /// CoreLocation activity — purely a read of `LocationManager.lastLocation`.
    private func currentLocationIfFresh() -> CLLocation? {
        guard let cached = location.lastLocation else { return nil }
        // 5 minutes is generous but safe — at this resolution the
        // "where am I now" question is answered well enough for the
        // first leg, and the user's real GPS will refine it within
        // a few seconds of tracking.
        if abs(cached.timestamp.timeIntervalSinceNow) > 300 { return nil }
        return cached
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
                else if altDelta < 0 { elevationDescentM += -altDelta }
            }
        }
        lastLocationForTracking = loc
        currentSpeedKmh = max(0, loc.speed) * 3.6  // CLLocation.speed is in m/s, < 0 when invalid
        if currentSpeedKmh > maxSpeedKmh { maxSpeedKmh = currentSpeedKmh }

        // Capture per-sample streams so we can build a full RideRecord
        // at the end of the navigation (same fields a tracked ride
        // would carry — gps, altitude, speed, distance, time arrays).
        sampledGps.append(Coordinate(lat: loc.coordinate.latitude, lng: loc.coordinate.longitude))
        sampledAltitude.append(loc.altitude)
        sampledSpeedKmh.append(currentSpeedKmh)
        sampledDistanceM.append(distanceTraveledM)
        if let startedAt {
            sampledTimeS.append(loc.timestamp.timeIntervalSince(startedAt))
        }

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
        // Honor the user's toggle. Saved per-device under
        // tle_voice_prompts_enabled — see SettingsView for the UI.
        // Defaults to true so the feature is discoverable on first
        // navigation.
        let enabled = UserDefaults.standard.object(forKey: "tle_voice_prompts_enabled") as? Bool ?? true
        guard enabled else { return }

        // Activate the audio session BEFORE queuing the utterance.
        // Without this:
        //   * Phone on silent mode → no sound (mute switch overrides
        //     speech). The .playback category bypasses the mute switch
        //     (same as Apple Maps).
        //   * Screen locked → speech is suppressed. .playback also
        //     keeps audio flowing under lock screen (we already have
        //     UIBackgroundModes: audio in project.yml).
        //   * Background music (Spotify, Apple Music, podcast) → our
        //     speech wouldn't be heard. .duckOthers temporarily lowers
        //     the other app's volume during our utterance.
        // The SpeechAudioSessionManager delegate restores normal volume
        // when the utterance ends.
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .voicePrompt,
                options: [.duckOthers, .mixWithOthers],
            )
            try AVAudioSession.sharedInstance().setActive(true, options: [])
        } catch {
            Log.tracking.error("voice: audio session activate failed: \(error.localizedDescription, privacy: .public)")
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: lang == .fr ? "fr-FR" : "en-US")
        utterance.rate = 0.5
        // Slight pre-utterance silence so a duck transition from
        // background music feels less abrupt.
        utterance.preUtteranceDelay = 0.15
        utterance.postUtteranceDelay = 0.1
        synthesizer.speak(utterance)
    }

    /// Speak an arbitrary sentence on demand. Used by the "Test voice"
    /// button in Settings so the user can verify the toggle / volume /
    /// duck-others behaviour without starting a real navigation.
    func speakTestPhrase() {
        speak(text: lang == .fr
            ? "Dans 300 mètres, tournez à droite sur Rue de la République."
            : "In 300 meters, turn right onto Republic Street.")
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
            userLat: userLocation?.coordinate.latitude,
            userLng: userLocation?.coordinate.longitude,
        )
        await activityManager.update(stateUpdate)
    }

    /// Uniform downsample of a polyline to at most `maxPoints` points
    /// (always keeping the first and last). Used to keep the Live
    /// Activity payload under the ContentState 4KB budget — at 100
    /// points × 16 bytes/coord that's ~1.6KB which leaves room for
    /// the rest of the state.
    private func downsampledPolyline(_ coords: [Coordinate], maxPoints: Int) -> [[Double]]? {
        guard !coords.isEmpty else { return nil }
        if coords.count <= maxPoints {
            return coords.map { [$0.lat, $0.lng] }
        }
        let step = Double(coords.count - 1) / Double(maxPoints - 1)
        var out: [[Double]] = []
        out.reserveCapacity(maxPoints)
        for i in 0..<maxPoints {
            let idx = min(Int(Double(i) * step), coords.count - 1)
            out.append([coords[idx].lat, coords[idx].lng])
        }
        return out
    }

    /// Build a RideRecord from the captured streams — same shape as
    /// RideTracker.commitRecord(title:) so the activity slots
    /// straight into LocalRideStore + the feed alongside ridden
    /// activities. Returns nil if nothing meaningful was recorded
    /// (no distance, no start time).
    func commitRecord(sport: Sport, title customTitle: String?) -> RideRecord? {
        // Accept anything > 5 m so the user can save very short
        // shakedown rides too. The save dialog itself decides whether
        // to call us — empty rides get the "Ignorer" path.
        guard let startedAt, distanceTraveledM > 5 else { return nil }
        let endDate = Date()
        let durationSeconds = elapsedSec > 0 ? elapsedSec : endDate.timeIntervalSince(startedAt)
        let durationMin = max(0, Int((durationSeconds / 60).rounded()))
        let distanceKm = distanceTraveledM / 1000
        let avgSpeed = durationSeconds > 0 ? distanceTraveledM / durationSeconds * 3.6 : 0

        let dateFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "dd MMM yyyy"
            f.locale = Locale(identifier: "fr_FR")
            return f
        }()
        let title: String = {
            let trimmed = (customTitle ?? "").trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return trimmed }
            return "Navigation · \(dateFormatter.string(from: startedAt))"
        }()
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        return RideRecord(
            id: -Int(startedAt.timeIntervalSince1970),
            type: sport.rawValue,
            originalType: nil,
            title: title,
            date: dateFormatter.string(from: startedAt).uppercased(),
            rawDate: isoFormatter.string(from: startedAt),
            location: nil,
            duration: formatDurationLabel(seconds: durationSeconds),
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
            maxIncline: nil,
            minIncline: nil,
            avgHr: nil, maxHr: nil, calories: nil,
            np: nil, avgPower: nil, tss: nil, ifFactor: nil, vi: nil,
            wkg: nil, ef: nil, trimp: nil, vam: nil, ftp: nil,
            weather: nil, bestEfforts: nil, photos: nil, hrZones: nil,
            aed: nil, riderKg: nil, totalMass: nil, paceSPerKm: nil,
        )
    }

    private func formatDurationLabel(seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        let h = s / 3600
        let m = (s % 3600) / 60
        return h > 0 ? "\(h)h \(String(format: "%02d", m))m" : "\(m) min"
    }
}

/// AVSpeechSynthesizer delegate that pairs each utterance with an
/// audio-session deactivation so background music (Spotify, Apple
/// Music…) returns to full volume after our turn-by-turn prompt.
///
/// We keep this in a separate type because the synthesizer's delegate
/// property is `weak` — if it pointed at NavigateState directly we'd
/// either have to hold a strong reference somewhere (the wrapper
/// pattern is cleaner), or risk the delegate being deallocated
/// mid-flight.
final class SpeechAudioSessionManager: NSObject, AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        deactivate()
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        deactivate()
    }

    private func deactivate() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            // Best-effort. If it fails the audio session stays
            // activated which means background music keeps ducking
            // until the OS resets it on app background. Not great
            // but not breaking.
        }
    }
}
