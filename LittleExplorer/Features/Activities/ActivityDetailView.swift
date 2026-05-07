import MapKit
import SwiftUI

struct ActivityDetailView: View {
    let activity: RideRecord

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                map
                metricsGrid
                if let altitude = activity.altitude, !altitude.isEmpty {
                    elevationChart(altitude)
                }
            }
            .padding()
        }
        .navigationTitle(activity.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var map: some View {
        Map {
            MapPolyline(coordinates: activity.gps.map(\.clLocation))
                .stroke(Color.accentColor, lineWidth: 4)
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .allowsHitTesting(false)
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            metric("Distance", value: activity.distance.map { String(format: "%.2f km", $0) } ?? "—")
            metric("Duration", value: activity.duration)
            metric("Avg speed", value: activity.speed.map { String(format: "%.1f km/h", $0) } ?? "—")
            metric("Elevation", value: activity.elevation.map { "\(Int($0)) m" } ?? "—")
            if let np = activity.np { metric("NP", value: "\(np) W") }
            if let avgHr = activity.avgHr { metric("Avg HR", value: "\(Int(avgHr)) bpm") }
            if let tss = activity.tss { metric("TSS", value: "\(tss)") }
            if let calories = activity.calories { metric("Calories", value: "\(calories) kcal") }
        }
    }

    private func metric(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.title3).fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func elevationChart(_ altitudes: [Double]) -> some View {
        // Simple inline area sparkline — full Charts integration is a v0+ TODO.
        GeometryReader { proxy in
            let minA = altitudes.min() ?? 0
            let maxA = altitudes.max() ?? 1
            let range = max(maxA - minA, 1)
            let step = proxy.size.width / CGFloat(max(altitudes.count - 1, 1))
            Path { path in
                path.move(to: CGPoint(x: 0, y: proxy.size.height))
                for (i, alt) in altitudes.enumerated() {
                    let x = CGFloat(i) * step
                    let y = proxy.size.height - (CGFloat((alt - minA) / range) * proxy.size.height)
                    path.addLine(to: CGPoint(x: x, y: y))
                }
                path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height))
                path.closeSubpath()
            }
            .fill(Color.accentColor.opacity(0.3))
        }
        .frame(height: 100)
        .padding(.top, 8)
    }
}
