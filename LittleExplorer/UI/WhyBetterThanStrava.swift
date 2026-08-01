import SwiftUI

/// Shared "why we beat Strava" pitch — used on the onboarding welcome screen,
/// in the in-app guide, and as a section of the "i" What's-New panel.
struct WhyBetterThanStrava: View {
    var showTitle: Bool = true

    private struct Pt { let icon: String; let text: String }
    private let pitch = "Garde Strava. Branche The Little Explorer par-dessus : l'analyse d'un abonnement Premium, un planificateur qui bat Komoot, et un coach. Gratuit, et sans capteur de puissance."
    private let points: [Pt] = [
        Pt(icon: "⚡", text: "Puissance, FTP et TSS estimés sans capteur, depuis ta vitesse et le dénivelé. Strava exige un vrai capteur de puissance."),
        Pt(icon: "🔁", text: "Le parcours auto trace de vraies boucles, jamais d'aller-retour, avec les cols autour, les points d'eau / ravito et le type de surface. Ni Strava ni Komoot ne font le ravito."),
        Pt(icon: "🧠", text: "Un vrai coach : plan d'entraînement et prochaine sortie prescrite (TSS cible, règle des 10 %). Niveau TrainingPeaks."),
        Pt(icon: "⌚", text: "Toutes tes sorties, pas seulement Strava : import direct depuis Apple Santé (Watch, Garmin, Whoop…), sans plafond d'athlètes."),
        Pt(icon: "🗺️", text: "Ta carte à toi : heatmap de tous tes tracés, bilan de l'année, comparateur de sorties."),
        Pt(icon: "🔧", text: "Suivi du matériel : usure des pièces (chaîne, pneus, plaquettes), pas juste le kilométrage brut."),
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
