import SwiftUI

/// Friend search, presented as a sheet from the Accueil loupe. Type a name →
/// TLE users matching it → follow inline or open their profile.
struct FriendSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [SocialUser] = []
    @State private var openedProfile: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(results) { u in
                        HStack(spacing: 10) {
                            Button { openedProfile = u.id } label: {
                                HStack(spacing: 10) {
                                    AvatarView(url: u.image, name: u.name, size: 38)
                                    Text(u.name ?? "Anonyme").font(.system(size: 15, weight: .semibold)).foregroundStyle(AppColors.ink)
                                }
                            }
                            Spacer()
                            SocialFollowButton(userId: u.id, following: u.isFollowing)
                        }
                        .padding(.vertical, 10).padding(.horizontal, 16)
                        Divider()
                    }
                    if !query.isEmpty && query.count >= 2 && results.isEmpty {
                        Text("Personne trouvé.").font(.system(size: 13)).foregroundStyle(AppColors.inkLight).padding(.top, 30)
                    }
                }
            }
            .background(AppColors.cream.ignoresSafeArea())
            .searchable(text: $query, prompt: "Cherche un ami sur The Little Explorer")
            .navigationTitle("Rechercher")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
            .navigationDestination(item: $openedProfile) { PublicProfileView(userId: $0) }
            .task(id: query) { await runSearch() }
        }
    }

    private func runSearch() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { results = []; return }
        try? await Task.sleep(nanoseconds: 250_000_000)
        if Task.isCancelled { return }
        do { results = try await APIClient.shared.searchSocialUsers(q) }
        catch { results = [] }
    }
}

/// Followers / following list, presented as a sheet.
struct ConnectionsSheet: View {
    let userId: String
    let type: String            // "followers" | "following"
    @Environment(\.dismiss) private var dismiss
    @State private var users: [SocialUser] = []
    @State private var loading = true
    @State private var openedProfile: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    if loading { ProgressView().padding(.top, 30) }
                    else if users.isEmpty {
                        Text("Personne pour l'instant.").font(.system(size: 13)).foregroundStyle(AppColors.inkLight).padding(.top, 30)
                    }
                    ForEach(users) { u in
                        HStack(spacing: 10) {
                            Button { openedProfile = u.id } label: {
                                HStack(spacing: 10) {
                                    AvatarView(url: u.image, name: u.name, size: 38)
                                    Text(u.name ?? "Anonyme").font(.system(size: 15, weight: .semibold)).foregroundStyle(AppColors.ink)
                                }
                            }
                            Spacer()
                            SocialFollowButton(userId: u.id, following: u.isFollowing)
                        }
                        .padding(.vertical, 10).padding(.horizontal, 16)
                        Divider()
                    }
                }
            }
            .background(AppColors.cream.ignoresSafeArea())
            .navigationTitle(type == "followers" ? "Abonnés" : "Abonnements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
            .navigationDestination(item: $openedProfile) { PublicProfileView(userId: $0) }
            .task { await load() }
        }
    }

    private func load() async {
        loading = true
        do { users = try await APIClient.shared.connections(userId: userId, type: type) }
        catch { users = [] }
        loading = false
    }
}

/// Strava-style profile header: avatar, name, bio, and the
/// Abonnements / Abonnés / Activités counts. Sits on top of the Profil tab.
struct ProfileHeaderView: View {
    let profile: SocialProfile?
    let activityCount: Int
    var onOpenConnections: (String) -> Void = { _ in }
    var onSettings: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                AvatarView(url: profile?.image, name: profile?.name, size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile?.name ?? "Mon profil")
                        .font(.system(size: 22, weight: .heavy, design: .serif))
                        .foregroundStyle(AppColors.ink)
                    if let bio = profile?.bio, !bio.isEmpty {
                        Text(bio).font(.system(size: 13)).foregroundStyle(AppColors.inkMid).lineLimit(3)
                    }
                }
                Spacer()
                Button(action: onSettings) {
                    Image(systemName: "gearshape").font(.system(size: 18)).foregroundStyle(AppColors.inkMid)
                }
            }
            HStack(spacing: 0) {
                stat("Abonnements", profile?.following ?? 0) { onOpenConnections("following") }
                stat("Abonnés", profile?.followers ?? 0) { onOpenConnections("followers") }
                stat("Activités", activityCount) {}
            }
        }
        .padding(16)
        .background(AppColors.cream)
    }

    private func stat(_ label: String, _ value: Int, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text("\(value)").font(.system(size: 20, weight: .heavy)).foregroundStyle(AppColors.ink)
                Text(label).font(.system(size: 11)).foregroundStyle(AppColors.inkMid)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
