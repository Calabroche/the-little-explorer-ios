import SwiftUI

/// Follow / unfollow button with optimistic state. Reused by search rows and
/// the public profile.
struct SocialFollowButton: View {
    let userId: String
    @State private var following: Bool
    @State private var busy = false

    init(userId: String, following: Bool) {
        self.userId = userId
        _following = State(initialValue: following)
    }

    var body: some View {
        Button { toggle() } label: {
            Text(following ? "ABONNÉ" : "S'ABONNER")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(following ? AppColors.inkMid : .white)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(following ? Color.clear : AppColors.terra)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(following ? AppColors.creamBorder : AppColors.terra, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .disabled(busy)
    }

    private func toggle() {
        busy = true
        let next = !following
        following = next
        Task {
            do {
                if next { try await APIClient.shared.followUser(userId) }
                else    { try await APIClient.shared.unfollowUser(userId) }
            } catch {
                await MainActor.run { following = !next }
            }
            await MainActor.run { busy = false }
        }
    }
}

/// The "Suivis" tab: a social feed (people you follow + you), a source
/// toggle, and a user search to grow your following.
struct SocialFeedView: View {
    @State private var source = "following"
    @State private var items: [SocialFeedItem] = []
    @State private var loading = true
    @State private var query = ""
    @State private var results: [SocialUser] = []
    @State private var openedProfile: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    searchField
                    if !results.isEmpty { searchResults }
                    sourcePicker

                    if loading {
                        ProgressView().padding(.top, 30)
                    } else if items.isEmpty {
                        Text(source == "following"
                             ? "Ton feed est vide. Abonne-toi à des gens avec la recherche ci-dessus."
                             : "Tu n'as pas encore de sortie.")
                            .font(.system(size: 13))
                            .foregroundStyle(AppColors.inkMid)
                            .multilineTextAlignment(.center)
                            .padding(.top, 30).padding(.horizontal, 20)
                    } else {
                        ForEach(items) { item in
                            SocialCardView(item: item) { openedProfile = $0 }
                        }
                    }
                }
                .padding(16)
            }
            .background(AppColors.creamDark.ignoresSafeArea())
            .navigationTitle("Suivis")
            .navigationDestination(item: $openedProfile) { uid in
                PublicProfileView(userId: uid)
            }
            .task(id: source) { await loadFeed() }
            .task(id: query) { await runSearch() }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(AppColors.inkLight)
            TextField("Trouver des amis…", text: $query)
                .autocorrectionDisabled()
        }
        .padding(10)
        .background(AppColors.cream)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.creamBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var searchResults: some View {
        VStack(spacing: 0) {
            ForEach(results) { u in
                HStack(spacing: 10) {
                    Button { openedProfile = u.id } label: {
                        HStack(spacing: 10) {
                            AvatarView(url: u.image, name: u.name, size: 30)
                            Text(u.name ?? "Anonyme").font(.system(size: 14, weight: .semibold)).foregroundStyle(AppColors.ink)
                        }
                    }
                    Spacer()
                    SocialFollowButton(userId: u.id, following: u.isFollowing)
                }
                .padding(.vertical, 8).padding(.horizontal, 12)
                Divider()
            }
        }
        .background(AppColors.cream)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var sourcePicker: some View {
        Picker("", selection: $source) {
            Text("Suivis").tag("following")
            Text("Moi").tag("mine")
        }
        .pickerStyle(.segmented)
    }

    private func loadFeed() async {
        loading = true
        do { items = try await APIClient.shared.socialFeed(source: source) }
        catch { items = [] }
        loading = false
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

/// A user's public profile: identity, follow button, and their visible
/// activities. Tapping another author pushes a nested profile.
struct PublicProfileView: View {
    let userId: String

    @State private var profile: SocialProfile?
    @State private var loading = true
    @State private var openedProfile: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let p = profile {
                    header(p)
                    if let bio = p.bio, !bio.isEmpty {
                        Text(bio).font(.system(size: 14)).foregroundStyle(AppColors.inkMid)
                    }
                    Text("SORTIES (\(p.activities.count))")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(AppColors.terra)
                    if p.activities.isEmpty {
                        Text("Aucune sortie visible.").font(.system(size: 13)).foregroundStyle(AppColors.inkLight)
                    }
                    ForEach(p.activities) { item in
                        SocialCardView(item: item) { openedProfile = $0 }
                    }
                } else if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                } else {
                    Text("Profil introuvable.").foregroundStyle(AppColors.inkMid).padding(.top, 40)
                }
            }
            .padding(16)
        }
        .background(AppColors.creamDark.ignoresSafeArea())
        .navigationTitle(profile?.name ?? "Profil")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openedProfile) { uid in
            PublicProfileView(userId: uid)
        }
        .task { await load() }
    }

    private func header(_ p: SocialProfile) -> some View {
        HStack(spacing: 14) {
            AvatarView(url: p.image, name: p.name, size: 60)
            VStack(alignment: .leading, spacing: 3) {
                Text(p.name ?? "Anonyme").font(.system(size: 20, weight: .heavy, design: .serif)).foregroundStyle(AppColors.ink)
                Text("\(p.followers) abonnés · \(p.following) abonnements")
                    .font(.system(size: 12)).foregroundStyle(AppColors.inkMid)
            }
            Spacer()
            if !p.isMe {
                SocialFollowButton(userId: p.id, following: p.isFollowing)
            }
        }
    }

    private func load() async {
        loading = true
        do { profile = try await APIClient.shared.socialProfile(userId: userId) }
        catch { profile = nil }
        loading = false
    }
}
