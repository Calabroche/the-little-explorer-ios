import SwiftUI

/// Shared "why we beat Strava" pitch — used on the onboarding welcome screen,
/// in the in-app guide, and as a section of the "i" What's-New panel.
struct WhyBetterThanStrava: View {
    var showTitle: Bool = true

    private struct Pt { let icon: String; let text: String }
    private let pitch = "Garde Strava gratuit, branche The Little Explorer : analyse niveau Premium + planificateur type Komoot — gratuit, et sans capteur de puissance."
    private let points: [Pt] = [
        Pt(icon: "⚡", text: "Puissance & FTP estimées sans capteur — Strava exige un vrai capteur de puissance."),
        Pt(icon: "💧", text: "Points de ravitaillement (eau / nourriture) le long du parcours — Strava et même Komoot ne le font pas."),
        Pt(icon: "🛤️", text: "Types de chemins & surfaces par itinéraire (route, piste, chemin, asphalte / non-pavé)."),
        Pt(icon: "🧠", text: "Plan d'entraînement + prochaine sortie prescrite (TSS cible, règle des 10 %) — niveau TrainingPeaks."),
        Pt(icon: "🔧", text: "Carnet d'entretien matériel (usure des pièces) — Strava ne suit que le kilométrage brut."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showTitle {
                Text("EN QUOI ON EST MIEUX QUE STRAVA ?")
                    .font(.system(size: 10).weight(.bold)).tracking(0.8)
                    .foregroundStyle(AppColors.terra)
            }
            Text(pitch)
                .font(.system(size: 13).weight(.medium))
                .foregroundStyle(AppColors.ink)
                .lineSpacing(2)
            ForEach(points.indices, id: \.self) { i in
                HStack(alignment: .top, spacing: 10) {
                    Text(points[i].icon).font(.system(size: 15))
                    Text(points[i].text)
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.inkMid)
                        .lineSpacing(2)
                }
            }
            Text("Et tout ça, gratuit.")
                .font(.system(size: 12).weight(.bold))
                .foregroundStyle(AppColors.green)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppColors.creamDark, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColors.creamBorder, lineWidth: 1))
    }
}
