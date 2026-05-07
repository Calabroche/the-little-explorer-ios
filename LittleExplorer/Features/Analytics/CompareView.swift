import Charts
import SwiftUI

/// Pick two activities, overlay their key metrics. Re-samples each
/// stream against a fixed-distance bucket grid so the X axis is shared.
/// Mirrors the web's ComparePage (HR / speed-or-pace / altitude / power).
struct CompareView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var idA: Int?
    @State private var idB: Int?

    // Power constants (mirror activities/route.ts default profile).
    private static let mass: Double = 74.18
    private static let g: Double = 9.81
    private static let crr: Double = 0.004
    private static let cda: Double = 0.3
    private static let rho: Double = 1.225

    var body: some View {
        let activities = environment.activityStore.activities.sortedRecentFirst
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headline()
                pickerCard(activities: activities)
                if let a = activities.first(where: { $0.id == idA }),
                   let b = activities.first(where: { $0.id == idB }) {
                    statsCard(a: a, b: b)
                    let overlay = buildOverlay(a: a, b: b)
                    let isRunning = a.type == "running" || b.type == "running"
                    OverlayChartCard(
                        title: "FRÉQUENCE CARDIAQUE (bpm)",
                        unit: "bpm",
                        data: overlay,
                        keyPathA: \.hrA,
                        keyPathB: \.hrB,
                        nameA: a.title,
                        nameB: b.title,
                        reversed: false,
                    )
                    if isRunning {
                        OverlayChartCard(
                            title: "ALLURE (min:ss / km)",
                            unit: "/km",
                            data: overlay,
                            keyPathA: \.paceA,
                            keyPathB: \.paceB,
                            nameA: a.title,
                            nameB: b.title,
                            reversed: true,
                            yFormatter: paceText,
                        )
                    } else {
                        OverlayChartCard(
                            title: "VITESSE (km/h)",
                            unit: "km/h",
                            data: overlay,
                            keyPathA: \.speedA,
                            keyPathB: \.speedB,
                            nameA: a.title,
                            nameB: b.title,
                            reversed: false,
                        )
                    }
                    OverlayChartCard(
                        title: "ALTITUDE (m)",
                        unit: "m",
                        data: overlay,
                        keyPathA: \.altA,
                        keyPathB: \.altB,
                        nameA: a.title,
                        nameB: b.title,
                        reversed: false,
                    )
                    if !isRunning {
                        OverlayChartCard(
                            title: "PUISSANCE ESTIMÉE (W)",
                            unit: "W",
                            data: overlay,
                            keyPathA: \.powerA,
                            keyPathB: \.powerB,
                            nameA: a.title,
                            nameB: b.title,
                            reversed: false,
                        )
                    }
                } else {
                    placeholder
                }
            }
            .padding(16)
        }
        .background(AppColors.cream)
        .navigationTitle("Comparer")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if idA == nil { idA = activities.first?.id }
            if idB == nil, activities.count > 1 { idB = activities[1].id }
        }
    }

    private func headline() -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Deux sorties.")
                .font(.system(.largeTitle, design: .serif).weight(.heavy))
                .foregroundStyle(AppColors.ink)
            Text("Côte à côte.")
                .font(.system(.title2, design: .serif).weight(.bold).italic())
                .foregroundStyle(AppColors.terra)
        }
    }

    private func pickerCard(activities: [RideRecord]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                pickerColumn(label: "Première (orange)", color: AppColors.terra, selection: $idA, activities: activities)
                pickerColumn(label: "Seconde (verte)", color: AppColors.green, selection: $idB, activities: activities)
            }
        }
        .padding(16)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppColors.creamBorder, lineWidth: 1))
    }

    private func pickerColumn(label: String, color: Color, selection: Binding<Int?>, activities: [RideRecord]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 9).weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(color)
            Picker("Sortie", selection: selection) {
                Text("—").tag(nil as Int?)
                ForEach(activities) { activity in
                    Text(rowLabel(activity)).tag(activity.id as Int?)
                }
            }
            .pickerStyle(.menu)
            .tint(color)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rowLabel(_ activity: RideRecord) -> String {
        let dist = activity.distance.map { String(format: "%.0f km", $0) } ?? "—"
        let title = activity.title.prefix(30)
        return "\(activity.date) · \(dist) · \(title)"
    }

    private var placeholder: some View {
        Text("Choisis deux sorties pour voir l'overlay.")
            .font(.caption)
            .foregroundStyle(AppColors.inkLight)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppColors.creamBorder, lineWidth: 1))
    }

    // MARK: - Stats card

    private func statsCard(a: RideRecord, b: RideRecord) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("STATISTIQUES")
                .font(.system(size: 9).weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(AppColors.inkLight)
                .padding(.bottom, 12)
            statRow(label: "Distance", va: a.distance, vb: b.distance, unit: "km")
            statRow(label: "Durée", va: a.duration, vb: b.duration)
            statRow(label: "Dénivelé", va: a.elevation, vb: b.elevation, unit: "m")
            statRow(label: a.type == "running" || b.type == "running" ? "Allure (s/km)" : "Vitesse moy.",
                    va: a.type == "running" || b.type == "running" ? Double(a.durationMin) * 60.0 / max(a.distance ?? 1, 0.001) : a.speed,
                    vb: a.type == "running" || b.type == "running" ? Double(b.durationMin) * 60.0 / max(b.distance ?? 1, 0.001) : b.speed,
                    unit: a.type == "running" || b.type == "running" ? "" : "km/h")
            if a.avgHr != nil || b.avgHr != nil {
                statRow(label: "FC moy.", va: a.avgHr, vb: b.avgHr, unit: "bpm")
            }
            if a.maxHr != nil || b.maxHr != nil {
                statRow(label: "FC max", va: a.maxHr, vb: b.maxHr, unit: "bpm")
            }
            if a.tss != nil || b.tss != nil {
                statRow(label: "TSS", va: a.tss, vb: b.tss)
            }
            if a.np != nil || b.np != nil {
                statRow(label: "NP", va: a.np, vb: b.np, unit: "W")
            }
            if a.calories != nil || b.calories != nil {
                statRow(label: "Calories", va: a.calories, vb: b.calories, unit: "kcal")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppColors.creamBorder, lineWidth: 1))
    }

    @ViewBuilder
    private func statRow<T>(label: String, va: T?, vb: T?, unit: String = "") -> some View {
        if va != nil || vb != nil {
            HStack {
                Text(format(va, unit: unit))
                    .font(.system(.subheadline, design: .serif).weight(.bold))
                    .foregroundStyle(AppColors.terra)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(label.uppercased())
                    .font(.system(size: 9).weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(AppColors.inkLight)
                    .frame(maxWidth: .infinity)
                Text(format(vb, unit: unit))
                    .font(.system(.subheadline, design: .serif).weight(.bold))
                    .foregroundStyle(AppColors.green)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.vertical, 6)
            Divider().background(AppColors.creamBorder)
        }
    }

    private func format<T>(_ value: T?, unit: String) -> String {
        guard let value else { return "—" }
        if let d = value as? Double {
            let n = abs(d) >= 10 ? "\(Int(d.rounded()))" : String(format: "%.1f", d)
            return unit.isEmpty ? n : "\(n) \(unit)"
        }
        if let i = value as? Int {
            return unit.isEmpty ? "\(i)" : "\(i) \(unit)"
        }
        if let s = value as? String {
            return unit.isEmpty ? s : "\(s) \(unit)"
        }
        return "\(value)"
    }

    // MARK: - Overlay sampling

    private struct DistPoint: Identifiable {
        let id: Double
        let km: Double
        let hrA: Double?
        let hrB: Double?
        let speedA: Double?
        let speedB: Double?
        let altA: Double?
        let altB: Double?
        let powerA: Double?
        let powerB: Double?
        let paceA: Double?
        let paceB: Double?
    }

    private func buildOverlay(a: RideRecord, b: RideRecord) -> [DistPoint] {
        let maxKm = max(a.distance ?? 0, b.distance ?? 0)
        guard maxKm > 0 else { return [] }
        let stepKm = max(0.1, ((maxKm / 200) * 100).rounded() / 100)
        let n = Int(ceil(maxKm / stepKm)) + 1

        let isRunning = a.type == "running" || b.type == "running"
        let sampledA = sample(a, n: n, stepKm: stepKm)
        let sampledB = sample(b, n: n, stepKm: stepKm)

        var out: [DistPoint] = []
        out.reserveCapacity(n)
        for i in 0..<n {
            let km = (Double(i) * stepKm * 100).rounded() / 100
            let stillA = km <= (a.distance ?? 0) + 0.01
            let stillB = km <= (b.distance ?? 0) + 0.01
            let hrA = stillA ? sampledA.hr[i] : nil
            let hrB = stillB ? sampledB.hr[i] : nil
            let speedA = stillA ? sampledA.speed[i] : nil
            let speedB = stillB ? sampledB.speed[i] : nil
            let altA = stillA ? sampledA.alt[i] : nil
            let altB = stillB ? sampledB.alt[i] : nil
            let powerA = !isRunning && stillA && speedA != nil ? Double(powerAt(speed: speedA!, gradient: sampledA.grad[i] / 100)) : nil
            let powerB = !isRunning && stillB && speedB != nil ? Double(powerAt(speed: speedB!, gradient: sampledB.grad[i] / 100)) : nil
            let paceA = isRunning && stillA && (speedA ?? 0) > 1 ? 3600 / speedA! : nil
            let paceB = isRunning && stillB && (speedB ?? 0) > 1 ? 3600 / speedB! : nil
            out.append(DistPoint(
                id: km, km: km,
                hrA: hrA, hrB: hrB,
                speedA: speedA, speedB: speedB,
                altA: altA, altB: altB,
                powerA: powerA, powerB: powerB,
                paceA: paceA, paceB: paceB,
            ))
        }
        return out
    }

    private struct Sampled {
        var hr: [Double?]
        var speed: [Double?]
        var alt: [Double?]
        var grad: [Double]
    }

    private func sample(_ activity: RideRecord, n: Int, stepKm: Double) -> Sampled {
        let dist = activity.distanceM ?? []
        let hr = sampleStream(activity.heartrate ?? [], dist: dist, n: n, stepKm: stepKm)
        let speed = sampleStream(activity.speedKmh ?? [], dist: dist, n: n, stepKm: stepKm)
        let alt = sampleStream(activity.altitude ?? [], dist: dist, n: n, stepKm: stepKm)
        let grad = computeGradient(altitude: activity.altitude ?? [], dist: dist, n: n, stepKm: stepKm)
        return Sampled(hr: hr, speed: speed, alt: alt, grad: grad)
    }

    private func sampleStream(_ stream: [Double], dist: [Double], n: Int, stepKm: Double) -> [Double?] {
        guard !stream.isEmpty, !dist.isEmpty else { return Array(repeating: nil, count: n) }
        var out: [Double?] = Array(repeating: nil, count: n)
        var idx = 0
        for i in 0..<n {
            let target = Double(i) * stepKm * 1000
            while idx < dist.count - 1, dist[idx] < target { idx += 1 }
            out[i] = idx < stream.count ? stream[idx] : nil
        }
        return out
    }

    private func computeGradient(altitude: [Double], dist: [Double], n: Int, stepKm: Double) -> [Double] {
        var out = Array(repeating: 0.0, count: n)
        guard altitude.count >= 5, dist.count >= 5 else { return out }
        var idx = 0
        for i in 0..<n {
            let target = Double(i) * stepKm * 1000
            while idx < dist.count - 1, dist[idx] < target { idx += 1 }
            let lo = max(0, idx - 30)
            let hi = min(altitude.count - 1, idx + 30)
            guard hi > lo else { continue }
            let dAlt = altitude[hi] - altitude[lo]
            let dDist = dist[hi] - dist[lo]
            if dDist > 5 {
                let g = ((dAlt / dDist) * 100 * 10).rounded() / 10
                out[i] = max(-25, min(25, g))
            }
        }
        return out
    }

    private func powerAt(speed kmh: Double, gradient: Double) -> Int {
        let v = kmh / 3.6
        let fr = Self.mass * Self.g * Self.crr
        let fg = Self.mass * Self.g * gradient
        let fa = 0.5 * Self.rho * Self.cda * v * v
        return max(0, Int(((fg + fr + fa) * v).rounded()))
    }

    private func paceText(_ secPerKm: Double) -> String {
        let total = Int(secPerKm.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - Overlay chart card

    private struct OverlayChartCard: View {
        let title: String
        let unit: String
        let data: [DistPoint]
        let keyPathA: KeyPath<DistPoint, Double?>
        let keyPathB: KeyPath<DistPoint, Double?>
        let nameA: String
        let nameB: String
        let reversed: Bool
        var yFormatter: ((Double) -> String)? = nil

        var body: some View {
            let hasData = data.contains { $0[keyPath: keyPathA] != nil || $0[keyPath: keyPathB] != nil }
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.system(size: 9).weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(AppColors.inkLight)
                if !hasData {
                    Text("Pas de données pour cette métrique.")
                        .font(.caption)
                        .foregroundStyle(AppColors.inkLight)
                } else {
                    Chart {
                        ForEach(data) { point in
                            if let value = point[keyPath: keyPathA] {
                                LineMark(
                                    x: .value("km", point.km),
                                    y: .value(unit, value),
                                    series: .value("Sortie", "A"),
                                )
                                .foregroundStyle(AppColors.terra)
                            }
                            if let value = point[keyPath: keyPathB] {
                                LineMark(
                                    x: .value("km", point.km),
                                    y: .value(unit, value),
                                    series: .value("Sortie", "B"),
                                )
                                .foregroundStyle(AppColors.green)
                            }
                        }
                    }
                    .frame(height: 200)
                    .chartYScale(domain: .automatic(reversed: reversed))
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisValueLabel {
                                if let formatter = yFormatter, let v = value.as(Double.self) {
                                    Text(formatter(v)).font(.system(size: 9))
                                } else if let v = value.as(Double.self) {
                                    Text(formatNumber(v)).font(.system(size: 9))
                                }
                            }
                            AxisGridLine().foregroundStyle(AppColors.creamBorder)
                        }
                    }
                    HStack(spacing: 14) {
                        legendDot(color: AppColors.terra, label: nameA)
                        legendDot(color: AppColors.green, label: nameB)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppColors.creamBorder, lineWidth: 1))
        }

        private func formatNumber(_ value: Double) -> String {
            abs(value) >= 100 ? "\(Int(value.rounded()))" : String(format: "%.1f", value)
        }

        private func legendDot(color: Color, label: String) -> some View {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(label.prefix(28))
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.inkMid)
                    .lineLimit(1)
            }
        }
    }
}
