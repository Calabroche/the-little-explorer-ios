import Charts
import SwiftUI

/// Cycling-specific power view: surfaced FTP, FTP-over-time evolution
/// (rolling-max best 20 min × 0.95), and the power-duration curve over
/// 6 standard intervals (1m / 5m / 10m / 20m / 30m / 60m). E-bike rides
/// excluded by both `original_type` and a title regex.
struct FtpView: View {
    @Environment(AppEnvironment.self) private var environment
    private static let riderKg: Double = 66
    private static let defaultFtp: Int = 291

    var body: some View {
        let cyclingActivities = environment.activityStore.activities
            .filter { $0.type == "cycling" }
            .filter { !isElectric($0) }
        let efforts = aggregateBestEfforts(cyclingActivities)
        let best20 = efforts.first(where: { $0.seconds == 1200 })?.power
        let apiFtp = environment.activityStore.activities.first?.ftp
        let estimatedFtp = apiFtp ?? best20.map { Int(Double($0) * 0.95) }
        let effectiveFtp = estimatedFtp ?? Self.defaultFtp
        let wkg = (Double(effectiveFtp) / Self.riderKg * 100).rounded() / 100
        let evolution = buildEvolution(activities: cyclingActivities)
        let excluded = environment.activityStore.activities.filter { $0.type == "cycling" }.count - cyclingActivities.count

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headline()
                ftpCard(value: effectiveFtp, source: apiFtp != nil ? "estimation" : "fallback", wkg: wkg, best20: best20, excluded: excluded)
                evolutionCard(series: evolution)
                pdcCard(efforts: efforts, ftp: effectiveFtp)
                methodology()
            }
            .padding(16)
        }
        .background(AppColors.cream)
        .navigationTitle("FTP")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func headline() -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Votre puissance.")
                .font(.system(.largeTitle, design: .serif).weight(.heavy))
                .foregroundStyle(AppColors.ink)
            Text("En chiffres.")
                .font(.system(.title2, design: .serif).weight(.bold).italic())
                .foregroundStyle(AppColors.terra)
        }
    }

    private func ftpCard(value: Int, source: String, wkg: Double, best20: Int?, excluded: Int) -> some View {
        card(tag: "FTP", label: "PUISSANCE SEUIL · 1 H", color: AppColors.terra) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(value)")
                        .font(.system(size: 56, design: .serif).weight(.heavy))
                        .foregroundStyle(AppColors.terra)
                    Text("W")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.inkLight)
                }
                Text("\(source) · \(String(format: "%.2f", wkg)) W/kg")
                    .font(.caption)
                    .foregroundStyle(AppColors.inkLight)
                if let best20 {
                    Text("Best 20 min : **\(best20) W** · FTP ≈ best 20 min × 0,95")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.inkMid)
                        .lineSpacing(2)
                }
                if excluded > 0 {
                    Text("\(excluded) sortie\(excluded > 1 ? "s" : "") en assistance électrique exclue\(excluded > 1 ? "s" : "").")
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.inkLight)
                }
            }
        }
    }

    // MARK: - FTP Evolution

    private struct EvolutionPoint: Identifiable, Hashable {
        let id: TimeInterval
        let date: Date
        let ftp: Int
        let best20: Int
        let isPr: Bool
    }

    private func buildEvolution(activities: [RideRecord]) -> [EvolutionPoint] {
        let eligible = activities
            .compactMap { activity -> (Date, Int)? in
                guard let v = activity.bestEfforts?.s1200, let d = RideDate.parse(activity.rawDate) else { return nil }
                return (d, v)
            }
            .sorted(by: { $0.0 < $1.0 })

        var runningMax = 0
        var out: [EvolutionPoint] = []
        for (date, v) in eligible {
            let isPr = v > runningMax
            if isPr { runningMax = v }
            let ftp = Int((Double(runningMax) * 0.95).rounded())
            out.append(EvolutionPoint(id: date.timeIntervalSince1970, date: date, ftp: ftp, best20: v, isPr: isPr))
        }
        return out
    }

    private func evolutionCard(series: [EvolutionPoint]) -> some View {
        card(tag: "EVOLUTION", label: "FTP DANS LE TEMPS", color: AppColors.terra) {
            if series.count < 2 {
                Text("Pas encore assez de sorties avec données de puissance.")
                    .font(.caption)
                    .foregroundStyle(AppColors.inkLight)
            } else {
                Chart {
                    ForEach(series) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("FTP", point.ftp),
                        )
                        .foregroundStyle(AppColors.terra)
                        .interpolationMethod(.stepEnd)
                    }
                    ForEach(series.filter(\.isPr)) { point in
                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("FTP", point.ftp),
                        )
                        .foregroundStyle(AppColors.terra)
                        .symbolSize(80)
                    }
                }
                .frame(height: 200)
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisValueLabel().font(.system(size: 9))
                        AxisGridLine().foregroundStyle(AppColors.creamBorder)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                        AxisValueLabel(format: .dateTime.day().month()).font(.system(size: 9))
                    }
                }
            }
        }
    }

    // MARK: - Power-Duration Curve

    private struct BestEffort: Identifiable, Hashable {
        let seconds: Int
        let label: String
        let power: Int?
        let title: String?
        let date: String?
        var id: Int { seconds }
    }

    private func aggregateBestEfforts(_ activities: [RideRecord]) -> [BestEffort] {
        let durations: [(Int, String, KeyPath<BestEfforts, Int?>)] = [
            (60, "1 min", \.s60),
            (300, "5 min", \.s300),
            (600, "10 min", \.s600),
            (1200, "20 min", \.s1200),
            (1800, "30 min", \.s1800),
            (3600, "60 min", \.s3600),
        ]
        return durations.map { sec, label, key in
            var best: Int?
            var bestActivity: RideRecord?
            for activity in activities {
                guard let v = activity.bestEfforts?[keyPath: key] else { continue }
                if best == nil || v > best! {
                    best = v
                    bestActivity = activity
                }
            }
            return BestEffort(
                seconds: sec,
                label: label,
                power: best,
                title: bestActivity?.title,
                date: bestActivity?.date,
            )
        }
    }

    private func pdcCard(efforts: [BestEffort], ftp: Int) -> some View {
        let hasData = efforts.contains { $0.power != nil }
        return card(tag: "PDC", label: "POWER-DURATION CURVE", color: AppColors.green) {
            if !hasData {
                Text("Aucune donnée de puissance pour le moment.")
                    .font(.caption)
                    .foregroundStyle(AppColors.inkLight)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    Chart {
                        ForEach(efforts.compactMap { e -> (Int, Int)? in
                            guard let p = e.power else { return nil }
                            return (e.seconds, p)
                        }, id: \.0) { sec, power in
                            LineMark(
                                x: .value("Durée (s)", sec),
                                y: .value("W", power),
                            )
                            .foregroundStyle(AppColors.green)
                            .symbol(.circle)
                        }
                        RuleMark(y: .value("FTP", ftp))
                            .foregroundStyle(AppColors.terra.opacity(0.7))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                            .annotation(position: .topLeading) {
                                Text("FTP \(ftp) W")
                                    .font(.system(size: 9))
                                    .foregroundStyle(AppColors.terra)
                            }
                    }
                    .frame(height: 220)
                    .chartXScale(domain: 60...3600, type: .log)
                    .chartXAxis {
                        AxisMarks(values: [60, 300, 600, 1200, 1800, 3600]) { value in
                            if let s = value.as(Int.self) {
                                AxisValueLabel { Text(formatDuration(s)).font(.system(size: 9)) }
                            }
                            AxisGridLine().foregroundStyle(AppColors.creamBorder)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { _ in
                            AxisValueLabel().font(.system(size: 9))
                            AxisGridLine().foregroundStyle(AppColors.creamBorder)
                        }
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(efforts) { effort in
                            effortCell(effort)
                        }
                    }
                }
            }
        }
    }

    private func effortCell(_ effort: BestEffort) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(effort.label)
                .font(.system(size: 9).weight(.semibold))
                .tracking(1.0)
                .foregroundStyle(AppColors.inkLight)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(effort.power.map(String.init) ?? "—")
                    .font(.system(.title3, design: .serif).weight(.bold))
                    .foregroundStyle(effort.seconds == 1200 ? AppColors.terra : AppColors.ink)
                if effort.power != nil {
                    Text("W").font(.caption2).foregroundStyle(AppColors.inkLight)
                }
            }
            if let date = effort.date {
                Text(date).font(.system(size: 9)).foregroundStyle(AppColors.inkLight).lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.creamDark, in: RoundedRectangle(cornerRadius: 3))
        .overlay(
            Rectangle().fill(effort.seconds == 1200 ? AppColors.terra : AppColors.creamBorder)
                .frame(height: 2),
            alignment: .top,
        )
    }

    private func methodology() -> some View {
        card(tag: "MÉTHODE", label: "COMMENT EST CALCULÉE LA FTP", color: AppColors.blue) {
            VStack(alignment: .leading, spacing: 10) {
                bullet(title: "Test 20 min", body: "Pédale à fond pendant 20 min après échauffement. Multiplie la puissance moyenne par 0,95.")
                bullet(title: "Test 8 min", body: "Variante plus courte : 2 × 8 min à fond. Prends la meilleure puissance × 0,9.")
                bullet(title: "Ramp test", body: "Augmente la résistance toutes les minutes jusqu'à abandon. FTP ≈ 75 % du dernier palier complété.")
                Text("La FTP affichée ici provient du modèle physique côté serveur — pas besoin de capteur de puissance, l'estimation s'appuie sur GPS + altimétrie + masse rider.")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.inkLight)
                    .lineSpacing(3)
                    .padding(.top, 4)
            }
        }
    }

    private func bullet(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 12).weight(.bold))
                .foregroundStyle(AppColors.ink)
            Text(body)
                .font(.system(size: 12))
                .foregroundStyle(AppColors.inkMid)
                .lineSpacing(2)
        }
    }

    // MARK: - Building blocks

    @ViewBuilder
    private func card<Content: View>(tag: String, label: String, color: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text(tag)
                    .font(.system(size: 9).weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(color)
                Rectangle().fill(AppColors.creamBorder).frame(width: 24, height: 1)
                Text(label)
                    .font(.system(size: 9).weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(AppColors.inkLight)
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppColors.creamBorder, lineWidth: 1))
    }

    private func formatDuration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        return "1h"
    }

    private func isElectric(_ a: RideRecord) -> Bool {
        if a.originalType == "EBikeRide" { return true }
        let title = a.title.lowercased()
        return title.contains("électrique") || title.contains("electrique")
            || title.contains("e-bike") || title.contains("ebike")
            || title.contains("assistance")
    }
}
