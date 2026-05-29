import SwiftUI

/// In-progress ride screen — Phase E.1 redesign.
///
/// Goal: no scrolling, no swiping for the primary data. Everything
/// the rider needs at a glance fits on one screen via a dense grid.
/// The previous layout buried half the metrics + the End button below
/// the fold; the new one fits Time / Distance / Speed / HR + Avg /
/// Climb / Pause / End on the same view.
///
/// Two flavours:
///   • Freeform ride: 3-row metric grid (Time-Distance / Speed-Avg /
///     HR-Climb) + compact Pause / End row at the bottom.
///   • Itinerary ride: 2-page TabView — page 1 dense metric grid
///     identical to freeform, page 2 map view. The map is on its own
///     page so the grid stays uncompromised; swipe-to-map is intentional
///     (touch-only, no Crown collision with the system page switcher).
///
/// Always-On Display: when `isLuminanceReduced`, the grid switches to
/// a high-contrast layout (white-on-black, tight letter spacing,
/// monospaced digits) and the action row is hidden — taps are blocked
/// in dim mode anyway and two buttons just eat pixels.
struct RideView: View {
    @Environment(WorkoutManager.self) private var workoutManager
    @Environment(WatchSessionManager.self) private var session

    var body: some View {
        if let itinerary = workoutManager.activeItinerary {
            TabView {
                MetricsPage().tabItem { Label("Métriques", systemImage: "gauge.with.dots.needle.bottom.50percent") }
                ItineraryMapView(
                    itinerary: itinerary,
                    currentCoordinate: workoutManager.latestCoordinate,
                ).tabItem { Label("Carte", systemImage: "map.fill") }
            }
            .tabViewStyle(.verticalPage)
        } else {
            MetricsPage()
        }
    }
}

/// Dense metric grid that fits everything on one screen — no scroll.
/// Layout: 3 rows × 2 columns of metrics, then a divider, then a
/// compact Pause / End row at the bottom.
private struct MetricsPage: View {
    @Environment(WorkoutManager.self) private var workoutManager
    @Environment(WatchSessionManager.self) private var session
    @Environment(\.isLuminanceReduced) private var isDimmed

    var body: some View {
        VStack(spacing: 0) {
            // ── Metric grid ─────────────────────────────────
            // Grid takes priority — it gets all remaining space after
            // the action row's intrinsic size is reserved at the bottom.
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: isDimmed ? 8 : 6) {
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 4)
            .padding(.top, 2)

            // ── Action row ──────────────────────────────────
            // Hidden in Always-On dim — taps are blocked anyway, so
            // two buttons just eat pixels. Reappears on wrist-raise.
            if !isDimmed {
                HStack(spacing: 8) {
                    Button {
                        workoutManager.togglePause()
                    } label: {
                        Image(systemName: workoutManager.isPaused ? "play.fill" : "pause.fill")
                            .frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.bordered)
                    .tint(.yellow)

                    Button(role: .destructive) {
                        Task {
                            await workoutManager.end()
                            session.send(["kind": "rideControl", "action": "stop"])
                        }
                    } label: {
                        Image(systemName: "stop.fill")
                            .frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
            }
        }
    }

    /// Single metric cell — label on top in tiny caps, value below in
    /// big monospaced digits. The tint coloring helps the rider parse
    /// the grid by glance without reading the labels (red = HR,
    /// green = current speed, etc.).
    private func cell(_ label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(isDimmed ? .white.opacity(0.55) : .secondary)
            Text(value)
                .font(.system(size: isDimmed ? 22 : 19, weight: .bold))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .foregroundStyle(isDimmed ? .white : tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let s = Int(seconds)
        // Drop hours when zero — saves horizontal space in the
        // shorter rides where most of our use lives.
        if s >= 3600 {
            return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
        } else {
            return String(format: "%d:%02d", s / 60, s % 60)
        }
    }

    private func formatDistance(_ meters: Double) -> String {
        meters >= 1000 ? String(format: "%.1f km", meters / 1000) : "\(Int(meters)) m"
    }
}
