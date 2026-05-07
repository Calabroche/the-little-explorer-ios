import SwiftUI

/// Personal Records card. For cycling, surfaces best 1m/5m/10m/20m/30m/60m
/// power efforts (e-bike rides excluded). For running, sweeps the speed
/// stream to find the fastest 1/2/5/10/21.1 km windows.
/// Returns nil-rendering for sports without a comparable benchmark.
struct PersonalRecordsView: View {
    let activities: [RideRecord]
    let sport: Sport

    var body: some View {
        Group {
            switch sport {
            case .cycling: cyclingRecords
            case .running: runningRecords
            default:       EmptyView()
            }
        }
    }

    // MARK: - Cycling power records

    private struct PowerPR: Identifiable {
        let label: String
        let value: Int
        let date: String
        let title: String
        var id: String { label }
    }

    @ViewBuilder
    private var cyclingRecords: some View {
        let records = pickBestPower()
        card(tag: "RECORDS", label: "MEILLEURES PERFS", color: AppColors.terra) {
            if records.isEmpty {
                emptyMessage("Pas encore de mesure de puissance.")
            } else {
                LazyVGrid(columns: gridColumns(records.count), spacing: 8) {
                    ForEach(records) { record in
                        recordCard(
                            label: "BEST \(record.label)",
                            value: "\(record.value)",
                            unit: "W",
                            color: AppColors.terra,
                            date: record.date,
                            title: record.title,
                        )
                    }
                }
            }
        }
    }

    private func pickBestPower() -> [PowerPR] {
        struct Slot {
            let key: KeyPath<BestEfforts, Int?>
            let label: String
        }
        let slots: [Slot] = [
            Slot(key: \.s60, label: "1 min"),
            Slot(key: \.s300, label: "5 min"),
            Slot(key: \.s600, label: "10 min"),
            Slot(key: \.s1200, label: "20 min"),
            Slot(key: \.s1800, label: "30 min"),
            Slot(key: \.s3600, label: "60 min"),
        ]
        var out: [PowerPR] = []
        for slot in slots {
            var best = 0
            var bestRecord: RideRecord?
            for activity in activities where !isElectric(activity) {
                guard let value = activity.bestEfforts?[keyPath: slot.key], value > best else { continue }
                best = value
                bestRecord = activity
            }
            if let bestRecord, best > 0 {
                out.append(PowerPR(
                    label: slot.label,
                    value: best,
                    date: bestRecord.date,
                    title: bestRecord.title,
                ))
            }
        }
        return out
    }

    private func isElectric(_ a: RideRecord) -> Bool {
        if a.originalType == "EBikeRide" { return true }
        let lower = a.title.lowercased()
        return lower.contains("électrique") || lower.contains("electrique")
            || lower.contains("e-bike") || lower.contains("ebike")
            || lower.contains("assistance")
    }

    // MARK: - Running pace records

    private struct PacePR: Identifiable {
        let km: Double
        let secPerKm: Double
        let date: String
        let title: String
        var id: Double { km }

        var label: String { km < 21 ? "\(km == floor(km) ? Int(km).description : km.description) km" : "Semi" }
        var formatted: String {
            let total = Int(secPerKm.rounded())
            return String(format: "%d:%02d", total / 60, total % 60)
        }
    }

    @ViewBuilder
    private var runningRecords: some View {
        let paces = [1.0, 2.0, 5.0, 10.0, 21.1].compactMap { pickBestPace(targetKm: $0) }
        card(tag: "RECORDS", label: "MEILLEURES ALLURES", color: AppColors.green) {
            if paces.isEmpty {
                emptyMessage("Pas encore d'allure mesurée.")
            } else {
                LazyVGrid(columns: gridColumns(paces.count), spacing: 8) {
                    ForEach(paces) { pace in
                        recordCard(
                            label: pace.label,
                            value: pace.formatted,
                            unit: "/km",
                            color: AppColors.green,
                            date: pace.date,
                            title: pace.title,
                        )
                    }
                }
            }
        }
    }

    private func pickBestPace(targetKm: Double) -> PacePR? {
        var best: PacePR?
        let targetM = targetKm * 1000
        for activity in activities {
            guard activity.type == "running" else { continue }
            guard let dist = activity.distanceM, dist.count >= 30 else { continue }
            guard let speed = activity.speedKmh, speed.count >= 30 else { continue }
            guard let activityDistance = activity.distance, activityDistance >= targetKm else { continue }

            // Slide the index window: shrink while distance covered ≥ target.
            var lo = 0
            var bestSec = Double.infinity
            for hi in 1..<dist.count {
                while dist[hi] - dist[lo] >= targetM, lo < hi {
                    let dt = Double(hi - lo) // 1 Hz samples
                    if dt < bestSec { bestSec = dt }
                    lo += 1
                }
            }

            if bestSec.isFinite, bestSec > 30 {
                let secPerKm = bestSec / targetKm
                if best == nil || secPerKm < best!.secPerKm {
                    best = PacePR(km: targetKm, secPerKm: secPerKm, date: activity.date, title: activity.title)
                }
            }
        }
        return best
    }

    // MARK: - Building blocks

    private func gridColumns(_ count: Int) -> [GridItem] {
        // 2 per row on phones (≈ web's mobile fallback); 3 wide otherwise.
        Array(repeating: GridItem(.flexible(), spacing: 8), count: min(count, 3))
    }

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
        .padding(20)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppColors.creamBorder, lineWidth: 1))
    }

    private func recordCard(label: String, value: String, unit: String, color: Color, date: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9).weight(.semibold))
                .tracking(1.0)
                .foregroundStyle(AppColors.inkLight)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(.title2, design: .serif).weight(.bold))
                    .foregroundStyle(color)
                Text(unit).font(.caption).foregroundStyle(AppColors.inkLight)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(date).font(.system(size: 9)).foregroundStyle(AppColors.inkLight)
                Text(title).font(.system(size: 9)).foregroundStyle(AppColors.inkMid).lineLimit(1)
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.creamDark, in: RoundedRectangle(cornerRadius: 3))
        .overlay(
            Rectangle().fill(color)
                .frame(height: 2),
            alignment: .top,
        )
    }

    private func emptyMessage(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(AppColors.inkLight)
            .padding(.vertical, 8)
    }
}
