import SwiftUI

/// One-time welcome screen shown the first time a signed-in user opens
/// the app. Greets them, sketches what the app does in a few bullets, and
/// links to the full GuideView — without burying them in it. "Commencer"
/// calls `onDone`, which flips `AppEnvironment.hasSeenWelcome` and
/// dismisses the cover.
///
/// iOS counterpart of the web's onboarding Step 0
/// (src/app/onboarding/page.tsx). Keep the greeting + highlights roughly
/// in sync between the two.
struct WelcomeView: View {
    @Environment(AppEnvironment.self) private var environment
    /// Invoked when the user taps "Commencer". The caller persists the
    /// "seen" flag and dismisses.
    let onDone: () -> Void

    private struct Highlight: Identifiable {
        let id = UUID()
        let emoji: String
        let text: String
    }

    private let highlights: [Highlight] = [
        Highlight(emoji: "◎", text: "Toutes tes sorties Strava synchronisées : récap, graphes annuels et cartes."),
        Highlight(emoji: "✦", text: "Un planificateur d'itinéraires + plans d'entraînement calibrés sur ta FTP."),
        Highlight(emoji: "⚡", text: "Suivi de ta FTP, de ta charge (TSS) et de ta forme dans le temps."),
        Highlight(emoji: "⚙", text: "Carnet d'entretien de ton matériel et suivi des pièces d'usure."),
        Highlight(emoji: "◎", text: "Apple Watch : enregistre tes rides en GPS standalone, guidage vocal inclus."),
    ]

    private var firstName: String? {
        environment.session.profile?.name?
            .split(separator: " ").first.map(String.init)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    Text("The Little Explorer rassemble tout ton suivi sportif au même endroit. Voici un aperçu de ce que tu peux faire :")
                        .font(.system(size: 14))
                        .foregroundStyle(AppColors.inkMid)
                        .lineSpacing(4)
                        .padding(.bottom, 4)

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(highlights) { h in
                            HStack(alignment: .top, spacing: 12) {
                                Text(h.emoji)
                                    .font(.system(size: 16))
                                    .foregroundStyle(AppColors.terra)
                                Text(h.text)
                                    .font(.system(size: 13))
                                    .foregroundStyle(AppColors.inkMid)
                                    .lineSpacing(3)
                            }
                        }
                    }

                    // Why we beat Strava — the pitch, right on the welcome screen.
                    WhyBetterThanStrava()

                    NavigationLink {
                        GuideView()
                    } label: {
                        Text("📖 Voir le guide complet")
                            .font(.system(size: 13).weight(.semibold))
                            .foregroundStyle(AppColors.terra)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 4)
                    }
                    .padding(.top, 4)

                    Button(action: onDone) {
                        Text("COMMENCER")
                            .font(.system(size: 14).weight(.bold))
                            .tracking(1)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(AppColors.terra, in: RoundedRectangle(cornerRadius: 4))
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .background(AppColors.cream.ignoresSafeArea())
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("§ BIENVENUE")
                .font(.system(size: 10).weight(.bold))
                .tracking(1.4)
                .foregroundStyle(AppColors.terra)
            Text(firstName.map { "Bienvenue \($0) 👋" } ?? "Bienvenue à bord 👋")
                .font(.system(size: 32, design: .serif).weight(.heavy))
                .foregroundStyle(AppColors.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
