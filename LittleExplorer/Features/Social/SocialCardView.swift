import MapKit
import SwiftUI

/// Renders a static map image with the GPS route drawn on top, via
/// MKMapSnapshotter — used for the shareable story card so the trace sits on a
/// real basemap instead of a flat colour.
enum RouteSnapshot {
    @MainActor
    static func image(coords: [CLLocationCoordinate2D], size: CGSize) async -> UIImage? {
        let pts = coords.filter { CLLocationCoordinate2DIsValid($0) }
        guard pts.count >= 2 else { return nil }

        var minLat = pts[0].latitude, maxLat = pts[0].latitude
        var minLng = pts[0].longitude, maxLng = pts[0].longitude
        for p in pts {
            minLat = min(minLat, p.latitude);  maxLat = max(maxLat, p.latitude)
            minLng = min(minLng, p.longitude); maxLng = max(maxLng, p.longitude)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2)
        // ~18% padding so the route isn't glued to the edges.
        let span = MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.36, 0.002),
                                    longitudeDelta: max((maxLng - minLng) * 1.36, 0.002))

        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: center, span: span)
        options.size = size
        options.scale = 3
        options.pointOfInterestFilter = .excludingAll

        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return nil }

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            snapshot.image.draw(at: .zero)
            let cg = ctx.cgContext
            cg.setStrokeColor(UIColor(AppColors.terra).cgColor)
            cg.setLineWidth(5)
            cg.setLineJoin(.round)
            cg.setLineCap(.round)
            for (i, coord) in pts.enumerated() {
                let point = snapshot.point(for: coord)
                if i == 0 { cg.move(to: point) } else { cg.addLine(to: point) }
            }
            cg.strokePath()
        }
    }
}

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
    @State private var shareItem: ShareItem?
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
                .padding(.horizontal, 16)
            // Everything else is a single button → tapping the title, map or
            // stats opens the detail. A Button captures taps reliably even over
            // the MapKit map (an .onTapGesture doesn't). The map is full-bleed
            // (edge to edge, Strava-style); text/stats keep side padding.
            Button {
                onOpenActivity(item.id)
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    if let title = item.title, !title.isEmpty {
                        Text(title)
                            .font(.system(size: 21, weight: .heavy, design: .serif))
                            .foregroundStyle(AppColors.ink)
                            .padding(.horizontal, 16)
                    }
                    if item.gps.count >= 2 {
                        RouteMiniMap(
                            gps: item.gps.map { Coordinate(lat: $0[0], lng: $0[1]) },
                            speedKmh: nil,
                            fallbackColor: AppColors.terra,
                            height: 240,
                        )
                    }
                    stats
                        .padding(.horizontal, 16)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            actions
                .padding(.horizontal, 16)
        }
        .padding(.vertical, 14)
        .background(AppColors.cream)
        .sheet(isPresented: $showComments) {
            CommentsView(activityId: item.id) { commentCount = $0 }
        }
        // item-based sheet: only presents once the rendered image exists, so we
        // never flash an empty black sheet (the isPresented+optional-content
        // race that forced a quit-and-retry).
        .sheet(item: $shareItem) { item in
            ShareSheet(items: item.activityItems)
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
        Task {
            let coords = item.gps.compactMap { g -> CLLocationCoordinate2D? in
                g.count >= 2 ? CLLocationCoordinate2D(latitude: g[0], longitude: g[1]) : nil
            }
            let mapImg = await RouteSnapshot.image(coords: coords, size: CGSize(width: 349, height: 340))
            let card = StoryCardView(item: item, mapImage: mapImg).frame(width: 405, height: 720)
            let renderer = ImageRenderer(content: card)
            renderer.scale = 3
            guard let img = renderer.uiImage else { return }
            var url: URL?
            if visibility == .public {
                url = URL(string: "https://the-little-explorer-app.vercel.app/api/share/activity/\(item.id)")
            }
            shareItem = ShareItem(image: img, link: url)
        }
    }
}

/// A rendered share image (+ optional public link), wrapped as Identifiable so
/// `.sheet(item:)` presents it only once it's ready.
struct ShareItem: Identifiable {
    let id = UUID()
    let image: UIImage
    let link: URL?
    var activityItems: [Any] { link.map { [image, $0] } ?? [image] }
}

/// The story image rendered for Instagram (via ImageRenderer). Fixed 9:16-ish
/// canvas: brand, title, the trace, and the headline stats.
struct StoryCardView: View {
    let item: SocialFeedItem
    var mapImage: UIImage? = nil
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

            // Real basemap with the route on it (falls back to the bare trace
            // if the snapshot couldn't be generated).
            if let mapImage {
                Image(uiImage: mapImage)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 340)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.vertical, 24)
            } else if item.gps.count >= 2 {
                TraceShape(points: item.gps)
                    .stroke(AppColors.terra, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    .frame(height: 340)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                // No GPS (pool swim, gym…): a sport hero instead of empty space.
                ZStack {
                    RoundedRectangle(cornerRadius: 16).fill(AppColors.terra.opacity(0.12))
                    VStack(spacing: 14) {
                        Image(systemName: Self.sportSymbol(item.sport))
                            .font(.system(size: 96, weight: .regular))
                            .foregroundStyle(AppColors.terra)
                        Text(SocialFmt.sportLabel(item.sport).uppercased())
                            .font(.system(size: 15, weight: .heavy))
                            .tracking(2)
                            .foregroundStyle(AppColors.inkMid)
                    }
                }
                .frame(height: 340)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            }

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
    static func sportSymbol(_ sport: String) -> String {
        switch sport {
        case "swim":      return "figure.pool.swim"
        case "running":   return "figure.run"
        case "walking":   return "figure.walk"
        case "hiking":    return "figure.hiking"
        case "cycling":   return "figure.outdoor.cycle"
        case "rowing":    return "figure.rower"
        case "ski":       return "figure.skiing.downhill"
        case "snowboard": return "figure.snowboarding"
        case "yoga":      return "figure.mind.and.body"
        case "workout":   return "figure.strengthtraining.traditional"
        default:          return "figure.run"
        }
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
