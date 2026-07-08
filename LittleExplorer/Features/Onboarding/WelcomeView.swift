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

    /// Drives the Apple Health priming card: whether we've fired the system
    /// read-permission sheet yet, and a spinner while it's in flight.
    @State private var hkRequested = false
    @State private var hkAuthorizing = false

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

    // One-time per-brand setup shown in the priming card. Each brand's own app
    // must be told to write into Apple Health before its workouts reach us.
    private struct BrandStep { let brand: String; let step: String }
    private let brandSteps: [BrandStep] = [
        BrandStep(brand: "Apple Watch", step: "Rien à faire, tes séances arrivent toutes seules."),
        BrandStep(brand: "Garmin",      step: "Garmin Connect → Plus → Réglages → Apple Santé → activer."),
        BrandStep(brand: "Coros",       step: "COROS → Profil → Réglages → Apple Santé → connecter."),
        BrandStep(brand: "Whoop",       step: "Whoop → Réglages → Intégrations → Apple Santé → activer."),
        BrandStep(brand: "Autres",      step: "Wahoo / Polar / Suunto : app de la marque → Réglages → Apple Santé."),
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

                    // Explicit Apple Health priming, right in the onboarding.
                    // Apple recommends explaining WHY before the system sheet
                    // fires — otherwise users reflexively dismiss it and their
                    // workouts never sync. This is our Strava-independent path.
                    if HealthKitService.isAvailable {
                        healthPrimingCard
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

                    Button {
                        Task {
                            // Safety net: if the user tapped straight through
                            // without using the card, still fire the permission
                            // sheet now (they've read the explanation above it).
                            if HealthKitService.isAvailable && !hkRequested {
                                await environment.primeHealthKitIngestion()
                            }
                            onDone()
                        }
                    } label: {
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

    /// Priming card: explains what we read from Apple Health and why, then a
    /// single button that fires the system permission sheet and starts the
    /// full-history import. Once tapped it shows a granted/asked confirmation.
    private var healthPrimingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("◎ IMPORTE TOUT TON HISTORIQUE")
                .font(.system(size: 10).weight(.bold))
                .tracking(1.4)
                .foregroundStyle(AppColors.terra)

            Text("Autorise-nous à lire tes entraînements depuis Apple Santé. On importe tout ton historique en une fois (Apple Watch, et toute app qui écrit dans Santé : Garmin, Coros, Whoop…), puis chaque nouvelle sortie arrive automatiquement. Aucune dépendance à Strava.")
                .font(.system(size: 13))
                .foregroundStyle(AppColors.inkMid)
                .lineSpacing(3)

            // The one-time per-brand setup: a workout only reaches us once the
            // brand's own app is told to write into Apple Health. Apple Watch
            // needs nothing; every other brand is a single toggle to flip.
            VStack(alignment: .leading, spacing: 6) {
                Text("À FAIRE UNE FOIS, SELON TA MARQUE")
                    .font(.system(size: 10).weight(.bold))
                    .tracking(1)
                    .foregroundStyle(AppColors.inkLight)
                ForEach(brandSteps, id: \.brand) { s in
                    HStack(alignment: .top, spacing: 8) {
                        Text(s.brand)
                            .font(.system(size: 11).weight(.bold))
                            .foregroundStyle(AppColors.terra)
                            .frame(width: 74, alignment: .leading)
                        Text(s.step)
                            .font(.system(size: 11))
                            .foregroundStyle(AppColors.inkMid)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.top, 2)

            Button {
                Task {
                    hkAuthorizing = true
                    await environment.primeHealthKitIngestion()
                    hkAuthorizing = false
                    hkRequested = true
                }
            } label: {
                HStack(spacing: 8) {
                    if hkAuthorizing {
                        ProgressView().scaleEffect(0.8).tint(.white)
                    } else if hkRequested {
                        Image(systemName: "checkmark.circle.fill")
                    }
                    Text(hkRequested ? "Accès demandé" : "Autoriser l'accès à mes entraînements")
                        .font(.system(size: 13).weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(hkRequested ? AppColors.green : AppColors.terra,
                            in: RoundedRectangle(cornerRadius: 4))
            }
            .disabled(hkAuthorizing || hkRequested)

            if hkRequested {
                Text("Si tu n'as pas vu la fenêtre d'autorisation, tu pourras la réactiver dans Réglages → Santé → Petit Explorer.")
                    .font(.caption)
                    .foregroundStyle(AppColors.inkMid)
                    .lineSpacing(2)
            }
        }
        .padding(14)
        .background(AppColors.cream)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppColors.terra.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
