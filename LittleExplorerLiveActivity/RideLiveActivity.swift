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
                    .frame(width: 150)
            }

            // ── Right: maneuver + metrics ────────────────────────────
            VStack(alignment: .leading, spacing: 6) {
                if let next = state.nextManeuver, let dist = state.nextManeuverDistanceM {
                    HStack(spacing: 6) {
                        Image(systemName: state.nextManeuverSymbol ?? "arrow.up")
                            .font(.system(size: 13).weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(Color.blue, in: Circle())
                        VStack(alignment: .leading, spacing: 0) {
                            Text(formatMeters(dist))
                                .font(.system(size: 16).weight(.heavy))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                                .lineLimit(1).minimumScaleFactor(0.8)
                            Text(next)
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(1).minimumScaleFactor(0.8)
                        }
                        Spacer(minLength: 0)
                    }
                }

                Divider().background(.white.opacity(0.25))

                // 2×2 grid of metrics, tighter spacing so the right
                // column doesn't overflow on narrower devices.
                VStack(spacing: 5) {
                    HStack(spacing: 6) {
                        compactMetric("KM",       formatDistance(state.distanceKm))
                        compactMetric("VITESSE",  formatSpeed(state.speedKmh))
                    }
                    HStack(spacing: 6) {
                        compactMetric("MOY",      formatSpeed(durationSec: state.durationSec, distKm: state.distanceKm))
                        compactMetric("D+",       "\(Int(state.elevationGainM))m")
                    }
                }

                Text(formatDuration(state.durationSec))
                    .font(.system(size: 10).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
    }

    private func compactMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 8).weight(.bold)).foregroundStyle(.white.opacity(0.6))
            Text(value)
                .font(.system(size: 12).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Lock-screen map: a real MKMapSnapshotter-generated map image
    /// (loaded from the shared App Group container) with the user dot
    /// drawn on top via Canvas overlay so the position stays current.
    /// Falls back to a Canvas-only render if the snapshot file isn't
    /// present yet (first second after navigation start).
    @ViewBuilder
    private func lockMap(polyline: [[Double]], userLat: Double, userLng: Double) -> some View {
        ZStack {
            mapBackground()
            userDotOverlay(polyline: polyline, userLat: userLat, userLng: userLng)
        }
        .frame(height: 150)
        .background(Color.gray.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.15), lineWidth: 1))
    }

    /// Reads the MKMapSnapshotter JPEG from the App Group container.
    /// On first call after navigation start the file might not exist
    /// yet (snapshot runs in the background); we fall back to a
    /// neutral grey while we wait.
    @ViewBuilder
    private func mapBackground() -> some View {
        if let url = MapSnapshotShare.snapshotURL,
           let data = try? Data(contentsOf: url),
           let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
        } else {
            // Fallback gradient — looks more "outdoor map" than a flat
            // black panel while the snapshot is generating.
            LinearGradient(
                colors: [Color(red: 0.20, green: 0.27, blue: 0.20),
                         Color(red: 0.10, green: 0.15, blue: 0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing,
            )
        }
    }

    /// Draw just the user-position dot using the polyline bounds to
    /// project (userLat, userLng) → canvas coordinates. Matches the
    /// extent the MKMapSnapshotter rendered (route bounding box +
    /// 30% padding) so the dot lands where it should on the image.
    @ViewBuilder
    private func userDotOverlay(polyline: [[Double]], userLat: Double, userLng: Double) -> some View {
        Canvas { context, size in
            let lats = polyline.map { $0[0] }
            let lngs = polyline.map { $0[1] }
            guard let minLat = lats.min(), let maxLat = lats.max(),
                  let minLng = lngs.min(), let maxLng = lngs.max() else { return }
            // Same 30% padding as in MapSnapshotShare.generate.
            let centerLat = (minLat + maxLat) / 2
            let centerLng = (minLng + maxLng) / 2
            let halfLat = max(0.0005, (maxLat - minLat) * 0.65)
            let halfLng = max(0.0005, (maxLng - minLng) * 0.65)

            let nx = (userLng - (centerLng - halfLng)) / (halfLng * 2)
            let ny = 1 - (userLat - (centerLat - halfLat)) / (halfLat * 2)
            let p = CGPoint(x: nx * size.width, y: ny * size.height)

            // Dot: white halo + blue core.
            let outer = CGRect(x: p.x - 9, y: p.y - 9, width: 18, height: 18)
            let inner = CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12)
            context.fill(Path(ellipseIn: outer), with: .color(.white))
            context.fill(Path(ellipseIn: inner), with: .color(.blue))
        }
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
