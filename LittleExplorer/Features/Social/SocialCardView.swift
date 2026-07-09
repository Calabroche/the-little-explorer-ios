import SwiftUI

/// One feed / profile card: author header, GPS trace, stats, and the
/// like / comment / share actions. Owner cards also get a visibility menu.
struct SocialCardView: View {
    let item: SocialFeedItem
    var onOpenProfile: (String) -> Void = { _ in }
    var onOpenActivity: (Int) -> Void = { _ in }

    @State private var liked: Bool
    @State private var likeCount: Int
    @State private var commentCount: Int
    @State private var visibility: ActivityVisibility
    @State private var showComments = false
    @State private var shareImage: UIImage?
    @State private var showShare = false
    @State private var likeBusy = false

    init(item: SocialFeedItem,
         onOpenProfile: @escaping (String) -> Void = { _ in },
         onOpenActivity: @escaping (Int) -> Void = { _ in }) {
        self.item = item
        self.onOpenProfile = onOpenProfile
        self.onOpenActivity = onOpenActivity
        _liked        = State(initialValue: item.likedByMe)
        _likeCount    = State(initialValue: item.likeCount)
        _commentCount = State(initialValue: item.commentCount)
        _visibility   = State(initialValue: item.visibility)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Author row on top (its own buttons open the profile / menu).
            header
            // Everything else is a single button → tapping the title, map or
            // stats opens the detail. A Button captures taps reliably even over
            // the MapKit map (an .onTapGesture doesn't).
            Button {
                onOpenActivity(item.id)
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    if let title = item.title, !title.isEmpty {
                        Text(title)
                            .font(.system(size: 21, weight: .heavy, design: .serif))
                            .foregroundStyle(AppColors.ink)
                    }
                    if item.gps.count >= 2 {
                        RouteMiniMap(
                            gps: item.gps.map { Coordinate(lat: $0[0], lng: $0[1]) },
                            speedKmh: nil,
                            fallbackColor: AppColors.terra,
                            height: 190,
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColors.creamBorder, lineWidth: 1))
                    }
                    stats
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            actions
        }
        .padding(16)
        .background(AppColors.cream)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.creamBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .sheet(isPresented: $showComments) {
            CommentsView(activityId: item.id) { commentCount = $0 }
        }
        .sheet(isPresented: $showShare) {
            if let img = shareImage {
                ShareSheet(items: shareItems(img))
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { onOpenProfile(item.author.id) } label: {
                AvatarView(url: item.author.image, name: item.author.name, size: 46)
            }
            VStack(alignment: .leading, spacing: 1) {
                Button { onOpenProfile(item.author.id) } label: {
                    Text(item.author.name ?? "Anonyme")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(AppColors.ink)
                }
                Text("\(SocialFmt.shortDate(item.date)) · \(SocialFmt.sportLabel(item.sport))")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.inkLight)
            }
            Spacer()
            if item.isMine {
                Menu {
                    ForEach(ActivityVisibility.allCases) { v in
                        Button(v.label) { changeVisibility(v) }
                    }
                } label: {
                    Label(visibility.label, systemImage: "eye")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppColors.inkMid)
                }
            }
        }
    }

    private var stats: some View {
        HStack(spacing: 18) {
            statCell("Distance", SocialFmt.distance(item.distanceKm), AppColors.ink)
            statCell("Dénivelé +", SocialFmt.elevation(item.elevationM), AppColors.terra)
            statCell("Temps", SocialFmt.duration(item.durationMin), AppColors.ink)
            statCell("V. max", SocialFmt.speed(item.maxSpeedKmh), Color(red: 0.24, green: 0.44, blue: 0.64))
        }
    }
    private func statCell(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 15, weight: .bold, design: .serif)).foregroundStyle(color)
            Text(label.uppercased()).font(.system(size: 8, weight: .semibold)).foregroundStyle(AppColors.inkLight)
        }
    }

    private var actions: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 0) {
                actionButton(liked ? "❤️" : "🤍", likeCount > 0 ? "\(likeCount)" : "Kudos", active: liked) { toggleLike() }
                actionButton("💬", commentCount > 0 ? "\(commentCount)" : "Commenter") { showComments = true }
                actionButton("↗", "Partager") { presentShare() }
            }
        }
        .padding(.top, 6)
    }
    private func actionButton(_ icon: String, _ label: String, active: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(icon).font(.system(size: 15))
                Text(label).font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(active ? AppColors.terra : AppColors.inkMid)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
    }

    // ── Actions ─────────────────────────────────────────────────────────────
    private func toggleLike() {
        guard !likeBusy else { return }
        likeBusy = true
        let next = !liked
        liked = next; likeCount += next ? 1 : -1
        Task {
            do {
                if next { try await APIClient.shared.likeActivity(item.id) }
                else    { try await APIClient.shared.unlikeActivity(item.id) }
            } catch {
                await MainActor.run { liked = !next; likeCount += next ? -1 : 1 }
            }
            await MainActor.run { likeBusy = false }
        }
    }
    private func changeVisibility(_ v: ActivityVisibility) {
        let prev = visibility
        visibility = v
        Task {
            do { try await APIClient.shared.setVisibility(activityId: item.id, visibility: v) }
            catch { await MainActor.run { visibility = prev } }
        }
    }
    @MainActor private func presentShare() {
        let card = StoryCardView(item: item).frame(width: 405, height: 720)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        if let img = renderer.uiImage {
            shareImage = img
            showShare = true
        }
    }
    private func shareItems(_ img: UIImage) -> [Any] {
        var items: [Any] = [img]
        if visibility == .public,
           let url = URL(string: "https://the-little-explorer-app.vercel.app/api/share/activity/\(item.id)") {
            items.append(url)
        }
        return items
    }
}

/// The story image rendered for Instagram (via ImageRenderer). Fixed 9:16-ish
/// canvas: brand, title, the trace, and the headline stats.
struct StoryCardView: View {
    let item: SocialFeedItem
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("The Little Explorer")
                .font(.system(size: 18, weight: .heavy, design: .serif))
                .foregroundStyle(AppColors.terra)
            Text(item.title ?? "Sortie")
                .font(.system(size: 30, weight: .heavy, design: .serif))
                .foregroundStyle(AppColors.ink)
                .lineLimit(2)
                .padding(.top, 6)

            TraceShape(points: item.gps)
                .stroke(AppColors.terra, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .frame(height: 360)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)

            HStack {
                storyStat("DISTANCE", SocialFmt.distance(item.distanceKm))
                Spacer()
                storyStat("DÉNIVELÉ", SocialFmt.elevation(item.elevationM))
            }
            HStack {
                storyStat("TEMPS", SocialFmt.duration(item.durationMin))
                Spacer()
                storyStat("V. MAX", SocialFmt.speed(item.maxSpeedKmh))
            }.padding(.top, 20)
            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            LinearGradient(colors: [AppColors.cream, AppColors.terraLight],
                           startPoint: .top, endPoint: .bottom)
        )
    }
    private func storyStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 13, weight: .semibold)).foregroundStyle(AppColors.inkLight)
            Text(value).font(.system(size: 30, weight: .heavy, design: .serif)).foregroundStyle(AppColors.ink)
        }
    }
}

/// Comment thread for one activity — list + add + delete, in a sheet.
struct CommentsView: View {
    let activityId: Int
    var onCountChange: (Int) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @State private var comments: [SocialComment] = []
    @State private var loading = true
    @State private var draft = ""
    @State private var sending = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if loading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            if comments.isEmpty {
                                Text("Aucun commentaire.")
                                    .font(.system(size: 13)).foregroundStyle(AppColors.inkLight)
                                    .padding(.top, 20)
                            }
                            ForEach(comments) { c in
                                HStack(alignment: .top, spacing: 8) {
                                    AvatarView(url: c.author.image, name: c.author.name, size: 28)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(c.author.name ?? "Anonyme").font(.system(size: 12, weight: .bold)).foregroundStyle(AppColors.ink)
                                        Text(c.body).font(.system(size: 13)).foregroundStyle(AppColors.inkMid)
                                    }
                                    Spacer()
                                    if c.isMine {
                                        Button { remove(c) } label: {
                                            Image(systemName: "trash").font(.system(size: 12)).foregroundStyle(AppColors.inkLight)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(16)
                    }
                }
                Divider()
                HStack(spacing: 8) {
                    TextField("Ajouter un commentaire…", text: $draft)
                        .textFieldStyle(.roundedBorder)
                    Button { send() } label: {
                        Image(systemName: "paperplane.fill")
                    }
                    .disabled(sending || draft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(12)
            }
            .navigationTitle("Commentaires")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
            .task { await load() }
        }
    }

    private func load() async {
        loading = true
        do { comments = try await APIClient.shared.comments(activityId: activityId) }
        catch { comments = [] }
        loading = false
    }
    private func send() {
        let body = draft.trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty, !sending else { return }
        sending = true
        Task {
            do {
                let c = try await APIClient.shared.postComment(activityId: activityId, body: body)
                await MainActor.run {
                    comments.append(c); draft = ""; onCountChange(comments.count)
                }
            } catch { /* keep draft */ }
            await MainActor.run { sending = false }
        }
    }
    private func remove(_ c: SocialComment) {
        Task {
            do {
                try await APIClient.shared.deleteComment(activityId: activityId, commentId: c.id)
                await MainActor.run {
                    comments.removeAll { $0.id == c.id }; onCountChange(comments.count)
                }
            } catch { /* ignore */ }
        }
    }
}
