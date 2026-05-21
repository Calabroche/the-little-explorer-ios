import SwiftUI

/// Mirror of the web's ProfileSection at the bottom of the sidebar:
/// avatar + name/email card, RE-SYNCER STRAVA, PARAMÈTRES, ADMIN
/// (conditional on allowlist), SE DÉCONNECTER. The legacy
/// Florian/Helena multi-user picker is gone — multi-user auth means
/// each session sees only their own data.
struct ProfileView: View {
    @Environment(AppEnvironment.self) private var environment

    @State private var resyncState: ResyncState = .idle
    enum ResyncState: Equatable {
        case idle, busy, done, failed(String)
    }

    var body: some View {
        @Bindable var env = environment
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text("Profil")
                        .font(.system(.largeTitle, design: .serif).weight(.heavy))
                        .foregroundStyle(AppColors.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)

                    accountCard
                    appCard(env: env)
                    aboutCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .background(AppColors.cream)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: ProfileRoute.self) { route in
                switch route {
                case .settings: SettingsView()
                case .admin:    AdminView()
                }
            }
        }
    }

    // MARK: - Account card

    @ViewBuilder
    private var accountCard: some View {
        let profile = environment.session.profile
        VStack(alignment: .leading, spacing: 14) {
            // Identity row
            HStack(spacing: 14) {
                avatar(profile: profile)
                    .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(displayName(profile: profile))
                        .font(.system(.title3, design: .serif).weight(.bold))
                        .foregroundStyle(AppColors.ink)
                        .lineLimit(1)
                    if let email = profile?.email, email != profile?.name {
                        Text(email)
                            .font(.system(size: 12))
                            .foregroundStyle(AppColors.inkLight)
                            .lineLimit(1)
                    }
                    if let athleteId = profile?.athleteId {
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.fill").font(.system(size: 9))
                            Text("Strava · \(athleteId)").font(.system(size: 10).weight(.semibold))
                        }
                        .foregroundStyle(AppColors.terra)
                        .padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)
            }

            Divider().overlay(AppColors.creamBorder)

            // Action stack
            VStack(spacing: 8) {
                resyncButton

                NavigationLink(value: ProfileRoute.settings) {
                    actionRow(symbol: "gearshape", text: "Paramètres", chevron: true)
                }
                .buttonStyle(.plain)

                if AdminAllowlist.contains(email: profile?.email) {
                    NavigationLink(value: ProfileRoute.admin) {
                        actionRow(symbol: "shield.lefthalf.filled", text: "Admin", chevron: true, dashed: true)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    environment.session.clear()
                } label: {
                    HStack {
                        Spacer()
                        Image(systemName: "rectangle.portrait.and.arrow.right").font(.system(size: 12))
                        Text("Se déconnecter").font(.system(size: 13).weight(.semibold))
                        Spacer()
                    }
                    .padding(.vertical, 11)
                    .foregroundStyle(AppColors.terra)
                    .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.terra.opacity(0.35), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.creamBorder, lineWidth: 1))
    }

    @ViewBuilder
    private var resyncButton: some View {
        Button {
            Task { await resync() }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(AppColors.terraLight).frame(width: 28, height: 28)
                    if resyncState == .busy {
                        ProgressView().scaleEffect(0.6).tint(AppColors.terra)
                    } else {
                        Image(systemName: resyncState.symbol)
                            .font(.system(size: 12).weight(.semibold))
                            .foregroundStyle(AppColors.terra)
                    }
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(resyncState.title)
                        .font(.system(size: 13).weight(.semibold))
                        .foregroundStyle(resyncState.titleColor)
                    Text(resyncState.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.inkLight)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(AppColors.creamDark, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(resyncState == .busy)
    }

    private func actionRow(symbol: String, text: String, chevron: Bool, dashed: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13).weight(.semibold))
                .foregroundStyle(AppColors.inkMid)
                .frame(width: 28, height: 28)
                .background(AppColors.creamDark, in: Circle())
            Text(text)
                .font(.system(size: 13).weight(.semibold))
                .foregroundStyle(AppColors.ink)
            Spacer()
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11).weight(.semibold))
                    .foregroundStyle(AppColors.inkLight)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(AppColors.creamDark.opacity(dashed ? 0.4 : 1)),
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(AppColors.creamBorder, style: StrokeStyle(lineWidth: 1, dash: dashed ? [3, 3] : [])),
        )
    }

    private func avatar(profile: MeProfile?) -> some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [AppColors.terra, AppColors.terraLight],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing,
                ),
            )
            .overlay(
                Text(initials(profile: profile))
                    .font(.system(.title3, design: .serif).weight(.heavy))
                    .foregroundStyle(.white),
            )
            .overlay(Circle().stroke(.white.opacity(0.4), lineWidth: 1))
    }

    // MARK: - App iOS card (Sport / Theme / Watch)

    @ViewBuilder
    private func appCard(env: AppEnvironment) -> some View {
        @Bindable var env = env
        VStack(spacing: 0) {
            cardHeader("App iOS", subtitle: "Réglages spécifiques au mobile")

            // Sport principal
            cardRow(label: "Sport principal") {
                Menu {
                    ForEach(Sport.allCases) { sport in
                        Button {
                            env.selectedSport = sport
                        } label: {
                            if sport == env.selectedSport {
                                Label(sport.displayName, systemImage: "checkmark")
                            } else {
                                Text(sport.displayName)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: env.selectedSport.symbol).font(.system(size: 12))
                        Text(env.selectedSport.displayName).font(.system(size: 13).weight(.semibold))
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 9))
                    }
                    .foregroundStyle(AppColors.terra)
                }
            }

            cardDivider()

            // Apparence
            VStack(alignment: .leading, spacing: 8) {
                Text("Apparence").font(.system(size: 13)).foregroundStyle(AppColors.ink)
                ThemeSegmentedControl(selection: themeBinding(env: env))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            cardDivider()

            // Apple Watch
            cardRow(label: "Apple Watch") {
                HStack(spacing: 6) {
                    statusDot(ok: env.watch.isPaired)
                    Text(env.watch.isPaired ? "Appairée" : "Non appairée")
                        .font(.system(size: 12)).foregroundStyle(AppColors.inkMid)
                }
            }

            if env.watch.isPaired {
                cardDivider()
                cardRow(label: "Joignable") {
                    HStack(spacing: 6) {
                        statusDot(ok: env.watch.isReachable)
                        Text(env.watch.isReachable ? "Oui" : "Non")
                            .font(.system(size: 12)).foregroundStyle(AppColors.inkMid)
                    }
                }
            }
        }
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.creamBorder, lineWidth: 1))
    }

    // MARK: - À propos

    @ViewBuilder
    private var aboutCard: some View {
        VStack(spacing: 0) {
            cardHeader("À propos", subtitle: nil)
            cardRow(label: "Backend") {
                Text("the-little-explorer-app.vercel.app")
                    .font(.system(size: 11)).foregroundStyle(AppColors.inkLight)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            cardDivider()
            cardRow(label: "Version") {
                Text(appVersion).font(.system(size: 12)).foregroundStyle(AppColors.inkMid)
            }
        }
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.creamBorder, lineWidth: 1))
    }

    // MARK: - Reusable card primitives

    private func cardHeader(_ title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 10).weight(.bold))
                .tracking(1.5)
                .foregroundStyle(AppColors.terra)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.inkLight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private func cardRow<Trailing: View>(label: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            Text(label).font(.system(size: 13)).foregroundStyle(AppColors.ink)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func cardDivider() -> some View {
        Rectangle().fill(AppColors.creamBorder).frame(height: 1).padding(.leading, 14)
    }

    private func statusDot(ok: Bool) -> some View {
        Circle()
            .fill(ok ? AppColors.green : AppColors.inkLight.opacity(0.4))
            .frame(width: 7, height: 7)
    }

    // MARK: - Helpers

    private func displayName(profile: MeProfile?) -> String {
        if let n = profile?.name, !n.isEmpty { return n }
        if let e = profile?.email, !e.isEmpty { return e }
        return "Compte"
    }

    private func initials(profile: MeProfile?) -> String {
        let source = profile?.name ?? profile?.email ?? "?"
        let parts = source.split(whereSeparator: { $0 == " " || $0 == "@" || $0 == "." })
        let letters = parts.prefix(2).compactMap { $0.first.map { String($0) } }
        return letters.joined().uppercased()
    }

    private func resync() async {
        resyncState = .busy
        do {
            _ = try await environment.api.syncStrava()
            await environment.activityStore.load(user: environment.currentUser, force: true)
            await MainActor.run { resyncState = .done }
        } catch {
            await MainActor.run { resyncState = .failed(error.localizedDescription) }
        }
    }

    fileprivate enum ThemeOption: String, CaseIterable, Hashable { case system, light, dark }

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

enum ProfileRoute: Hashable {
    case settings, admin
}

// MARK: - Theme segmented control

private struct ThemeSegmentedControl: View {
    @Binding var selection: ProfileView.ThemeOption

    private static let options: [(ProfileView.ThemeOption, String, String)] = [
        (.system, "Système", "circle.lefthalf.filled"),
        (.light,  "Clair",   "sun.max"),
        (.dark,   "Sombre",  "moon"),
    ]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Self.options, id: \.0) { option, label, symbol in
                let isActive = selection == option
                Button {
                    selection = option
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: symbol).font(.system(size: 11))
                        Text(label).font(.system(size: 12).weight(isActive ? .bold : .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isActive ? AppColors.terra : Color.clear),
                    )
                    .foregroundStyle(isActive ? Color.white : AppColors.inkMid)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(AppColors.creamDark, in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Resync state styling

private extension ProfileView.ResyncState {
    var title: String {
        switch self {
        case .idle:    return "Re-syncer Strava"
        case .busy:    return "Synchronisation…"
        case .done:    return "Sync terminée"
        case .failed:  return "Échec — Réessayer"
        }
    }
    var subtitle: String {
        switch self {
        case .idle:    return "Forcer une mise à jour Strava"
        case .busy:    return "Téléchargement en cours"
        case .done:    return "Tes activités sont à jour"
        case .failed(let msg): return msg
        }
    }
    var symbol: String {
        switch self {
        case .idle:    return "arrow.triangle.2.circlepath"
        case .busy:    return "arrow.triangle.2.circlepath"
        case .done:    return "checkmark"
        case .failed:  return "exclamationmark.triangle"
        }
    }
    var titleColor: Color {
        switch self {
        case .failed: return .red
        case .done:   return AppColors.green
        default:      return AppColors.ink
        }
    }
}
