import SwiftUI

/// Averages across the 5 most-recent activities, plus a row of 5 mini cards
/// (one per ride) so the user can compare the most recent against the rest.
struct Last5StatsView: View {
    let activities: [RideRecord]

    var body: some View {
        let sorted = activities.sortedRecentFirst
        let last5 = Array(sorted.prefix(5))
        if last5.count < 2 {
            EmptyView()
        } else {
            content(last5: last5)
        }
    }

    @ViewBuilder
    private func content(last5: [RideRecord]) -> some View {
        let dur      = formatAvgDuration(last5)
        let dist     = avg(last5.map(\.distance))
        let elev     = avgInt(last5.map(\.elevation))
        let speed    = avg(last5.map(\.speed))
        let hr       = avgInt(last5.map(\.avgHr))
        let np       = avgInt(last5.map { $0.np.map(Double.init) })
        let avgPower = avgInt(last5.map { $0.avgPower.map(Double.init) })
        let tss      = avgInt(last5.map { $0.tss.map(Double.init) })
        let wkg      = avg(last5.map(\.wkg))
        let cal      = avgInt(last5.map { $0.calories.map(Double.init) })

        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Text("LAST 5")
                    .font(.system(size: 9).weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(AppColors.blue)
                Rectangle().fill(AppColors.creamBorder).frame(width: 24, height: 1)
                Text("MOYENNES SUR LES 5 DERNIÈRES")
                    .font(.system(size: 9).weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(AppColors.inkLight)
            }

            // Averages row.
            FlowLayout(spacing: 16) {
                stat(label: "DURÉE", value: dur)
                stat(label: "DISTANCE", value: dist.map { String(format: "%.1f", $0) }, unit: "km")
                stat(label: "DÉNIVELÉ", value: elev.map(String.init), unit: "m")
                stat(label: "VITESSE", value: speed.map { String(format: "%.1f", $0) }, unit: "km/h")
                if let hr { stat(label: "FC", value: "\(hr)", unit: "bpm", color: AppColors.terra) }
                if let avgPower { stat(label: "PUISSANCE", value: "\(avgPower)", unit: "W", color: AppColors.green) }
                if let np { stat(label: "NP", value: "\(np)", unit: "W", color: AppColors.green) }
                if let tss { stat(label: "TSS", value: "\(tss)", color: AppColors.terra) }
                if let wkg { stat(label: "W/KG", value: String(format: "%.1f", wkg), color: AppColors.blue) }
                if let cal { stat(label: "KCAL", value: "\(cal)") }
            }
            .padding(.bottom, 16)

            Divider().background(AppColors.creamBorder)

            // 5 ride cards — horizontal carousel. Each card sized to
            // ~half the available width so 1.5 are visible at a time
            // (full first card + half of next as a peek), and snaps
            // to the nearest card on swipe-end. Lets every metric
            // breathe in big serif type instead of cramming all 5
            // cards onto one line.
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(Array(last5.enumerated()), id: \.element.id) { index, activity in
                        miniCard(activity: activity, isMostRecent: index == 0)
                            .containerRelativeFrame(.horizontal, count: 2, span: 1, spacing: 12)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
            // Page indicator: 5 dots, one per card; the active one
            // highlights as the user swipes through.
            HStack(spacing: 6) {
                ForEach(0..<last5.count, id: \.self) { _ in
                    Circle()
                        .fill(AppColors.creamBorder)
                        .frame(width: 4, height: 4)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
        }
        .padding(20)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppColors.creamBorder, lineWidth: 1))
    }

    @ViewBuilder
    private func stat(label: String, value: String?, unit: String? = nil, color: Color = AppColors.ink) -> some View {
        if let value {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.system(size: 9).weight(.semibold))
                    .tracking(1.0)
                    .foregroundStyle(AppColors.inkLight)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value)
                        .font(.system(.title3, design: .serif).weight(.bold))
                        .foregroundStyle(color)
                    if let unit {
                        Text(unit).font(.system(size: 11)).foregroundStyle(AppColors.inkLight)
                    }
                }
            }
            .frame(minWidth: 70, alignment: .leading)
        }
    }

    private func miniCard(activity: RideRecord, isMostRecent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: date + most-recent dot.
            HStack(alignment: .firstTextBaseline) {
                Text(activity.date)
                    .font(.system(size: 10).weight(.semibold))
                    .tracking(1.4)
                    .foregroundStyle(AppColors.inkLight)
                Spacer()
                if isMostRecent {
                    HStack(spacing: 4) {
                        Circle().fill(AppColors.terra).frame(width: 6, height: 6)
                        Text("RÉCENT")
                            .font(.system(size: 9).weight(.bold))
                            .tracking(1.2)
                            .foregroundStyle(AppColors.terra)
                    }
                }
            }

            // Hero: distance in big serif.
            Text(activity.distance.map { String(format: "%.2f km", $0) } ?? "—")
                .font(.system(size: 28, design: .serif).weight(.heavy))
                .foregroundStyle(AppColors.ink)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            // 2-column stats grid — gives every metric room to breathe
            // instead of stacking them as one column of micro-text.
            LazyVGrid(columns: [
                GridItem(.flexible(), alignment: .leading),
                GridItem(.flexible(), alignment: .leading),
            ], alignment: .leading, spacing: 10) {
                miniStat(label: "DURÉE", value: activity.duration, unit: nil, color: AppColors.ink)
                miniStat(label: "DÉNIVELÉ", value: activity.elevation.map { "\(Int($0))" }, unit: "m", color: AppColors.ink)
                if let tss = activity.tss {
                    miniStat(label: "TSS", value: "\(tss)", unit: nil, color: AppColors.terra)
                }
                if let np = activity.np {
                    miniStat(label: "NP", value: "\(np)", unit: "W", color: AppColors.green)
                } else if let power = activity.avgPower {
                    miniStat(label: "PUISSANCE", value: "\(power)", unit: "W", color: AppColors.green)
                }
                if let hr = activity.avgHr {
                    miniStat(label: "FC", value: "\(Int(hr.rounded()))", unit: "bpm", color: AppColors.terra)
                }
                if let wkg = activity.wkg {
                    miniStat(label: "W/KG", value: String(format: "%.2f", wkg), unit: nil, color: AppColors.blue)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
        .background(AppColors.creamDark, in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            Rectangle()
                .fill(isMostRecent ? AppColors.terra : AppColors.creamBorder)
                .frame(height: 4),
            alignment: .top,
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func miniStat(label: String, value: String?, unit: String?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9).weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(AppColors.inkLight)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value ?? "—")
                    .font(.system(size: 18, design: .serif).weight(.heavy))
                    .foregroundStyle(color)
                    .monospacedDigit()
                if let unit, value != nil {
                    Text(unit)
                        .font(.system(size: 10))
                        .foregroundStyle(AppColors.inkLight)
                }
            }
        }
    }

    // MARK: - Aggregations

    private func avg(_ values: [Double?]) -> Double? {
        let cleaned = values.compactMap { $0 }
        guard !cleaned.isEmpty else { return nil }
        return (cleaned.reduce(0, +) / Double(cleaned.count) * 10).rounded() / 10
    }

    private func avgInt(_ values: [Double?]) -> Int? {
        avg(values).map { Int($0.rounded()) }
    }

    private func formatAvgDuration(_ activities: [RideRecord]) -> String? {
        let mins = activities.map(\.durationMin)
        guard !mins.isEmpty else { return nil }
        let avg = Int((Double(mins.reduce(0, +)) / Double(mins.count)).rounded())
        return "\(avg / 60)h \(avg % 60)m"
    }
}

extension Array where Element == RideRecord {
    /// Sort most-recent first using rawDate (ISO).
    var sortedRecentFirst: [RideRecord] {
        sorted { lhs, rhs in
            let l = RideDate.parse(lhs.rawDate) ?? .distantPast
            let r = RideDate.parse(rhs.rawDate) ?? .distantPast
            return l > r
        }
    }
}

/// Simple flow layout that wraps children to multiple lines once they
/// exceed the available width — used for the averages row so it adapts
/// to the 7-or-10 visible stats depending on sport / data.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 12

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        return arrange(subviews: subviews, in: maxWidth).totalSize
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(subviews: subviews, in: bounds.width)
        for (index, subview) in subviews.enumerated() {
            let frame = result.frames[index]
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrange(subviews: Subviews, in maxWidth: CGFloat) -> (frames: [CGRect], totalSize: CGSize) {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            totalWidth = max(totalWidth, x - spacing)
        }
        return (frames, CGSize(width: totalWidth, height: y + rowHeight))
    }
}
