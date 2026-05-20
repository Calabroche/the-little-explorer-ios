import SwiftUI

struct ProfileView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        @Bindable var env = environment
        NavigationStack {
            Form {
                // Authenticated user info comes from /api/me after sign-in.
                // The legacy "Utilisateur" picker (Florian/Helena) is gone —
                // multi-user means each session sees only their own data.
                Section("Compte") {
                    if let p = env.session.profile {
                        LabeledContent("Nom", value: p.name ?? "—")
                        LabeledContent("Email", value: p.email ?? "—")
                        if let athleteId = p.athleteId {
                            LabeledContent("Strava athlete", value: String(athleteId))
                        }
                    } else {
                        Text("Chargement du profil…")
                            .foregroundStyle(.secondary)
                    }
                    Button(role: .destructive) {
                        env.session.clear()
                    } label: {
                        Text("Se déconnecter")
                    }
                }

                Section("Sport") {
                    Picker("Sport principal", selection: $env.selectedSport) {
                        ForEach(Sport.allCases) { sport in
                            Label(sport.displayName, systemImage: sport.symbol).tag(sport)
                        }
                    }
                }

                Section("Apparence") {
                    Picker("Thème", selection: themeBinding(env: env)) {
                        Text("Système").tag(ThemeOption.system)
                        Text("Clair").tag(ThemeOption.light)
                        Text("Sombre").tag(ThemeOption.dark)
                    }
                    .pickerStyle(.segmented)
                }

                Section("Backend") {
                    LabeledContent("API", value: "the-little-explorer-app.vercel.app")
                }

                Section("Apple Watch") {
                    LabeledContent("Appairée", value: env.watch.isPaired ? "Oui" : "Non")
                    LabeledContent("Joignable", value: env.watch.isReachable ? "Oui" : "Non")
                }

                Section("À propos") {
                    LabeledContent("Version", value: appVersion)
                }
            }
            .navigationTitle("Profil")
        }
    }

    private enum ThemeOption: String, CaseIterable, Hashable {
        case system, light, dark
    }

    private func themeBinding(env: AppEnvironment) -> Binding<ThemeOption> {
        Binding(
            get: {
                switch env.darkModeOverride {
                case .none:    return .system
                case .some(.light): return .light
                case .some(.dark):  return .dark
                @unknown default: return .system
                }
            },
            set: { newValue in
                switch newValue {
                case .system: env.darkModeOverride = nil
                case .light:  env.darkModeOverride = .light
                case .dark:   env.darkModeOverride = .dark
                }
            },
        )
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(v) (\(b))"
    }
}
