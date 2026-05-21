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

/// Mirror of the web's /admin dashboard. Lists every TLE user with their
/// providers, activity count, and join date. Restricted to the allowlist;
/// server returns 403 for anyone else.
struct AdminView: View {
    @Environment(AppEnvironment.self) private var environment

    @State private var users: [APIClient.AdminUser] = []
    @State private var loadState: LoadState = .idle

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
                List(users) { user in
                    row(user: user)
                }
            }
        }
        .navigationTitle("Admin")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func row(user: APIClient.AdminUser) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(user.name ?? user.email ?? user.id)
                .font(.system(.body, design: .serif).weight(.semibold))
                .foregroundStyle(AppColors.ink)
            if let email = user.email, email != user.name {
                Text(email)
                    .font(.caption)
                    .foregroundStyle(AppColors.inkLight)
            }
            HStack(spacing: 8) {
                if let providers = user.providers, !providers.isEmpty {
                    ForEach(providers, id: \.self) { p in
                        Text(p.uppercased())
                            .font(.system(size: 9).weight(.bold))
                            .tracking(0.8)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppColors.terraLight, in: Capsule())
                            .foregroundStyle(AppColors.terra)
                    }
                }
                if let count = user.activityCount {
                    Text("\(count) sorties")
                        .font(.caption2)
                        .foregroundStyle(AppColors.inkMid)
                }
                Spacer()
            }
        }
        .padding(.vertical, 4)
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
            await MainActor.run {
                loadState = .failed(error.localizedDescription)
            }
        }
    }
}
