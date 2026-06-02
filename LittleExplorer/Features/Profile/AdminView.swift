import SwiftUI

/// Hard-coded mirror of the web's `src/lib/admin.ts` allowlist. Anyone
/// not in this set won't see the Admin entry on Profile. The /api/admin
/// routes also enforce this server-side via the same allowlist.
enum AdminAllowlist {
    static let emails: Set<String> = [
        "florian.calabrese@gmail.com",
    ]

    static func contains(email: String?) -> Bool {
        guard let email else { return false }
        return emails.contains(email)
    }
}

/// Native mirror of the web's /admin (Users) dashboard. One card per TLE
/// user — avatar, name, short id, email, provider badges, Strava id,
/// activity count, join date, and a delete action. Restricted to the
/// allowlist; the server returns 403 for anyone else.
///
/// Keep in rough sync with src/app/admin/page.tsx on the web.
struct AdminView: View {
    @Environment(AppEnvironment.self) private var environment

    @State private var users: [APIClient.AdminUser] = []
    @State private var loadState: LoadState = .idle
    @State private var deletingId: String?
    @State private var pendingDelete: APIClient.AdminUser?
    @State private var deleteError: String?

    enum LoadState: Equatable {
        case idle, loading, loaded, failed(String)
    }

    var body: some View {
        Group {
            switch loadState {
            case .idle, .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let msg):
                ContentUnavailableView(
                    "Accès refusé",
                    systemImage: "lock.shield",
                    description: Text(msg),
                )
            case .loaded:
                loadedBody
            }
        }
        .background(AppColors.cream.ignoresSafeArea())
        .navigationTitle("Admin · Users")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { AdminMetricsView() } label: {
                    Image(systemName: "chart.bar.xaxis")
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .alert(
            "Supprimer ce compte ?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete,
        ) { user in
            Button("Supprimer", role: .destructive) { Task { await performDelete(user) } }
            Button("Annuler", role: .cancel) { pendingDelete = nil }
        } message: { user in
            Text("Suppression définitive de \(user.name ?? user.email ?? user.id) · \(user.activityCount ?? 0) activités.\n\nCompte, sessions, providers (Google/Strava), activités, matériel et itinéraires seront effacés. Irréversible.")
        }
        .alert("Échec de la suppression", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("OK", role: .cancel) { deleteError = nil }
        } message: {
            Text(deleteError ?? "")
        }
    }

    private var loadedBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(users.count) utilisateur\(users.count > 1 ? "s" : "")")
                    .font(.system(size: 12).weight(.semibold))
                    .foregroundStyle(AppColors.inkLight)
                    .padding(.bottom, 2)

                ForEach(users) { user in
                    UserCard(
                        user: user,
                        isDeleting: deletingId == user.id,
                        onDelete: { pendingDelete = user },
                    )
                }
            }
            .padding(16)
        }
    }

    private func load() async {
        loadState = .loading
        do {
            let fetched = try await environment.api.adminUsers()
            await MainActor.run {
                users = fetched
                loadState = .loaded
            }
        } catch {
            await MainActor.run { loadState = .failed(error.localizedDescription) }
        }
    }

    private func performDelete(_ user: APIClient.AdminUser) async {
        await MainActor.run { deletingId = user.id; pendingDelete = nil }
        do {
            _ = try await environment.api.adminDeleteUser(id: user.id)
            await MainActor.run {
                users.removeAll { $0.id == user.id }
                deletingId = nil
            }
        } catch {
            await MainActor.run {
                deletingId = nil
                deleteError = error.localizedDescription
            }
        }
    }
}

// MARK: - User card

private struct UserCard: View {
    let user: APIClient.AdminUser
    let isDeleting: Bool
    let onDelete: () -> Void

    private let google = Color(red: 0.26, green: 0.52, blue: 0.96)  // #4285F4
    private let strava = Color(red: 0.99, green: 0.30, blue: 0.01)  // #FC4C02

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Identity: avatar + name + short id
            HStack(spacing: 12) {
                avatar
                VStack(alignment: .leading, spacing: 3) {
                    Text(user.name ?? "—")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(AppColors.ink)
                        .lineLimit(1)
                    Text(String(user.id.prefix(13)) + "…")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(AppColors.inkLight)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            if let email = user.email {
                field("Email", email)
            }

            // Providers
            HStack(spacing: 6) {
                Text("PROVIDERS")
                    .font(.system(size: 8).weight(.bold)).tracking(0.6)
                    .foregroundStyle(AppColors.inkLight)
                let providers = user.providers ?? []
                if providers.contains("google") { badge("Google", google) }
                if providers.contains("strava") { badge("Strava", strava) }
                if providers.isEmpty {
                    Text("—").font(.system(size: 11)).foregroundStyle(AppColors.inkLight)
                }
            }

            // Stats row
            HStack(alignment: .top, spacing: 18) {
                stat("Strava ID", user.athleteId.map(String.init) ?? "—")
                stat("Sorties", "\(user.activityCount ?? 0)")
                stat("Inscrit", formatJoinDate(user.createdAt))
                Spacer(minLength: 0)
            }

            // Delete
            Button(role: .destructive, action: onDelete) {
                HStack(spacing: 6) {
                    if isDeleting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("✗ Supprimer")
                            .font(.system(size: 12).weight(.semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .foregroundStyle(Color(red: 0.67, green: 0, blue: 0))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color(red: 0.9, green: 0.71, blue: 0.71), lineWidth: 1),
                )
            }
            .buttonStyle(.plain)
            .disabled(isDeleting)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.creamBorder, lineWidth: 1))
    }

    @ViewBuilder
    private var avatar: some View {
        if let image = user.image, let url = URL(string: image) {
            AsyncImage(url: url) { phase in
                if let img = phase.image {
                    img.resizable().scaledToFill()
                } else {
                    initialCircle
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())
        } else {
            initialCircle
        }
    }

    private var initialCircle: some View {
        Circle()
            .fill(AppColors.terra)
            .frame(width: 40, height: 40)
            .overlay(
                Text((user.name ?? user.email ?? "?").prefix(1).uppercased())
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white),
            )
    }

    private func badge(_ label: String, _ color: Color) -> some View {
        Text(label.uppercased())
            .font(.system(size: 9).weight(.bold)).tracking(0.6)
            .foregroundStyle(.white)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(color, in: RoundedRectangle(cornerRadius: 3))
    }

    private func field(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 8).weight(.bold)).tracking(0.6)
                .foregroundStyle(AppColors.inkLight)
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(AppColors.inkMid)
                .lineLimit(1)
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 8).weight(.bold)).tracking(0.6)
                .foregroundStyle(AppColors.inkLight)
            Text(value)
                .font(.system(size: 13, design: .monospaced).weight(.semibold))
                .foregroundStyle(AppColors.ink)
        }
    }

    private func formatJoinDate(_ iso: String?) -> String {
        guard let iso else { return "—" }
        let datePart = String(iso.prefix(10))
        let inFmt = DateFormatter()
        inFmt.locale = Locale(identifier: "en_US_POSIX")
        inFmt.dateFormat = "yyyy-MM-dd"
        guard let d = inFmt.date(from: datePart) else { return datePart }
        let outFmt = DateFormatter()
        outFmt.locale = Locale(identifier: "fr_FR")
        outFmt.dateFormat = "dd MMM yyyy"
        return outFmt.string(from: d)
    }
}
