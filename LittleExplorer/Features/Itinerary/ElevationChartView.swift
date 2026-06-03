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
            gradeLegend
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppColors.creamBorder, lineWidth: 1))
    }

    private var gradeLegend: some View {
        HStack(spacing: 12) {
            ForEach(Array(zip(Self.bandColors, ["0–2 %", "3–5 %", "6–10 %", "> 10 %"]).enumerated()), id: \.offset) { _, pair in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(pair.0).frame(width: 11, height: 7)
                    Text(pair.1).font(.system(size: 9)).foregroundStyle(AppColors.inkLight)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
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
            // Profile coloured by slope: each contiguous grade band is its own
            // series so the area/line take the band colour (green ≤2 %, yellow
            // 3-5 %, orange 6-10 %, red >10 %).
            ForEach(gradeBands()) { band in
                ForEach(band.samples) { s in
                    AreaMark(
                        x: .value("km", s.km),
                        yStart: .value("base", domain.lowerBound),
                        yEnd: .value("ele", s.elevation),
                        series: .value("band", band.id),
                    )
                    .foregroundStyle(band.color.opacity(0.5))
                    .interpolationMethod(.catmullRom)
                }
                ForEach(band.samples) { s in
                    LineMark(
                        x: .value("km", s.km),
                        y: .value("ele", s.elevation),
                        series: .value("band", band.id),
                    )
                    .foregroundStyle(band.color)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.catmullRom)
                }
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
                .annotation(
                    position: .top,
                    alignment: .center,
                    spacing: 2,
                    // Keep the tooltip within the chart so it doesn't shove
                    // the plot smaller when you scrub near the edges.
                    overflowResolution: .init(x: .fit(to: .chart), y: .disabled),
                ) {
                    let grade = gradePercent(at: selectedIndex)
                    HStack(spacing: 5) {
                        Text("\(Int(s.elevation)) m")
                            .foregroundStyle(AppColors.ink)
                        if let grade {
                            Text("\(grade >= 0 ? "+" : "")\(Int(grade.rounded()))%")
                                .fontWeight(.bold)
                                .foregroundStyle(grade >= 3 ? AppColors.terra : (grade <= -3 ? AppColors.blue : AppColors.inkMid))
                        }
                        Text(String(format: "%.1f km", s.km))
                            .foregroundStyle(AppColors.inkLight)
                    }
                    .font(.caption2.monospacedDigit())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AppColors.creamDark, in: RoundedRectangle(cornerRadius: 3))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 150)
        .chartYScale(domain: domain)
        // Pin the x-domain to the data so the profile fills the full width —
        // by default Charts rounds the axis up and leaves a void on the right.
        .chartXScale(domain: (samples.first?.km ?? 0)...max(samples.last?.km ?? 1, (samples.first?.km ?? 0) + 0.1))
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

    /// Local grade (%) around a sample: Δelevation / Δdistance over the
    /// neighbouring samples, signed (+ uphill, − downhill).
    private func gradePercent(at index: Int) -> Double? {
        guard samples.count >= 2 else { return nil }
        let lo = max(0, index - 1)
        let hi = min(samples.count - 1, index + 1)
        guard hi > lo else { return nil }
        let dEle = samples[hi].elevation - samples[lo].elevation
        let dDistM = (samples[hi].km - samples[lo].km) * 1000
        guard dDistM > 1 else { return nil }
        return dEle / dDistM * 100
    }

    // MARK: - Grade banding

    private struct GradeBand: Identifiable { let id: Int; let color: Color; let samples: [ElevationSample] }

    static let bandColors: [Color] = [
        Color(red: 0.36, green: 0.60, blue: 0.37),  // green  ≤2 %
        Color(red: 0.89, green: 0.76, blue: 0.24),  // yellow 3-5 %
        Color(red: 0.88, green: 0.53, blue: 0.24),  // orange 6-10 %
        Color(red: 0.75, green: 0.22, blue: 0.17),  // red    >10 %
    ]

    private func gradeBandIndex(_ g: Double) -> Int {
        if g < 3 { return 0 }
        if g < 6 { return 1 }
        if g <= 10 { return 2 }
        return 3
    }

    /// Split the profile into contiguous runs of the same grade band so each
    /// can be drawn in its slope colour. Each run repeats the boundary sample
    /// so adjacent bands visually connect.
    private func gradeBands() -> [GradeBand] {
        guard samples.count >= 2 else {
            return samples.isEmpty ? [] : [GradeBand(id: 0, color: Self.bandColors[0], samples: samples)]
        }
        var runs: [(idx: Int, pts: [ElevationSample])] = []
        for i in 1..<samples.count {
            let dDist = (samples[i].km - samples[i - 1].km) * 1000
            let grade = dDist > 1 ? (samples[i].elevation - samples[i - 1].elevation) / dDist * 100 : 0
            let bi = gradeBandIndex(grade)
            if !runs.isEmpty, runs[runs.count - 1].idx == bi {
                runs[runs.count - 1].pts.append(samples[i])
            } else {
                runs.append((idx: bi, pts: [samples[i - 1], samples[i]]))
            }
        }
        return runs.enumerated().map { GradeBand(id: $0.offset, color: Self.bandColors[$0.element.idx], samples: $0.element.pts) }
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
