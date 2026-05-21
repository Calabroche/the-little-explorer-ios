import ActivityKit
import CoreLocation
import MapKit
import SwiftUI
import WidgetKit

struct RideLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RideActivityAttributes.self) { context in
            // Lock Screen / banner.
            LockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.7))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(formatDistance(context.state.distanceKm), systemImage: "bicycle")
                        .font(.caption.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Label(formatDuration(context.state.durationSec), systemImage: "clock")
                        .font(.caption.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("SPEED").font(.caption2).foregroundStyle(.secondary)
                            Text(formatSpeed(context.state.speedKmh)).font(.title3.weight(.bold)).monospacedDigit()
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("ELEV").font(.caption2).foregroundStyle(.secondary)
                            Text("\(Int(context.state.elevationGainM)) m").font(.title3.weight(.bold)).monospacedDigit()
                        }
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: "bicycle").foregroundStyle(.tint)
            } compactTrailing: {
                Text(formatDistance(context.state.distanceKm)).monospacedDigit()
            } minimal: {
                Image(systemName: "bicycle").foregroundStyle(.tint)
            }
        }
    }
}

private struct LockScreenView: View {
    let attributes: RideActivityAttributes
    let state: RideActivityAttributes.RideState

    var body: some View {
        // Horizontal layout — map on the left, vertical stack of
        // (next-maneuver + 4 metrics) on the right. iOS caps the
        // Live Activity lock-screen presentation at roughly 200pt of
        // height, so stacking everything vertically caused content to
        // get cropped. Going side-by-side packs the same info under
        // that ceiling.
        HStack(alignment: .top, spacing: 12) {
            // ── Left: map ─────────────────────────────────────────────
            if let polyline = attributes.routePolyline,
               polyline.count >= 2,
               let lat = state.userLat,
               let lng = state.userLng {
                lockMap(polyline: polyline, userLat: lat, userLng: lng)
                    .frame(width: 130)
            }

            // ── Right: maneuver + metrics ────────────────────────────
            VStack(alignment: .leading, spacing: 10) {
                // Small top padding so the maneuver chip doesn't
                // touch the banner's rounded top edge.
                if let next = state.nextManeuver, let dist = state.nextManeuverDistanceM {
                    HStack(spacing: 8) {
                        Image(systemName: state.nextManeuverSymbol ?? "arrow.up")
                            .font(.system(size: 16).weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(Color.blue, in: Circle())
                        VStack(alignment: .leading, spacing: 0) {
                            Text(formatMeters(dist))
                                .font(.system(size: 20).weight(.heavy))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                                .lineLimit(1).minimumScaleFactor(0.7)
                            Text(next)
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 4)
                }

                Divider().background(.white.opacity(0.25))

                // 2×2 grid of metrics — values at 20pt heavy so they
                // dominate the right column.
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        compactMetric("KM",       formatDistance(state.distanceKm))
                        compactMetric("VITESSE",  formatSpeed(state.speedKmh))
                    }
                    HStack(spacing: 8) {
                        compactMetric("MOY",      formatSpeed(durationSec: state.durationSec, distKm: state.distanceKm))
                        compactMetric("D+",       "\(Int(state.elevationGainM))m")
                    }
                }

                // Duration with bigger font + clock icon.
                HStack(spacing: 5) {
                    Image(systemName: "clock").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                    Text(formatDuration(state.durationSec))
                        .font(.system(size: 17).weight(.heavy))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
    }

    private func compactMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 10).weight(.bold)).foregroundStyle(.white.opacity(0.55))
            Text(value)
                .font(.system(size: 20).weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Lock-screen map preview rendered via SwiftUI Canvas.
    /// We project (lat, lng) → canvas coordinates inside a 1-km window
    /// centered on the user, then stroke the route polyline + paint
    /// the user dot. We tried shipping a real MKMapSnapshotter JPEG
    /// via an App Group shared container, but App Group entitlements
    /// don't sign cleanly on a Personal Team free account — the device
    /// build refused to launch — so we're back to the Canvas-only
    /// version with a muted dark-green background that at least feels
    /// outdoor-map-y instead of stark black.
    @ViewBuilder
    private func lockMap(polyline: [[Double]], userLat: Double, userLng: Double) -> some View {
        let windowMeters: Double = 1000
        let cosLat = cos(userLat * .pi / 180)
        let dLat = windowMeters / 111_000
        let dLng = windowMeters / (111_000 * max(cosLat, 0.0001))

        Canvas { context, size in
            func project(_ lat: Double, _ lng: Double) -> CGPoint {
                let nx = (lng - (userLng - dLng / 2)) / dLng
                let ny = 1 - (lat - (userLat - dLat / 2)) / dLat
                return CGPoint(x: nx * size.width, y: ny * size.height)
            }

            var path = Path()
            var started = false
            for pair in polyline where pair.count >= 2 {
                let p = project(pair[0], pair[1])
                if !started { path.move(to: p); started = true }
                else { path.addLine(to: p) }
            }
            context.stroke(path, with: .color(.black.opacity(0.5)), lineWidth: 7)
            context.stroke(path, with: .color(.blue),               lineWidth: 4)

            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let outer  = CGRect(x: center.x - 9, y: center.y - 9, width: 18, height: 18)
            let inner  = CGRect(x: center.x - 6, y: center.y - 6, width: 12, height: 12)
            context.fill(Path(ellipseIn: outer), with: .color(.white))
            context.fill(Path(ellipseIn: inner), with: .color(.blue))
        }
        .frame(height: 150)
        .background(
            LinearGradient(
                colors: [Color(red: 0.20, green: 0.27, blue: 0.20),
                         Color(red: 0.10, green: 0.15, blue: 0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing,
            ),
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.15), lineWidth: 1))
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(.caption2).foregroundStyle(.white.opacity(0.7))
            Text(value).font(.title3.weight(.bold)).monospacedDigit().foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Formatting (kept local — Formatters.swift lives in Shared but
// importing the iOS module from a widget extension isn't free in xcodegen).

private func formatDistance(_ km: Double) -> String {
    String(format: "%.2f km", km)
}

private func formatDuration(_ seconds: Double) -> String {
    let s = Int(seconds)
    let h = s / 3600
    let m = (s % 3600) / 60
    return h > 0 ? String(format: "%d:%02d", h, m) : String(format: "%d:%02d", m, s % 60)
}

private func formatSpeed(_ kmh: Double) -> String {
    String(format: "%.1f km/h", kmh)
}

/// Duration-weighted average speed in km/h. Returns 0 km/h before any
/// real motion so the lock-screen banner doesn't flash bogus values.
private func formatSpeed(durationSec: Double, distKm: Double) -> String {
    guard durationSec > 0, distKm > 0 else { return "0.0 km/h" }
    let avg = distKm / (durationSec / 3600)
    return String(format: "%.1f km/h", avg)
}

private func formatMeters(_ meters: Double) -> String {
    meters >= 1000 ? String(format: "%.1f km", meters / 1000) : "\(Int(meters)) m"
}
