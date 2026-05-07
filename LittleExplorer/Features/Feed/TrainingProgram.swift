import Charts
import SwiftUI

/// TSS-driven training summary: bar chart of the last 10 rides, average
/// reference line, recent gap stats, predicted next-ride date, and the
/// classic "10% rule" explainer card. Cycling-only — bails out otherwise.
struct TrainingProgramView: View {
    let activities: [RideRecord]

    var body: some View {
        let sorted = activities.sortedRecentFirst
        let last5  = Array(sorted.prefix(5))
        let last10 = Array(sorted.prefix(10))
        if last5.count < 2 {
            EmptyView()
        } else {
            content(last5: last5, last10: last10)
        }
    }

    @ViewBuilder
    private func content(last5: [RideRecord], last10: [RideRecord]) -> some View {
        let avgTSSAll = average(activities.compactMap(\.tss).map(Double.init))
        let avgTSS10  = average(last10.compactMap(\.tss).map(Double.init))
        let avgTSS5   = average(last5.compactMap(\.tss).map(Double.init))
        let lastTSS   = last5.first?.tss
        let targetTSS = avgTSS5.map { Int(($0 * 1.1).rounded()) }

        let gaps = computeGaps(last5)
        let avgGap = gaps.isEmpty ? 0 : Int((Double(gaps.reduce(0, +)) / Double(gaps.count)).rounded())
        let nextDate = computeNextDate(from: last5, avgGap: avgGap)
        let daysUntil = nextDate.map { RideDate.daysBetween(from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: $0)) } ?? 0

        let avgDist = Int((last5.compactMap(\.distance).reduce(0, +) / Double(max(last5.count, 1))).rounded())
        let avgElev = Int((last5.compactMap(\.elevation).reduce(0, +) / Double(max(last5.count, 1))).rounded())

        let advice = recommendation(lastTSS: lastTSS, avgTSS5: avgTSS5)

        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Text("PROGRAM")
                    .font(.system(size: 9).weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(AppColors.terra)
                Rectangle().fill(AppColors.creamBorder).frame(width: 24, height: 1)
                Text("PROGRAMME D'ENTRAÎNEMENT")
                    .font(.system(size: 9).weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(AppColors.inkLight)
            }

            chart(last10: last10, avgTSSAll: avgTSSAll)

            HStack(spacing: 24) {
                statBlock(label: "INTERVALLE MOYEN", value: "\(avgGap)j")
                if let v = avgTSS10 {
                    statBlock(label: "TSS MOYEN (10)", value: "\(Int(v.rounded()))")
                }
            }

            Divider().background(AppColors.creamBorder)

            // Next ride compact row.
            if let nextDate {
                FlowRow(spacing: 16) {
                    nextRideHeadline(date: nextDate, daysUntil: daysUntil)
                    nextRideStat(label: "DISTANCE", value: "\(avgDist)", unit: "km")
                    nextRideStat(label: "DÉNIVELÉ", value: "\(avgElev)", unit: "m")
                    if let target = targetTSS {
                        nextRideStat(label: "TSS CIBLE", value: "\(target)", color: AppColors.terra)
                    }
                }
            }

            Divider().background(AppColors.creamBorder)

            VStack(alignment: .leading, spacing: 12) {
                Text("RECOMMANDATION")
                    .font(.system(size: 9).weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(AppColors.inkLight)
                Text(advice)
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.inkMid)
                    .lineSpacing(4)

                rulesCard(title: "RÈGLE DES 10 %", body: "Augmentez la charge de TSS de 10 % maximum par semaine pour progresser sans risquer la blessure.", titleColor: AppColors.ink)
                rulesCard(title: "TSS — TRAINING STRESS SCORE", body: "Mesure l'effort relatif d'une sortie en s'appuyant sur la puissance normalisée (NP), l'intensité (IF) et la durée. Référence : 100 = sortie complète à FTP pendant 1 h. < 50 récup, 100–150 sortie qualité, > 150 charge élevée.", titleColor: AppColors.terra)
            }
        }
        .padding(20)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppColors.creamBorder, lineWidth: 1))
    }

    // MARK: - Chart

    private struct ChartPoint: Identifiable {
        let id: Int
        let date: String
        let dateFull: String
        let tss: Int
        let power: Int?
        let distance: Double?
        let elevation: Double?
    }

    private func chart(last10: [RideRecord], avgTSSAll: Double?) -> some View {
        let chronological = last10.reversed()
        let formatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "dd/MM"
            return f
        }()
        let fullFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "EEE d MMMM"
            f.locale = Locale(identifier: "fr_FR")
            return f
        }()
        let points: [ChartPoint] = chronological.enumerated().map { index, activity in
            let parsed = RideDate.parse(activity.rawDate) ?? Date()
            return ChartPoint(
                id: index,
                date: formatter.string(from: parsed),
                dateFull: fullFormatter.string(from: parsed),
                tss: activity.tss ?? 0,
                power: activity.avgPower,
                distance: activity.distance,
                elevation: activity.elevation,
            )
        }

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("TSS — DERNIÈRES SORTIES")
                    .font(.system(size: 9).weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(AppColors.inkLight)
                Spacer()
                if avgTSSAll != nil {
                    HStack(spacing: 4) {
                        Rectangle().fill(AppColors.terra).frame(width: 8, height: 8)
                        Text("TSS").font(.system(size: 9)).foregroundStyle(AppColors.inkLight)
                    }
                }
            }

            Chart {
                ForEach(points) { p in
                    BarMark(
                        x: .value("Date", p.date),
                        y: .value("TSS", p.tss),
                    )
                    .foregroundStyle(AppColors.terra)
                    .cornerRadius(3)
                }
                if let avg = avgTSSAll {
                    RuleMark(y: .value("Moyenne", avg))
                        .foregroundStyle(AppColors.terra.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .annotation(position: .topLeading) {
                            Text("moy. \(Int(avg.rounded()))")
                                .font(.system(size: 9))
                                .foregroundStyle(AppColors.terra)
                        }
                }
            }
            .frame(height: 180)
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
        }
    }

    // MARK: - Helpers

    private func computeGaps(_ activities: [RideRecord]) -> [Int] {
        var gaps: [Int] = []
        for i in 0..<(activities.count - 1) {
            guard let later   = RideDate.parse(activities[i].rawDate),
                  let earlier = RideDate.parse(activities[i + 1].rawDate) else { continue }
            gaps.append(RideDate.daysBetween(from: earlier, to: later))
        }
        return gaps
    }

    private func computeNextDate(from last5: [RideRecord], avgGap: Int) -> Date? {
        guard let lastDate = last5.first.flatMap({ RideDate.parse($0.rawDate) }) else { return nil }
        return Calendar.current.date(byAdding: .day, value: avgGap, to: lastDate)
    }

    private func recommendation(lastTSS: Int?, avgTSS5: Double?) -> String {
        guard let lastTSS, let avgTSS5 else {
            return "Reprends quand tu te sens prêt — la régularité prime sur l'intensité."
        }
        let last = Double(lastTSS)
        if last > avgTSS5 * 1.3 {
            return "Sortie intense par rapport à ta moyenne. Privilégie une sortie de récupération (TSS faible, allure conversation)."
        }
        if last < avgTSS5 * 0.7 {
            return "Charge faible récemment. Tu peux pousser un peu plus si la forme est là."
        }
        if avgTSS5 > 80 {
            return "Bon volume de charge. Garde une sortie facile dans la semaine pour absorber l'entraînement."
        }
        return "Charge équilibrée. Continue sur cette dynamique en visant un peu plus long ou plus dur la prochaine sortie."
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    @ViewBuilder
    private func statBlock(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 9).weight(.semibold))
                .tracking(1.0)
                .foregroundStyle(AppColors.inkLight)
            Text(value)
                .font(.system(.title3, design: .serif).weight(.bold))
                .foregroundStyle(AppColors.ink)
        }
    }

    @ViewBuilder
    private func nextRideHeadline(date: Date, daysUntil: Int) -> some View {
        let formatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "EEEE d MMMM"
            f.locale = Locale(identifier: "fr_FR")
            return f
        }()
        VStack(alignment: .leading, spacing: 2) {
            Text("PROCHAINE SORTIE")
                .font(.system(size: 9).weight(.semibold))
                .tracking(1.0)
                .foregroundStyle(AppColors.inkLight)
            Text(formatter.string(from: date))
                .font(.system(.callout, design: .serif).weight(.bold))
                .foregroundStyle(AppColors.terra)
            Text(daysCopy(daysUntil))
                .font(.system(size: 10))
                .foregroundStyle(AppColors.inkLight)
        }
    }

    private func daysCopy(_ days: Int) -> String {
        if days > 0 { return "dans \(days) jour\(days > 1 ? "s" : "")" }
        if days == 0 { return "aujourd'hui" }
        return "il y a \(abs(days)) jour\(abs(days) > 1 ? "s" : "")"
    }

    private func nextRideStat(label: String, value: String, unit: String? = nil, color: Color = AppColors.ink) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9).weight(.semibold))
                .tracking(1.0)
                .foregroundStyle(AppColors.inkLight)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(.callout, design: .serif).weight(.bold))
                    .foregroundStyle(color)
                if let unit {
                    Text(unit).font(.system(size: 9)).foregroundStyle(AppColors.inkLight)
                }
            }
        }
    }

    private func rulesCard(title: String, body: String, titleColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11).weight(.semibold))
                .foregroundStyle(titleColor)
            Text(body)
                .font(.system(size: 11))
                .foregroundStyle(AppColors.inkLight)
                .lineSpacing(3)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.creamDark, in: RoundedRectangle(cornerRadius: 4))
    }
}

/// One-line flow that wraps its children when they exceed available width.
struct FlowRow: Layout {
    var spacing: CGFloat = 12

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews: subviews, in: proposal.width ?? .infinity).total
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(subviews: subviews, in: bounds.width)
        for (index, subview) in subviews.enumerated() {
            let frame = result.frames[index]
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrange(subviews: Subviews, in maxWidth: CGFloat) -> (frames: [CGRect], total: CGSize) {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x + s.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(x: x, y: y, width: s.width, height: s.height))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
            totalWidth = max(totalWidth, x - spacing)
        }
        return (frames, CGSize(width: totalWidth, height: y + rowHeight))
    }
}
