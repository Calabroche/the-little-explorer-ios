import SwiftUI

/// Free race-time predictor + training paces for runners (the kind of thing
/// Strava paywalls). Riegel model T2 = T1·(D2/D1)^1.06 from the runner's best
/// recent effort, with Daniels-style training paces derived from it.
struct RaceProjectorView: View {
    let activities: [RideRecord]

    private let riegel = 1.06
    private struct Target { let km: Double; let label: String }
    private let targets: [Target] = [
        .init(km: 5, label: "5 km"),
        .init(km: 10, label: "10 km"),
        .init(km: 21.0975, label: "Semi"),
        .init(km: 42.195, label: "Marathon"),
    ]

    private var ref: (d: Double, t: Double)? {
        var best: (d: Double, t: Double, equiv: Double)?
        for a in activities where a.type == "running" {
            guard let d = a.distance, d >= 3 else { continue }
            let t: Double = a.paceSPerKm != nil ? Double(a.paceSPerKm!) * d : Double(a.durationMin) * 60
            guard t >= 60 else { continue }
            let equiv = t * pow(10 / d, riegel)
            if best == nil || equiv < best!.equiv { best = (d, t, equiv) }
        }
        if let b = best { return (b.d, b.t) }
        return nil
    }

    var body: some View {
        if let r = ref {
            content(r).padding(.horizontal, 16)
        }
    }

    private func predict(_ km: Double, _ r: (d: Double, t: Double)) -> Double {
        r.t * pow(km / r.d, riegel)
    }

    private func content(_ r: (d: Double, t: Double)) -> some View {
        let marathonPace = predict(42.195, r) / 42.195
        let tenKPace = predict(10, r) / 10
        let fiveKPace = predict(5, r) / 5
        let paces: [(name: String, sec: Double, color: Color)] = [
            ("Endurance facile", marathonPace + 50, AppColors.green),
            ("Allure marathon",  marathonPace,      AppColors.blue),
            ("Seuil (tempo)",    tenKPace,          AppColors.terra),
            ("VO2 / Intervalle", fiveKPace,         Color(red: 0.75, green: 0.22, blue: 0.17)),
        ]
        return VStack(alignment: .leading, spacing: 12) {
            Text("CHRONOS PRÉDITS")
                .font(.system(size: 10).weight(.bold)).tracking(0.8)
                .foregroundStyle(AppColors.terra)
            HStack(spacing: 8) {
                ForEach(targets, id: \.label) { tg in
                    let sec = predict(tg.km, r)
                    VStack(spacing: 3) {
                        Text(tg.label).font(.system(size: 9)).foregroundStyle(AppColors.inkLight)
                        Text(fmtTime(sec)).font(.system(size: 15, design: .serif).weight(.heavy)).foregroundStyle(AppColors.ink)
                        Text("\(fmtPace(sec / tg.km))/km").font(.system(size: 9, design: .monospaced)).foregroundStyle(AppColors.inkMid)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(AppColors.creamDark, in: RoundedRectangle(cornerRadius: 6))
                }
            }
            Text("ALLURES D'ENTRAÎNEMENT")
                .font(.system(size: 10).weight(.bold)).tracking(0.8)
                .foregroundStyle(AppColors.inkLight).padding(.top, 4)
            ForEach(paces.indices, id: \.self) { i in
                HStack(spacing: 10) {
                    Circle().fill(paces[i].color).frame(width: 9, height: 9)
                    Text(paces[i].name).font(.system(size: 13)).foregroundStyle(AppColors.ink)
                    Spacer()
                    Text("\(fmtPace(paces[i].sec))/km")
                        .font(.system(size: 13, design: .monospaced).weight(.semibold))
                        .foregroundStyle(AppColors.ink)
                }
                .padding(.vertical, 3)
            }
            Text("Estimations via le modèle de Riegel — Strava fait payer ça. Cours à ces allures pour viser les chronos.")
                .font(.system(size: 10)).foregroundStyle(AppColors.inkLight).lineSpacing(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.creamBorder, lineWidth: 1))
    }

    private func fmtTime(_ sec: Double) -> String {
        let s = Int(sec.rounded())
        let h = s / 3600, m = (s % 3600) / 60, ss = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, ss) : String(format: "%d:%02d", m, ss)
    }
    private func fmtPace(_ secPerKm: Double) -> String {
        let s = Int(secPerKm.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
