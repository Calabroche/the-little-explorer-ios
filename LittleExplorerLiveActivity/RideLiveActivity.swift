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

            HStack(spacing: 16) {
                metric("Distance", formatDistance(state.distanceKm))
                metric("Speed", formatSpeed(state.speedKmh))
                metric("Elev", "\(Int(state.elevationGainM)) m")
            }
            if let next = state.nextManeuver, let dist = state.nextManeuverDistanceM {
                HStack(spacing: 8) {
                    Image(systemName: state.nextManeuverSymbol ?? "arrow.up")
                    Text(next).lineLimit(1)
                    Spacer()
                    Text(formatMeters(dist)).monospacedDigit()
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white)
                .padding(8)
                .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding()
    }

    /// Tiny MapKit preview: the (downsampled) route polyline drawn in
    /// blue, with a blue dot for the user's current position. The
    /// camera is framed on a tight box around the user (≈800 m on the
    /// long side) so the view follows them as they ride.
    @ViewBuilder
    private func lockMap(polyline: [[Double]], userLat: Double, userLng: Double) -> some View {
        let coords = polyline.compactMap { pair -> CLLocationCoordinate2D? in
            guard pair.count >= 2 else { return nil }
            return CLLocationCoordinate2D(latitude: pair[0], longitude: pair[1])
        }
        let user = CLLocationCoordinate2D(latitude: userLat, longitude: userLng)
        let region = MKCoordinateRegion(
            center: user,
            latitudinalMeters: 700,
            longitudinalMeters: 700,
        )
        Map(initialPosition: .region(region)) {
            MapPolyline(coordinates: coords)
                .stroke(Color.blue, lineWidth: 5)
            Annotation("", coordinate: user) {
                ZStack {
                    Circle().fill(Color.blue).frame(width: 14, height: 14)
                    Circle().stroke(Color.white, lineWidth: 2).frame(width: 14, height: 14)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .frame(height: 140)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .allowsHitTesting(false)
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

private func formatMeters(_ meters: Double) -> String {
    meters >= 1000 ? String(format: "%.1f km", meters / 1000) : "\(Int(meters)) m"
}
