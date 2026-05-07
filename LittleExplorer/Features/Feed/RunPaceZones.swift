import SwiftUI

/// Critical Velocity-driven training zones for running.
/// CV = best 20-min pace / 0.95. Zones bracket around that anchor.
struct RunPaceZonesView: View {
    let activities: [RideRecord]

    var body: some View {
        let cv = computeCV()
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Text("ZONES")
                    .font(.system(size: 9).weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(AppColors.green)
                Rectangle().fill(AppColors.creamBorder).frame(width: 24, height: 1)
                Text("ZONES D'ALLURE — RUNNING")
                    .font(.system(size: 9).weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(AppColors.inkLight)
            }
            if let cv {
                cvDisplay(cv: cv)
                zonesList(cv: cv)
            } else {
                Text("Pas encore assez de données running (≥ 20 min de stream).")
                    .font(.caption)
                    .foregroundStyle(AppColors.inkLight)
                    .padding(.vertical, 8)
            }
        }
        .padding(20)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppColors.creamBorder, lineWidth: 1))
    }

    private func cvDisplay(cv: Double) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("CV (CRITICAL VELOCITY)")
                .font(.system(size: 9).weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(AppColors.inkLight)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(formatPace(cv))
                    .font(.system(.title, design: .serif).weight(.heavy))
                    .foregroundStyle(AppColors.green)
                Text("/km").font(.caption).foregroundStyle(AppColors.inkLight)
            }
            Text("≈ allure seuil")
                .font(.system(size: 10))
                .foregroundStyle(AppColors.inkLight)
        }
    }

    private func zonesList(cv: Double) -> some View {
        VStack(spacing: 4) {
            ForEach(buildZones(cv: cv)) { z in
                HStack(spacing: 12) {
                    Rectangle().fill(z.color).frame(width: 4)
                    Text(z.label)
                        .font(.system(size: 12).weight(.bold))
                        .foregroundStyle(z.color)
                        .frame(minWidth: 130, alignment: .leading)
                    Text(z.range)
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.inkMid)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppColors.creamDark, in: RoundedRectangle(cornerRadius: 3))
            }
        }
    }

    // MARK: - Computation

    private func computeCV() -> Double? {
        var bestPace: Double?
        for activity in activities {
            guard activity.type == "running" else { continue }
            guard let dist = activity.distanceM, dist.count >= 1200 else { continue }
            guard let speed = activity.speedKmh, speed.count >= 1200 else { continue }

            // 1200-sample sliding window (= 20 min at 1 Hz).
            let W = 1200
            var lo = 0
            var hi = W
            var best = Double.infinity
            while hi < dist.count {
                let dM = dist[hi] - dist[lo]
                if dM > 0 {
                    let secPerKm = (Double(W) * 1000) / dM
                    if secPerKm < best { best = secPerKm }
                }
                lo += 1
                hi += 1
            }
            if best.isFinite, bestPace == nil || best < bestPace! {
                bestPace = best
            }
        }
        guard let bestPace else { return nil }
        // CV = best 20 min / 0.95 (slower in pace units).
        return bestPace / 0.95
    }

    private struct Zone: Identifiable {
        let id: String
        let label: String
        let range: String
        let color: Color
    }

    private func buildZones(cv: Double) -> [Zone] {
        let z1Slow = cv / 0.70
        let z2Slow = cv / 0.80
        let z3Slow = cv / 0.87
        let z4Slow = cv / 0.95
        return [
            Zone(id: "z1", label: "Z1 — RÉCUP",   range: "> \(formatPace(z1Slow))", color: AppColors.green),
            Zone(id: "z2", label: "Z2 — ENDURANCE", range: "\(formatPace(z2Slow)) – \(formatPace(z1Slow))", color: AppColors.blue),
            Zone(id: "z3", label: "Z3 — TEMPO",   range: "\(formatPace(z3Slow)) – \(formatPace(z2Slow))", color: AppColors.terra),
            Zone(id: "z4", label: "Z4 — SEUIL",   range: "\(formatPace(z4Slow)) – \(formatPace(z3Slow))", color: Color(hex: "E07030")),
            Zone(id: "z5", label: "Z5 — VO2 MAX", range: "< \(formatPace(z4Slow))", color: Color(hex: "CC3333")),
        ]
    }

    private func formatPace(_ secPerKm: Double) -> String {
        let total = Int(secPerKm.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
