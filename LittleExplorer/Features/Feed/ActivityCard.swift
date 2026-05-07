import SwiftUI

/// Rich activity card matching the web's editorial layout.
/// Mobile arrangement (top→bottom):
///   1. Sport pill + date · location
///   2. Weather chip
///   3. Title (Playfair-style serif)
///   4. Map preview with speed-coloured polyline
///   5. Primary stats grid (Durée / Distance / Moy / Max)
///   6. Terrain stats grid (Montée / Pente max / Pente min / FC moy)
///   7. Advanced metrics row (NP / TSS / W·kg / TRIMP / IF)
struct ActivityCard: View {
    let activity: RideRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let title = nonEmptyTitle { titleView(title) }
            mapPreview
            primaryStats
            if hasTerrainOrHrStats { terrainStats }
            if hasAdvancedMetrics { metricsRow }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppColors.creamBorder, lineWidth: 1))
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                sportPill
                Text("\(activity.date) · \(activity.location ?? "—")")
                    .font(.system(size: 10).weight(.semibold))
                    .tracking(1.4)
                    .foregroundStyle(AppColors.inkLight)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            if let weather = activity.weather, weather.temp != nil {
                weatherBadge(weather: weather)
            }
        }
    }

    private var sportPill: some View {
        let sport = Sport(backendType: activity.type)
        let label = sport?.displayName.uppercased() ?? activity.type.uppercased()
        return HStack(spacing: 5) {
            Image(systemName: sport?.symbol ?? "figure.run").font(.system(size: 9))
            Text(label).font(.system(size: 10).weight(.bold)).tracking(1.2)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(sport?.color ?? AppColors.terra, in: Capsule())
        .foregroundStyle(.white)
    }

    private func weatherBadge(weather: Weather) -> some View {
        HStack(spacing: 8) {
            Image(systemName: weatherSymbol(for: weather.description))
                .foregroundStyle(AppColors.inkLight)
                .font(.system(size: 12))
            if let t = weather.temp {
                Text(String(format: "%.0f°C", t))
            }
            if let w = weather.windspeed {
                Text("\(Int(w)) km/h")
            }
            if let h = weather.humidity {
                Text("\(h)% hum.")
            }
            if let desc = weather.description {
                Text(desc)
                    .foregroundStyle(AppColors.inkMid)
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 11))
        .foregroundStyle(AppColors.inkLight)
    }

    private func weatherSymbol(for description: String?) -> String {
        guard let description else { return "cloud" }
        switch description.lowercased() {
        case let s where s.contains("ensoleillé") || s.contains("sunny"): return "sun.max.fill"
        case let s where s.contains("nuageux") || s.contains("cloudy"):    return "cloud.fill"
        case let s where s.contains("brouillard") || s.contains("fog"):    return "cloud.fog.fill"
        case let s where s.contains("pluie") || s.contains("rain"):        return "cloud.rain.fill"
        case let s where s.contains("neige") || s.contains("snow"):        return "snow"
        case let s where s.contains("averse") || s.contains("shower"):     return "cloud.heavyrain.fill"
        case let s where s.contains("orage") || s.contains("storm"):       return "cloud.bolt.fill"
        default: return "cloud.fill"
        }
    }

    // MARK: - Title + Map

    private var nonEmptyTitle: String? {
        let trimmed = activity.title.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func titleView(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 22, design: .serif).weight(.bold))
            .foregroundStyle(AppColors.ink)
            .lineLimit(2)
            .lineSpacing(2)
            .multilineTextAlignment(.leading)
    }

    @ViewBuilder
    private var mapPreview: some View {
        let sport = Sport(backendType: activity.type)
        if !activity.gps.isEmpty {
            RouteMiniMap(
                gps: activity.gps,
                speedKmh: activity.speedKmh,
                fallbackColor: sport?.color ?? AppColors.terra,
                height: 170,
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppColors.creamBorder, lineWidth: 1))
        }
    }

    // MARK: - Primary stats grid

    private var primaryStats: some View {
        VStack(spacing: 10) {
            Divider().background(AppColors.creamBorder)
            statsGrid(
                stats: [
                    Stat(label: "DURÉE",    value: activity.duration, unit: nil),
                    Stat(label: "DISTANCE", value: activity.distance.map(formatDistance), unit: "km"),
                    Stat(label: speedLabel, value: speedValue, unit: speedUnit),
                    Stat(label: "MAX",      value: activity.maxSpeed.map { String(format: "%.1f", $0) }, unit: "km/h"),
                ],
            )
        }
    }

    private var hasTerrainOrHrStats: Bool {
        activity.elevation != nil
            || activity.maxIncline != nil
            || activity.minIncline != nil
            || activity.avgHr != nil
    }

    private var terrainStats: some View {
        VStack(spacing: 10) {
            Divider().background(AppColors.creamBorder)
            statsGrid(
                stats: [
                    Stat(label: "MONTÉE",     value: activity.elevation.map { String(format: "%.1f", $0) }, unit: "m"),
                    Stat(label: "▲ PENTE MAX", value: activity.maxIncline.map { String(format: "%+.1f", $0) }, unit: "%"),
                    Stat(label: "▼ PENTE MIN", value: activity.minIncline.map { String(format: "%.1f", $0) }, unit: "%"),
                    Stat(label: "FC MOY",      value: activity.avgHr.map { String(format: "%.1f", $0) }, unit: "bpm"),
                ],
            )
        }
    }

    // MARK: - Advanced metrics row

    private var hasAdvancedMetrics: Bool {
        activity.np != nil || activity.tss != nil || activity.wkg != nil || activity.trimp != nil || activity.ifFactor != nil
    }

    private var metricsRow: some View {
        VStack(spacing: 10) {
            Divider().background(AppColors.creamBorder)
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                if let np = activity.np {
                    metric(label: "NP", value: "\(np)", unit: "W", color: AppColors.green)
                }
                if let tss = activity.tss {
                    metric(label: "TSS", value: "\(tss)", unit: nil, color: AppColors.terra)
                }
                if let wkg = activity.wkg {
                    metric(label: "W/KG", value: String(format: "%.2f", wkg), unit: nil, color: AppColors.blue)
                }
                if let trimp = activity.trimp {
                    metric(label: "TRIMP", value: "\(trimp)", unit: nil, color: AppColors.inkMid)
                }
                if let ifFactor = activity.ifFactor {
                    metric(label: "IF", value: String(format: "%.2f", ifFactor), unit: nil, color: AppColors.inkMid)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func metric(label: String, value: String, unit: String?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 9).weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(AppColors.inkLight)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 22, design: .serif).weight(.bold))
                    .foregroundStyle(color)
                    .monospacedDigit()
                if let unit {
                    Text(unit)
                        .font(.system(size: 10))
                        .foregroundStyle(AppColors.inkLight)
                }
            }
        }
    }

    // MARK: - Helpers

    private struct Stat {
        let label: String
        let value: String?
        let unit: String?
    }

    private func statsGrid(stats: [Stat]) -> some View {
        let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return LazyVGrid(columns: columns, spacing: 14) {
            ForEach(Array(stats.enumerated()), id: \.offset) { _, stat in
                statCell(stat)
            }
        }
    }

    private func statCell(_ stat: Stat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(stat.label)
                .font(.system(size: 9).weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(AppColors.inkLight)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(stat.value ?? "—")
                    .font(.system(size: 24, design: .serif).weight(.bold))
                    .foregroundStyle(AppColors.ink)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let unit = stat.unit, stat.value != nil {
                    Text(unit)
                        .font(.system(size: 10))
                        .foregroundStyle(AppColors.inkLight)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formatDistance(_ km: Double) -> String {
        String(format: "%.2f", km)
    }

    // Pace for running, otherwise average speed.
    private var speedLabel: String { activity.type == "running" ? "ALLURE" : "MOY" }
    private var speedUnit: String? { activity.type == "running" ? "/km" : "km/h" }
    private var speedValue: String? {
        if activity.type == "running", activity.distance ?? 0 > 0 {
            let total = Double(activity.durationMin) * 60 / max(activity.distance ?? 1, 0.001)
            let secs = Int(total.rounded())
            return String(format: "%d:%02d", secs / 60, secs % 60)
        }
        return activity.speed.map { String(format: "%.1f", $0) }
    }
}
