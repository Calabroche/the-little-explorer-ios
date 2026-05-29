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
        VStack(spacing: 0) {
            // Grid sits at the top edge — values are now LARGER
            // (32pt → 34pt) so the rider reads them at arm's length
            // without squinting. Inter-row spacing kept tight (4pt)
            // to fit three rows + the HR bar inside one watch screen.
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
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
            .padding(.horizontal, 6)
            .padding(.top, 2)

            Spacer(minLength: 4)

            // HR zone strip pinned to the screen's bottom edge —
            // padding.bottom dropped to 2pt so there's no dead air
            // below the pill. Reserved 38pt for the pill (32pt) +
            // triangle (5pt) + 1pt breathing.
            if !isDimmed {
                HRZonesBar(bpm: workoutManager.heartRate)
                    .frame(minHeight: 38)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 2)
            }
        }
    }

    /// Single metric cell — label on top in tiny caps, value below in
    /// big monospaced digits. Tint color helps glance-parsing.
    /// Bumped to 34pt (dim 36) so TIME / AVG / SPEED read at arm's
    /// length while the rider's hands stay on the bars. The HR zone
    /// strip sits flush at the bottom, so the value font has room
    /// to grow without spilling off the watch screen.
    private func cell(_ label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(isDimmed ? .white.opacity(0.55) : .secondary)
            Text(value)
                .font(.system(size: isDimmed ? 36 : 34, weight: .bold))
                .monospacedDigit()
                .minimumScaleFactor(0.55)
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
