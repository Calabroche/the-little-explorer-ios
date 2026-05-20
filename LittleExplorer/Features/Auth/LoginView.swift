import SwiftUI

/// Login screen — visual match for the web app's /login page.
///
/// Layout:
///   - Top half: forest photo background with the "The Little Explorer"
///     title in white at the bottom-left (same hero treatment as web).
///   - Bottom half: cream-background card with the two OAuth buttons.
///
/// The forest photo is fetched from the web app's public/ directory
/// rather than bundled in the app — keeps the iOS build small and
/// guarantees the image stays in sync if Florian swaps it later on
/// the web.
struct LoginView: View {
    @Environment(SessionStore.self) private var session
    @State private var auth = AuthService()
    @State private var busy: String? = nil
    @State private var error: String? = nil

    private let heroURL = URL(string: "https://the-little-explorer-app.vercel.app/login-forest.avif")!

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                AppColors.cream.ignoresSafeArea()

                VStack(spacing: 0) {
                    hero
                        .frame(height: geo.size.height * 0.45)

                    formCard
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
        }
    }

    // MARK: - Hero (forest photo + title)

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: heroURL) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                default:
                    // While loading: a deep-green placeholder so the
                    // layout doesn't jump.
                    AppColors.green.opacity(0.25)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            // Dark gradient overlay so the white title stays readable.
            LinearGradient(
                colors: [Color.black.opacity(0.20), Color.black.opacity(0.55)],
                startPoint: .top, endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("The Little")
                    .font(.custom("Playfair Display", size: 40))
                    .fontWeight(.heavy)
                Text("Explorer")
                    .font(.custom("Playfair Display", size: 40))
                    .fontWeight(.heavy)
                    .italic()
                    .foregroundStyle(Color(red: 1.0, green: 0.83, blue: 0.64)) // #FFD3A3
                Text("Suis tes sorties vélo, course, rando — calendrier d'activités, objectifs et tout l'historique Strava au même endroit.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .padding(.top, 8)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
            .foregroundStyle(.white)
            .shadow(color: Color.black.opacity(0.4), radius: 6, x: 0, y: 1)
        }
    }

    // MARK: - Form card

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("§ BIENVENUE")
                .font(.system(size: 11, weight: .heavy))
                .tracking(1.5)
                .foregroundStyle(AppColors.terra)
                .padding(.top, 24)

            Text("Connecte-toi.")
                .font(.custom("Playfair Display", size: 28))
                .fontWeight(.heavy)
                .foregroundStyle(AppColors.ink)

            Text("Retrouve tes sorties Strava, ton calendrier et tes objectifs.")
                .font(.system(size: 13))
                .foregroundStyle(AppColors.inkLight)
                .fixedSize(horizontal: false, vertical: true)

            Text("Première fois ici ? Clique l'un des boutons ci-dessous — ton compte sera créé automatiquement.")
                .font(.system(size: 11))
                .italic()
                .foregroundStyle(AppColors.inkLight)
                .fixedSize(horizontal: false, vertical: true)

            if let error {
                Text("Erreur de connexion : \(error)")
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.red.opacity(0.3)))
            }

            providerButton(
                title: busy == "google" ? "Connexion…" : "Continuer avec Google",
                tint: AppColors.cream,
                fg: AppColors.ink,
                border: AppColors.creamBorder
            ) {
                Task { await signIn(provider: "google") }
            }
            .disabled(busy != nil)

            providerButton(
                title: busy == "strava" ? "Connexion…" : "Continuer avec Strava",
                tint: Color(red: 0.99, green: 0.30, blue: 0.01), // #FC4C02
                fg: .white,
                border: Color(red: 0.99, green: 0.30, blue: 0.01)
            ) {
                Task { await signIn(provider: "strava") }
            }
            .disabled(busy != nil)

            Text("En continuant, tu acceptes que nous récupérions tes activités Strava via l'API officielle. Aucun mot de passe stocké.")
                .font(.system(size: 11))
                .foregroundStyle(AppColors.inkLight)
                .padding(.top, 8)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .background(AppColors.cream)
    }

    private func providerButton(title: String, tint: Color, fg: Color, border: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Spacer()
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
            }
            .padding(.vertical, 14)
            .background(tint)
            .foregroundStyle(fg)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(border))
        }
    }

    // MARK: - Sign-in trigger

    private func signIn(provider: String) async {
        busy = provider
        error = nil
        do {
            let token = try await auth.authenticate(provider: provider)
            session.setToken(token)
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
        busy = nil
    }
}

#Preview {
    LoginView()
        .environment(SessionStore())
}
