import MapKit
import SwiftUI

/// Big interactive route map for the activity detail view.
/// Renders the polyline split into ~200 segments coloured by speed
/// (red→green hue gradient — same scheme as the web's
/// ActivityRouteMap), plus a tappable overlay that drops a marker +
/// summary popup at the closest sample point on every drag.
///
/// Uses MapReader so we can convert a touch point into a real
/// CLLocationCoordinate2D and then snap to the nearest GPS sample.
struct RouteAnalysisMap: View {
    let activity: RideRecord
    var height: CGFloat = 380
    /// Optional climb / segment to highlight on top of the base
    /// route. Indices are into the activity's gps array; we clamp
    /// defensively. Used by ActivityDetailView when the user taps
    /// a climb in the Climbs card — the matching stretch lights up
    /// here so the eye can locate it on the map.
    var highlightSegment: (startIdx: Int, endIdx: Int)? = nil

    @State private var cameraPosition: MapCameraPosition
    @State private var hovered: Hovered?
    @State private var clearTask: Task<Void, Never>?

    init(activity: RideRecord, height: CGFloat = 380, highlightSegment: (startIdx: Int, endIdx: Int)? = nil) {
        self.activity = activity
        self.height = height
        self.highlightSegment = highlightSegment
        let positions = activity.gps
        let region: MKCoordinateRegion = {
            guard !positions.isEmpty else {
                return MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: 45.75, longitude: 4.85),
                    span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5),
                )
            }
            let lats = positions.map(\.lat)
            let lngs = positions.map(\.lng)
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(
                    latitude: (lats.min()! + lats.max()!) / 2,
                    longitude: (lngs.min()! + lngs.max()!) / 2,
                ),
                span: MKCoordinateSpan(
                    latitudeDelta: max(0.02, (lats.max()! - lats.min()!) * 1.4),
                    longitudeDelta: max(0.02, (lngs.max()! - lngs.min()!) * 1.4),
                ),
            )
        }()
        self._cameraPosition = State(initialValue: .region(region))
    }

    var body: some View {
        let segments = buildSegments()
        let gradient = PowerStream.gradient(for: activity)

        MapReader { proxy in
            ZStack(alignment: .topLeading) {
                map(segments: segments)
                    .frame(height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppColors.creamBorder, lineWidth: 1))
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                updateHover(at: value.location, proxy: proxy, gradient: gradient)
                            }
                            .onEnded { _ in
                                clearTask?.cancel()
                                clearTask = Task {
                                    try? await Task.sleep(for: .seconds(8))
                                    if !Task.isCancelled {
                                        await MainActor.run { hovered = nil }
                                    }
                                }
                            },
                    )
                if let hovered {
                    samplePopup(hovered: hovered)
                        .padding(12)
                }
            }
        }
    }

    // MARK: - Map view

    private func map(segments: [Segment]) -> some View {
        Map(position: $cameraPosition, interactionModes: [.zoom]) {
            ForEach(segments.indices, id: \.self) { i in
                MapPolyline(coordinates: segments[i].coords.map(\.clLocation))
                    .stroke(segments[i].color, lineWidth: 5)
            }

            // Climb highlight — drawn after the base segments so it
            // sits on top. Two layers: a soft semi-transparent halo
            // (mimics the web's "glow") then a punchy core stroke.
            // Indices clamped into the GPS array length.
            if let highlight = highlightSegment {
                let coords = clampedHighlightCoordinates(highlight)
                if coords.count > 1 {
                    MapPolyline(coordinates: coords)
                        .stroke(AppColors.terra.opacity(0.35), style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    MapPolyline(coordinates: coords)
                        .stroke(AppColors.terra, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                }
            }

            if let hovered {
                Annotation("", coordinate: hovered.coordinate) {
                    Circle()
                        .fill(AppColors.terra)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(Color.white, lineWidth: 2.5))
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
    }

    /// Convert a (startIdx, endIdx) tuple into a CLLocationCoordinate2D
    /// array that's safe to render — clamps each index into the GPS
    /// array's bounds (Strava sometimes returns slightly mismatched
    /// stream lengths so a climb's endIndex can momentarily point
    /// past `gps.count`).
    private func clampedHighlightCoordinates(_ highlight: (startIdx: Int, endIdx: Int)) -> [CLLocationCoordinate2D] {
        let positions = activity.gps
        guard !positions.isEmpty else { return [] }
        let s = max(0, min(highlight.startIdx, positions.count - 1))
        let e = max(s, min(highlight.endIdx, positions.count - 1))
        if e - s < 1 { return [] }
        return positions[s...e].map(\.clLocation)
    }

    // MARK: - Sample popup

    private struct Hovered {
        let coordinate: CLLocationCoordinate2D
        let sample: RouteSample
    }

    private func samplePopup(hovered: Hovered) -> some View {
        let sample = hovered.sample
        let signed = sample.gradientPct >= 0 ? "+\(sample.gradientPct)" : "\(sample.gradientPct)"
        let speedHue = max(0, min(1, sample.speedKmh / 50)) * 120 / 360
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(hue: speedHue, saturation: 0.9, brightness: 0.55))
                    .frame(width: 11, height: 11)
                Text("\(formatKm(sample.distKm)) km · pente \(signed)%")
                    .font(.system(size: 11).weight(.bold))
                    .tracking(0.5)
                    .foregroundStyle(AppColors.ink)
            }
            if let hr = sample.heartRate {
                row(label: "FC", value: "\(hr) bpm")
            }
            row(label: "Vitesse", value: String(format: "%.1f km/h", sample.speedKmh))
            row(label: "Puissance", value: "\(sample.powerW) W")
            if let alt = sample.altitude {
                row(label: "Altitude", value: "\(alt) m")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minWidth: 180, alignment: .leading)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppColors.creamBorder, lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    private func row(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label).foregroundStyle(AppColors.inkMid)
            Text(": ").foregroundStyle(AppColors.inkMid)
            Text(value).fontWeight(.bold).foregroundStyle(AppColors.ink)
        }
        .font(.system(size: 11))
        .monospacedDigit()
    }

    private func formatKm(_ km: Double) -> String {
        String(format: "%.2f", km)
    }

    // MARK: - Segments (speed-coloured)

    private struct Segment {
        let coords: [Coordinate]
        let color: Color
    }

    private func buildSegments() -> [Segment] {
        let positions = activity.gps
        let speeds = activity.speedKmh ?? []
        let n = positions.count
        guard n >= 2, !speeds.isEmpty else {
            return [Segment(coords: positions, color: AppColors.terra)]
        }

        var mapped = Array(repeating: 0.0, count: n)
        for i in 0..<n {
            let si = Int(((Double(i) / Double(n - 1)) * Double(speeds.count - 1)).rounded())
            mapped[i] = speeds[max(0, min(si, speeds.count - 1))]
        }
        let minS = mapped.min() ?? 0
        let maxS = mapped.max() ?? 1
        let range = (maxS - minS) > 0 ? (maxS - minS) : 1

        let target = 200
        let chunk = max(1, n / target)
        var out: [Segment] = []
        var i = 0
        while i < n - 1 {
            let end = min(i + chunk + 1, n)
            let avg = mapped[i..<end].reduce(0, +) / Double(end - i)
            let t = (avg - minS) / range
            let hue = t * 120 / 360
            out.append(Segment(
                coords: Array(positions[i..<end]),
                color: Color(hue: hue, saturation: 0.9, brightness: 0.55),
            ))
            i += chunk
        }
        return out
    }

    // MARK: - Hover handling

    private func updateHover(at point: CGPoint, proxy: MapProxy, gradient: [Double]) {
        guard !activity.gps.isEmpty else { return }
        guard let coord = proxy.convert(point, from: .local) else { return }
        let target = Coordinate(lat: coord.latitude, lng: coord.longitude)

        // Two-pass nearest neighbour search (coarse then fine).
        let positions = activity.gps
        var bestIdx = 0
        var bestDist = Double.infinity
        for i in stride(from: 0, to: positions.count, by: 5) {
            let d = sqDistance(positions[i], target)
            if d < bestDist { bestDist = d; bestIdx = i }
        }
        let lo = max(0, bestIdx - 10)
        let hi = min(positions.count - 1, bestIdx + 10)
        for i in lo...hi {
            let d = sqDistance(positions[i], target)
            if d < bestDist { bestDist = d; bestIdx = i }
        }
        let snapped = positions[bestIdx]
        let sample = PowerStream.sample(at: bestIdx, activity: activity, gradient: gradient)
        clearTask?.cancel()
        withAnimation(.easeOut(duration: 0.12)) {
            hovered = Hovered(coordinate: snapped.clLocation, sample: sample)
        }
    }

    private func sqDistance(_ a: Coordinate, _ b: Coordinate) -> Double {
        let dLat = a.lat - b.lat
        let dLng = a.lng - b.lng
        return dLat * dLat + dLng * dLng
    }
}
