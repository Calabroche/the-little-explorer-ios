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

// Typed navigation values so ONE NavigationStack can push both a profile and
// an activity detail (multiple `navigationDestination(item:)` of different
// types on one stack is unreliable — this is the robust pattern).
struct NavProfile: Hashable { let id: String }
struct NavActivity: Hashable { let record: RideRecord; let canDelete: Bool }

/// The "Suivis" tab: a social feed (people you follow + you), a source
/// toggle, and a user search to grow your following.
struct SocialFeedView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppEnvironment.self) private var environment
    @State private var items: [SocialFeedItem] = []
    @State private var loading = true
    @State private var showSearch = false
    @State private var showWhatsNew = false
    @State private var path = NavigationPath()
    @State private var myImage: String?

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(spacing: 14) {
                    if loading {
                        ProgressView().padding(.top, 40)
                    } else if items.isEmpty {
                        emptyState
                    } else {
                        ForEach(items) { item in
                            SocialCardView(item: item,
                                           onOpenProfile: { path.append(NavProfile(id: $0)) },
                                           onOpenActivity: { id in Task { if let r = try? await APIClient.shared.activity(id: id) { path.append(NavActivity(record: r, canDelete: item.isMine)) } } })
                        }
                    }
                }
                .padding(16)
            }
            .background(AppColors.creamDark.ignoresSafeArea())
            .navigationTitle("Accueil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Left: my profile avatar → jump to the Profil tab.
                ToolbarItem(placement: .topBarLeading) {
                    Button { router.selectedTab = .profile } label: {
                        AvatarView(url: myImage, name: environment.session.profile?.name, size: 30)
                    }
                }
                // Right: info + search friends.
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showWhatsNew = true } label: {
                        Image(systemName: "info.circle").foregroundStyle(AppColors.terra)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSearch = true } label: {
                        Image(systemName: "magnifyingglass").foregroundStyle(AppColors.terra)
                    }
                }
            }
            .navigationDestination(for: NavProfile.self) { p in
                PublicProfileView(userId: p.id, path: $path)
            }
            .navigationDestination(for: NavActivity.self) { a in
                ActivityDetailView(activity: a.record, canDelete: a.canDelete)
            }
            .sheet(isPresented: $showSearch) { FriendSearchView() }
            .sheet(isPresented: $showWhatsNew) { WhatsNewView(initialRunning: environment.selectedSport == .running) }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.2").font(.system(size: 40)).foregroundStyle(AppColors.inkLight)
            Text("Ton fil est vide.").font(.system(size: 15, weight: .semibold)).foregroundStyle(AppColors.ink)
            Text("Cherche des amis avec la loupe en haut à droite pour voir leurs sorties ici.")
                .font(.system(size: 13)).foregroundStyle(AppColors.inkMid).multilineTextAlignment(.center)
        }
        .padding(.top, 60).padding(.horizontal, 30)
    }

    @MainActor private func load() async {
        loading = true
        do { items = try await APIClient.shared.socialFeed(source: "following") }
        catch { items = [] }
        loading = false
        if myImage == nil, let id = environment.session.profile?.id {
            myImage = (try? await APIClient.shared.socialProfile(userId: id))?.image
        }
    }
}

/// A user's public profile: identity, follow button, and their visible
/// activities. Tapping another author pushes a nested profile.
struct PublicProfileView: View {
    let userId: String
    @Binding var path: NavigationPath

    @State private var profile: SocialProfile?
    @State private var loading = true

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
                        SocialCardView(item: item,
                                       onOpenProfile: { path.append(NavProfile(id: $0)) },
                                       onOpenActivity: { id in Task { if let r = try? await APIClient.shared.activity(id: id) { path.append(NavActivity(record: r, canDelete: item.isMine)) } } })
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
        // Navigation destinations are declared once on the root stack.
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
