import SwiftUI

/// In-progress ride screen — Phase E.3 layout.
///
/// Pages (swipe down with finger or scroll with Digital Crown):
///   1. **Metrics** — landing page, fully dedicated to data. Pause /
///      End buttons no longer live here, so every pixel goes to the
///      3×2 metric grid: Time / Distance / Speed / Avg / HR / Climb.
///   2. **Map** (itinerary mode only) — planned route + position.
///   3. **Controls** — Pause / Resume + End ride. Surface the actions
///      that change ride state behind a deliberate swipe so a wrist
///      bump in a pocket can't kill a ride.
///
/// Always-On Display: when `isLuminanceReduced`, the metrics page
/// keeps its grid in high-contrast white. The controls page is hidden
/// (taps blocked in dim mode anyway).
struct RideView: View {
    @Environment(WorkoutManager.self) private var workoutManager
    @Environment(WatchSessionManager.self) private var session

    var body: some View {
        TabView {
            MetricsPage()
            if let itinerary = workoutManager.activeItinerary {
                ItineraryMapView(
                    itinerary: itinerary,
                    currentCoordinate: workoutManager.latestCoordinate,
                )
            }
            ControlsPage()
        }
        .tabViewStyle(.verticalPage)
    }
}

/// Full-screen dense metric grid. No buttons share this view, no
/// scroll — everything the rider needs fits on one screen. Layout:
/// 3 rows × 2 cols of metrics + a thin 5-zone HR bar pinned at the
/// bottom (Apple Workout-style).
private struct MetricsPage: View {
    @Environment(WorkoutManager.self) private var workoutManager
    @Environment(\.isLuminanceReduced) private var isDimmed

    var body: some View {
        // Force full screen width on the root container so the
        // Grid's column geometry stays anchored regardless of
        // what's happening below. Without this, when the HR pill
        // toggles between inactive (narrow chip row) and active
        // (wide pill ⇒ HStack expands to .infinity), the VStack
        // re-derives its intrinsic width from its children and
        // the Grid columns shift left. Pinning the VStack to the
        // screen width breaks that coupling — the metrics row
        // doesn't budge when the HR zone updates.
        VStack(spacing: 0) {
            // Grid takes its intrinsic height. Value font 38pt —
            // smaller than 42 so the top row clears the Ultra's
            // rounded corner curve AND leaves slack for the HR
            // pill below. The corner clipped "TIME" → "IME" at
            // 42pt even with 10pt side padding because the corner
            // radius eats into the first ~14pt of the top-left.
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    cell("TIME",  value: formatDuration(workoutManager.elapsed),     tint: .white)
                    cell("DIST",  value: formatDistance(workoutManager.distanceMeters), tint: .white)
                }
                GridRow {
                    cell("SPEED", value: String(format: "%.0f km/h", workoutManager.speedKmh),    tint: .green)
                    cell("AVG",   value: String(format: "%.0f km/h", workoutManager.avgSpeedKmh), tint: .secondary)
                }
                GridRow {
                    cell("HR",    value: workoutManager.heartRate.map { "\($0)" } ?? "—", tint: .red)
                    cell("CLIMB", value: "+\(Int(workoutManager.elevationGain)) m",        tint: .orange)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)

            Spacer(minLength: 2)

            // HR zone strip — slimmed to match the smaller
            // metric digits. Reserved 48pt: 40pt pill + 2pt
            // VStack gap + 6pt triangle. Side padding 14pt
            // mirrors the grid above so columns align.
            if !isDimmed {
                HRZonesBar(bpm: workoutManager.heartRate)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Single metric cell — label on top in tiny caps, value
    /// below in big monospaced digits. Value at 40pt (dim 42),
    /// label at 13pt — the size the rider asked for after the
    /// 38pt / 11pt baseline felt too modest. minimumScaleFactor
    /// 0.5 absorbs rare wide values like "1:23:45" without
    /// breaking the grid.
    private func cell(_ label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(isDimmed ? .white.opacity(0.55) : .secondary)
            Text(value)
                .font(.system(size: isDimmed ? 42 : 40, weight: .bold))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(isDimmed ? .white : tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let s = Int(seconds)
        if s >= 3600 {
            return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
        } else {
            return String(format: "%d:%02d", s / 60, s % 60)
        }
    }

    private func formatDistance(_ meters: Double) -> String {
        meters >= 1000 ? String(format: "%.2f km", meters / 1000) : "\(Int(meters)) m"
    }
}

/// Pause / Resume + End ride. Lives on its own page so the rider
/// has to *deliberately* navigate here before they can stop a
/// workout — protects against accidental swipe-ends from a wrist
/// brush against a sleeve / handlebar.
private struct ControlsPage: View {
    @Environment(WorkoutManager.self) private var workoutManager
    @Environment(WatchSessionManager.self) private var session
    @Environment(\.isLuminanceReduced) private var isDimmed

    var body: some View {
        VStack(spacing: 14) {
            // Header so the rider knows what page they're on after
            // swiping down — without it the buttons feel orphaned.
            Text("Contrôles")
                .font(.caption.weight(.semibold))
                .tracking(0.4)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                workoutManager.togglePause()
            } label: {
                Label(
                    workoutManager.isPaused ? "Resume" : "Pause",
                    systemImage: workoutManager.isPaused ? "play.fill" : "pause.fill",
                )
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .tint(workoutManager.isPaused ? .green : .yellow)

            Button(role: .destructive) {
                Task {
                    await workoutManager.end()
                    session.send(["kind": "rideControl", "action": "stop"])
                }
            } label: {
                Label("End ride", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        // Dim mode hides controls — taps are blocked by Always-On and
        // two empty buttons just eat pixels. View reappears instantly
        // on wrist-raise.
        .opacity(isDimmed ? 0 : 1)
    }
}
