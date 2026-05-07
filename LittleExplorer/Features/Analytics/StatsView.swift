import SwiftUI

/// Total distance, distance by sport, elevation by sport, monthly
/// activity bars for the current year. Mirrors the web's StatsPage.
struct StatsView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        let activities = environment.activityStore.activities
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headline(activities: activities)
                distanceCard(activities: activities)
                elevationCard(activities: activities)
                monthlyCard(activities: activities)
            }
            .padding(16)
        }
        .background(AppColors.cream)
        .navigationTitle("Statistiques")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func headline(activities: [RideRecord]) -> some View {
        let totalKm = activities.compactMap(\.distance).reduce(0, +)
        return VStack(alignment: .leading, spacing: 4) {
            Text("\(Int(totalKm.rounded()).formatted()) km")
                .font(.system(.largeTitle, design: .serif).weight(.heavy))
                .foregroundStyle(AppColors.ink)
            Text("parcourus.")
                .font(.system(.title2, design: .serif).weight(.bold).italic())
                .foregroundStyle(AppColors.terra)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func distanceCard(activities: [RideRecord]) -> some View {
        let cycling = activities.filtered(by: .cycling).compactMap(\.distance).reduce(0, +)
        let hiking = activities.filtered(by: .hiking).compactMap(\.distance).reduce(0, +)
        let longest = activities.compactMap(\.distance).max() ?? 0
        let avg = activities.isEmpty
            ? 0
            : activities.compactMap(\.distance).reduce(0, +) / Double(activities.count)
        let scaleMax = max(cycling, hiking, 1) * 1.2

        return card(label: "DISTANCE · PAR ACTIVITÉ") {
            VStack(spacing: 10) {
                statBar(label: "Vélo · total", value: cycling, max: scaleMax, unit: "km", color: AppColors.terra)
                statBar(label: "Randonnée · total", value: hiking, max: scaleMax, unit: "km", color: AppColors.green)
                statBar(label: "Sortie la plus longue", value: longest, max: longest * 1.5, unit: "km", color: AppColors.blue)
                statBar(label: "Moyenne / sortie", value: avg, max: longest, unit: "km", color: AppColors.inkLight)
            }
        }
    }

    private func elevationCard(activities: [RideRecord]) -> some View {
        let total = activities.compactMap(\.elevation).reduce(0, +)
        let cycling = activities.filtered(by: .cycling).compactMap(\.elevation).reduce(0, +)
        let hiking = activities.filtered(by: .hiking).compactMap(\.elevation).reduce(0, +)
        let record = activities.compactMap(\.elevation).max() ?? 0

        return card(label: "DÉNIVELÉ · CUMULÉ") {
            VStack(spacing: 10) {
                statBar(label: "Total D+", value: total, max: total * 1.1, unit: "m", color: AppColors.terra)
                statBar(label: "Vélo · D+", value: cycling, max: total, unit: "m", color: AppColors.terra)
                statBar(label: "Rando · D+", value: hiking, max: total, unit: "m", color: AppColors.green)
                statBar(label: "Record sortie", value: record, max: total, unit: "m", color: AppColors.blue)
            }
        }
    }

    private func monthlyCard(activities: [RideRecord]) -> some View {
        let calendar = Calendar(identifier: .gregorian)
        let currentYear = calendar.component(.year, from: Date())
        let currentMonth = calendar.component(.month, from: Date()) - 1
        var monthValues = Array(repeating: 0, count: 12)
        for activity in activities {
            guard let date = RideDate.parse(activity.rawDate) else { continue }
            guard calendar.component(.year, from: date) == currentYear else { continue }
            let m = calendar.component(.month, from: date) - 1
            if monthValues.indices.contains(m) { monthValues[m] += 1 }
        }
        let maxMonth = max(monthValues.max() ?? 1, 1)
        let labels = ["J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"]

        return card(label: "ACTIVITÉ · PAR MOIS \(currentYear)") {
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(0..<12, id: \.self) { i in
                    VStack(spacing: 4) {
                        let height = max(monthValues[i] == 0 ? 0 : 4, CGFloat(monthValues[i]) / CGFloat(maxMonth) * 100)
                        let color: Color = i == currentMonth
                            ? AppColors.terra
                            : (monthValues[i] > 0 ? AppColors.inkLight : AppColors.creamBorder)
                        Rectangle().fill(color)
                            .frame(maxWidth: .infinity)
                            .frame(height: height)
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                        Text(labels[i])
                            .font(.system(size: 9))
                            .foregroundStyle(AppColors.inkLight)
                    }
                }
            }
            .frame(height: 124, alignment: .bottom)
        }
    }

    @ViewBuilder
    private func card<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(label)
                .font(.system(size: 9).weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(AppColors.inkLight)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppColors.creamBorder, lineWidth: 1))
    }

    private func statBar(label: String, value: Double, max: Double, unit: String, color: Color) -> some View {
        let pct = max <= 0 ? 0 : value / max
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.system(size: 11)).foregroundStyle(AppColors.inkMid)
                Spacer()
                HStack(spacing: 2) {
                    Text("\(Int(value.rounded()).formatted())")
                        .font(.system(.subheadline, design: .serif).weight(.bold))
                        .foregroundStyle(AppColors.ink)
                        .monospacedDigit()
                    Text(unit).font(.caption).foregroundStyle(AppColors.inkLight)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1).fill(AppColors.creamDark).frame(height: 4)
                    RoundedRectangle(cornerRadius: 1).fill(color).frame(width: geo.size.width * pct, height: 4)
                }
            }
            .frame(height: 4)
        }
    }
}
