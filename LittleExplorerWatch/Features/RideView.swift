import SwiftUI

/// In-progress ride screen.
///
/// Two modes:
///   • Freeform ride (`activeItinerary == nil`): scrollable single page
///     with the four live metrics on top + Pause + End buttons always
///     visible at the bottom. Digital Crown native.
///   • Itinerary ride: vertical TabView with two pages — metrics page
///     on top, map view on bottom showing the planned route + current
///     location. Swipe down (or Crown) to flip between them.
///
/// Always-On Display: on Series 5+, the screen stays dimly lit when
/// the user lowers the wrist mid-workout. We detect this via
/// `@Environment(\.isLuminanceReduced)` and switch to a high-contrast
/// monochrome layout that's readable at a glance without burning
/// battery. WatchKit blanks SwiftUI animations automatically in this
/// mode — no extra work needed for that.
struct RideView: View {
    @Environment(WorkoutManager.self) private var workoutManager
    @Environment(WatchSessionManager.self) private var session

    var body: some View {
        if let itinerary = workoutManager.activeItinerary {
            // Two-page TabView — vertical page style maps to the
            // Digital Crown's natural up/down.
            TabView {
                MetricsPage()
                ItineraryMapView(
                    itinerary: itinerary,
                    currentCoordinate: workoutManager.latestCoordinate,
                )
                .tabItem { Label("Carte", systemImage: "map.fill") }
            }
            .tabViewStyle(.verticalPage)
        } else {
            MetricsPage()
        }
    }
}

/// Live metrics + Pause/End controls. Same layout in freeform and
/// itinerary rides; only the surrounding navigation differs.
private struct MetricsPage: View {
    @Environment(WorkoutManager.self) private var workoutManager
    @Environment(WatchSessionManager.self) private var session
    /// True when the Watch is in Always-On (dim) mode. Drives the
    /// monochrome / larger-font branch of the layout.
    @Environment(\.isLuminanceReduced) private var isDimmed

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: isDimmed ? 14 : 10) {
                row("Time",     value: formatDuration(workoutManager.elapsed))
                row("Distance", value: formatDistance(workoutManager.distanceMeters))
                row("Speed",    value: String(format: "%.1f km/h", workoutManager.speedKmh))
                row("HR",       value: workoutManager.heartRate.map { "\($0) bpm" } ?? "—")

                // Hide the control row when dimmed — taps are blocked
                // by Always-On anyway, so two big buttons just eat
                // pixels. They reappear instantly on wrist-raise.
                if !isDimmed {
                    Divider().padding(.vertical, 6)

                    Button {
                        workoutManager.togglePause()
                    } label: {
                        Label(
                            workoutManager.isPaused ? "Resume" : "Pause",
                            systemImage: workoutManager.isPaused ? "play.fill" : "pause.fill",
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive) {
                        Task {
                            await workoutManager.end()
                            session.send(["kind": "rideControl", "action": "stop"])
                        }
                    } label: {
                        Label("End ride", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
            .padding(.horizontal, isDimmed ? 6 : 4)
            .padding(.bottom, 8)
        }
    }

    /// Single metric row. In dim mode we go bigger (~25 % up) and
    /// strip the colour-coded tint to monochrome white-on-black, which
    /// is the highest-contrast / lowest-battery rendering on OLED.
    private func row(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.caption2)
                .foregroundStyle(isDimmed ? .white.opacity(0.6) : .secondary)
            Text(value)
                .font((isDimmed ? Font.title2 : Font.title3).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(isDimmed ? .white : .primary)
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let s = Int(seconds)
        return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    private func formatDistance(_ meters: Double) -> String {
        meters >= 1000 ? String(format: "%.2f km", meters / 1000) : "\(Int(meters)) m"
    }
}
