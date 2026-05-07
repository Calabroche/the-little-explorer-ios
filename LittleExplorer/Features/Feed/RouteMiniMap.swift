import MapKit
import SwiftUI

/// Compact, non-interactive map preview for an activity card. Renders
/// the GPS polyline split into ~80 segments coloured by instantaneous
/// speed (red→green hue gradient, hsl 0–120) — matches the web app's
/// CardMap. Falls back to a single sport-coloured polyline when no
/// speed stream is available.
struct RouteMiniMap: View {
    let gps: [Coordinate]
    let speedKmh: [Double]?
    let fallbackColor: Color
    var height: CGFloat = 180

    var body: some View {
        if gps.count < 2 {
            placeholder
        } else {
            content
        }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(AppColors.creamDark)
            .frame(height: height)
            .overlay(
                Image(systemName: "map.fill")
                    .foregroundStyle(AppColors.inkLight),
            )
    }

    private var content: some View {
        let downsampled = downsample(gps, max: 200)
        let segments = (speedKmh.map { $0.count >= 2 ? buildSegments(positions: downsampled, speeds: $0, targetSegments: 80) : [] }) ?? []
        let region = makeRegion(positions: downsampled)
        return Map(initialPosition: .region(region), interactionModes: []) {
            if !segments.isEmpty {
                ForEach(segments.indices, id: \.self) { i in
                    MapPolyline(coordinates: segments[i].coordinates.map(\.clLocation))
                        .stroke(segments[i].color, lineWidth: 3)
                }
            } else {
                MapPolyline(coordinates: downsampled.map(\.clLocation))
                    .stroke(fallbackColor, lineWidth: 3)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .frame(height: height)
        .allowsHitTesting(false)
    }

    // MARK: - Helpers

    /// Down-sample to keep map render fast on long rides.
    private func downsample(_ points: [Coordinate], max: Int) -> [Coordinate] {
        guard points.count > max else { return points }
        let step = Swift.max(1, points.count / max)
        var out: [Coordinate] = []
        out.reserveCapacity(max + 1)
        for i in stride(from: 0, to: points.count, by: step) { out.append(points[i]) }
        if out.last != points.last, let last = points.last { out.append(last) }
        return out
    }

    private func makeRegion(positions: [Coordinate]) -> MKCoordinateRegion {
        let lats = positions.map(\.lat)
        let lngs = positions.map(\.lng)
        let center = CLLocationCoordinate2D(
            latitude: (lats.min()! + lats.max()!) / 2,
            longitude: (lngs.min()! + lngs.max()!) / 2,
        )
        let span = MKCoordinateSpan(
            latitudeDelta: Swift.max(0.01, (lats.max()! - lats.min()!) * 1.25),
            longitudeDelta: Swift.max(0.01, (lngs.max()! - lngs.min()!) * 1.25),
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    private struct Segment {
        let coordinates: [Coordinate]
        let color: Color
    }

    /// Split the polyline into roughly `targetSegments` chunks, coloured by
    /// each chunk's average speed. Maps speed to hue 0 (red) → 120 (green).
    private func buildSegments(
        positions: [Coordinate],
        speeds: [Double],
        targetSegments: Int,
    ) -> [Segment] {
        let n = positions.count
        guard n >= 2, !speeds.isEmpty else { return [] }

        // Map each position index to a speed via ratio (streams may be
        // sampled at different cadence than the GPS polyline).
        var mapped: [Double] = []
        mapped.reserveCapacity(n)
        for i in 0..<n {
            let si = Int(((Double(i) / Double(n - 1)) * Double(speeds.count - 1)).rounded())
            mapped.append(speeds[Swift.min(Swift.max(si, 0), speeds.count - 1)])
        }
        let sorted = mapped.sorted()
        let minS = sorted.first ?? 0
        let maxS = sorted.last ?? 1
        let range = (maxS - minS) > 0 ? (maxS - minS) : 1

        let chunkSize = Swift.max(1, n / targetSegments)
        var result: [Segment] = []
        var i = 0
        while i < n - 1 {
            let end = Swift.min(i + chunkSize + 1, n)
            let chunk = mapped[i..<end]
            let avg = chunk.reduce(0, +) / Double(chunk.count)
            let t = (avg - minS) / range
            let hue = t * 120 / 360 // SwiftUI's Color(hue:) takes 0–1
            let color = Color(hue: hue, saturation: 0.9, brightness: 0.55)
            result.append(Segment(coordinates: Array(positions[i..<end]), color: color))
            i += chunkSize
        }
        return result
    }
}
