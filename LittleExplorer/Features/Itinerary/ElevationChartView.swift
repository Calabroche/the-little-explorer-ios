import Charts
import SwiftUI

/// Elevation profile chart. Drag horizontally to surface the matching
/// point on the route — the parent reads `selectedIndex` to render a
/// synced marker on the map.
struct ElevationChartView: View {
    let samples: [ElevationSample]
    let ascent: Int
    let descent: Int
    let loading: Bool
    @Binding var selectedIndex: Int?

    var body: some View {
        if samples.isEmpty {
            placeholder
        } else {
            content
        }
    }

    private var placeholder: some View {
        HStack {
            if loading {
                ProgressView().controlSize(.small)
                Text("Calcul du profil d'altitude…")
                    .font(.caption)
                    .foregroundStyle(AppColors.inkLight)
            } else {
                Text("Pas de profil disponible.")
                    .font(.caption)
                    .foregroundStyle(AppColors.inkLight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppColors.creamBorder, lineWidth: 1))
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("PROFIL")
                    .font(.system(size: 9).weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(AppColors.inkLight)
                Spacer()
                Text("D+ \(ascent) m · D− \(descent) m")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.inkMid)
                    .monospacedDigit()
            }
            chart
        }
        .padding(12)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppColors.creamBorder, lineWidth: 1))
    }

    /// Y-axis domain padded a little around the real min/max so the
    /// profile uses the full chart height instead of being squashed
    /// against a 0 baseline. The area then fills from the bottom edge up
    /// to the line, like a proper elevation profile.
    private var yDomain: ClosedRange<Double> {
        let elevs = samples.map(\.elevation)
        let lo = elevs.min() ?? 0
        let hi = elevs.max() ?? (lo + 100)
        let pad = max(10, (hi - lo) * 0.18)
        let floor = max(0, lo - pad)
        let ceil = hi + pad
        return floor...(ceil > floor ? ceil : floor + 1)
    }

    private var chart: some View {
        let domain = yDomain
        return Chart {
            ForEach(samples) { sample in
                AreaMark(
                    x: .value("km", sample.km),
                    yStart: .value("base", domain.lowerBound),
                    yEnd: .value("ele", sample.elevation),
                )
                .foregroundStyle(
                    .linearGradient(
                        colors: [AppColors.green.opacity(0.45), AppColors.green.opacity(0.12)],
                        startPoint: .top, endPoint: .bottom,
                    ),
                )
                .interpolationMethod(.catmullRom)
                LineMark(
                    x: .value("km", sample.km),
                    y: .value("ele", sample.elevation),
                )
                .foregroundStyle(AppColors.green)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.catmullRom)
            }
            if let selectedIndex, samples.indices.contains(selectedIndex) {
                let s = samples[selectedIndex]
                RuleMark(x: .value("km", s.km))
                    .foregroundStyle(AppColors.terra.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                PointMark(
                    x: .value("km", s.km),
                    y: .value("ele", s.elevation),
                )
                .foregroundStyle(AppColors.terra)
                .symbolSize(80)
                .annotation(position: .top, spacing: 2) {
                    Text("\(Int(s.elevation)) m · \(String(format: "%.1f", s.km)) km")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(AppColors.ink)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppColors.creamDark, in: RoundedRectangle(cornerRadius: 3))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 120)
        .chartYScale(domain: domain)
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisValueLabel().font(.system(size: 9))
                AxisGridLine().foregroundStyle(AppColors.creamBorder)
            }
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel().font(.system(size: 9))
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                update(at: value.location, proxy: proxy, geo: geo)
                            }
                            .onEnded { _ in selectedIndex = nil },
                    )
            }
        }
    }

    private func update(at point: CGPoint, proxy: ChartProxy, geo: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else { return }
        let frame = geo[plotFrame]
        let x = max(frame.minX, min(point.x, frame.maxX))
        guard let km: Double = proxy.value(atX: x - frame.minX) else { return }
        var nearest = 0
        var bestDelta = Double.infinity
        for (i, sample) in samples.enumerated() {
            let delta = abs(sample.km - km)
            if delta < bestDelta { bestDelta = delta; nearest = i }
        }
        selectedIndex = nearest
    }
}
