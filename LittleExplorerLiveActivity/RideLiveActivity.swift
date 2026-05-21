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
        VStack(alignment: .leading, spacing: 8) {
            // Compact top row: sport + elapsed time on the right.
            HStack {
                Label(attributes.sportLabel, systemImage: "bicycle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text(formatDuration(state.durationSec))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }

            // Live map preview — shows the route polyline + the user's
            // current position. Renders only when we have BOTH a
            // polyline (set when navigation started) and a recent
            // user coordinate (pushed every second via state updates).
            if let polyline = attributes.routePolyline,
               polyline.count >= 2,
               let lat = state.userLat,
               let lng = state.userLng {
                lockMap(polyline: polyline, userLat: lat, userLng: lng)
            }

            // Next maneuver above the metrics so it's the first thing
            // the user sees when they glance at their lock screen.
            if let next = state.nextManeuver, let dist = state.nextManeuverDistanceM {
                HStack(spacing: 10) {
                    Image(systemName: state.nextManeuverSymbol ?? "arrow.up")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.blue, in: Circle())
                    VStack(alignment: .leading, spacing: 0) {
                        Text(formatMeters(dist))
                            .font(.title3.weight(.heavy))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                        Text(next)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                    }
                    Spacer()
                }
            }

            // Four-column metrics row (Distance / Speed / Avg / Elev)
            // — user wanted more info than the original 3-up layout.
            // Avg speed is duration-weighted so it stays meaningful
            // when the user pauses at a light etc.
            HStack(spacing: 12) {
                metric("Distance", formatDistance(state.distanceKm))
                metric("Speed",    formatSpeed(state.speedKmh))
                metric("Avg",      formatSpeed(durationSec: state.durationSec, distKm: state.distanceKm))
                metric("Elev",     "\(Int(state.elevationGainM)) m")
            }
        }
        .padding()
    }

    /// Mini map preview rendered via SwiftUI Canvas — MapKit's `Map`
    /// view is NOT allowed in Widget / Live Activity contexts (you get
    /// the iOS "no entry" placeholder if you try). We project the
    /// polyline + user position into a 0..1 box centered on the user,
    /// then draw with `Canvas`. Window is ~1 km on the long side so
    /// the user sees enough route ahead.
    @ViewBuilder
    private func lockMap(polyline: [[Double]], userLat: Double, userLng: Double) -> some View {
        let windowMeters: Double = 1000
        let cosLat = cos(userLat * .pi / 180)
        let dLat = windowMeters / 111_000
        let dLng = windowMeters / (111_000 * max(cosLat, 0.0001))

        Canvas { context, size in
            // Map a (lat, lng) to canvas coordinates. Latitude is flipped
            // because Canvas's Y axis points down.
            func project(_ lat: Double, _ lng: Double) -> CGPoint {
                let nx = (lng - (userLng - dLng / 2)) / dLng
                let ny = 1 - (lat - (userLat - dLat / 2)) / dLat
                return CGPoint(x: nx * size.width, y: ny * size.height)
            }

            // Route polyline — dark outline + bright blue stroke for
            // contrast on the Live Activity's dark background.
            var path = Path()
            var started = false
            for pair in polyline where pair.count >= 2 {
                let p = project(pair[0], pair[1])
                if !started {
                    path.move(to: p); started = true
                } else {
                    path.addLine(to: p)
                }
            }
            context.stroke(path, with: .color(.black.opacity(0.5)), lineWidth: 7)
            context.stroke(path, with: .color(.blue),               lineWidth: 4)

            // User dot dead-center.
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let outer  = CGRect(x: center.x - 9, y: center.y - 9, width: 18, height: 18)
            let inner  = CGRect(x: center.x - 6, y: center.y - 6, width: 12, height: 12)
            context.fill(Path(ellipseIn: outer), with: .color(.white))
            context.fill(Path(ellipseIn: inner), with: .color(.blue))
        }
        .frame(height: 200)
        .background(Color.white.opacity(0.06))
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
