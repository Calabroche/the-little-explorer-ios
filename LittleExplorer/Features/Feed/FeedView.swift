import SwiftUI

/// Root of the activities tab — replicates the web app's `/` page.
/// Stitches together the calendar heatmap, training program, personal
/// records, optional run pace zones, last-5 averages, and the scrolling
/// list of activity cards. Filters everything by the selected sport.
struct FeedView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        @Bindable var env = environment
        NavigationStack {
            VStack(spacing: 0) {
                BrandHeader()
                content(env: env)
            }
            .background(AppColors.cream)
            .toolbar(.hidden, for: .navigationBar)
            .task {
                await env.activityStore.load(user: env.currentUser)
                await Self.backgroundSyncStravaIfEmpty(env: env)
            }
            .refreshable {
                // Pull-to-refresh is an explicit user gesture — always
                // try syncing whether the feed is empty or not. Sync
                // first so any newly-added rows are picked up by the
                // subsequent reload, otherwise the user would see the
                // pre-sync state and have to refresh twice.
                await Self.backgroundSyncStrava(env: env)
                await env.activityStore.load(user: env.currentUser, force: true)
            }
            .onChange(of: env.currentUser) { _, newUser in
                Task {
                    await env.activityStore.load(user: newUser)
                    await Self.backgroundSyncStravaIfEmpty(env: env)
                }
            }
        }
    }

    /// Only auto-sync when the feed is empty — matches the web's
    /// autoSync useEffect in ExplorerApp.tsx. Covers the "new user
    /// just connected Strava, the cron hasn't run yet" path without
    /// hitting `/api/strava/sync` on every Feed appearance (which
    /// historically clobbered streams via an upsert bug).
    static func backgroundSyncStravaIfEmpty(env: AppEnvironment) async {
        guard env.activityStore.activities.isEmpty else { return }
        await backgroundSyncStrava(env: env)
    }

    /// Fire-and-forget Strava sync. Pulls anything newer from Strava
    /// into Supabase server-side; if the server reports new rows,
    /// force-reload activities so the heatmap / cards / records pick
    /// them up without the user having to tap "Re-syncer Strava"
    /// manually. Silent on failure — sync is best-effort.
    static func backgroundSyncStrava(env: AppEnvironment) async {
        do {
            let result = try await env.api.syncStrava()
            if result.ok, (result.count ?? 0) > 0 {
                await env.activityStore.load(user: env.currentUser, force: true)
            }
        } catch {
            #if DEBUG
            print("[backgroundSyncStrava] skipped: \(error.localizedDescription)")
            #endif
        }
    }

    @ViewBuilder
    private func content(env: AppEnvironment) -> some View {
        switch env.activityStore.state {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView(
                "Couldn't load activities",
                systemImage: "exclamationmark.triangle",
                description: Text(message),
            )
        case .loaded:
            FeedScrollView(env: env)
        }
    }
}

/// Editorial wordmark — "The Little / Explorer" stacked, with `Explorer`
/// italicised in terra. Mirrors the web sidebar lockup so the brand
/// shows up consistently on the welcome page.
struct BrandLockup: View {
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: -2) {
            Text("The Little")
                .font(.system(size: compact ? 14 : 16, design: .serif).weight(.heavy))
                .foregroundStyle(AppColors.ink)
            Text("Explorer")
                .font(.system(size: compact ? 14 : 16, design: .serif).weight(.heavy).italic())
                .foregroundStyle(AppColors.terra)
        }
        .fixedSize(horizontal: true, vertical: true)
    }
}

/// Top header shown on the welcome screens — brand wordmark on the
/// left and a read-only signed-in user pill on the right (taps route
/// to the Profil tab). The legacy Florian/Helena picker is gone —
/// multi-user auth means each session sees only their own data.
struct BrandHeader: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(AppRouter.self) private var router

    var body: some View {
        HStack(alignment: .center) {
            Button {
                router.goHome()
            } label: {
                BrandLockup()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Retour aux activités")

            Spacer(minLength: 12)
            SignedInUserPill(profile: environment.session.profile) {
                router.selectedTab = .profile
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }
}

/// Compact pill showing the signed-in user's display name. Tap to
/// jump to the Profil tab.
struct SignedInUserPill: View {
    let profile: MeProfile?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(AppColors.terra)
                Text(displayName)
                    .font(.system(size: 13, design: .serif).weight(.bold))
                    .foregroundStyle(AppColors.ink)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppColors.surface, in: Capsule())
            .overlay(Capsule().stroke(AppColors.creamBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Profil")
    }

    private var displayName: String {
        if let name = profile?.name, !name.isEmpty { return name }
        if let email = profile?.email, !email.isEmpty {
            return email.split(separator: "@").first.map(String.init) ?? email
        }
        return "Compte"
    }
}

private struct FeedScrollView: View {
    @Bindable var env: AppEnvironment
    @Environment(AppRouter.self) private var router

    private static let scrollAnchorID = "feed-top"

    var body: some View {
        let allActivities = env.activityStore.activities
        let filtered = env.activityStore.filtered(by: env.selectedSport)
        let availableSports = allActivities.availableSports

        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Invisible anchor at the very top — the brand-tap
                    // action scrolls back to this id.
                    Color.clear
                        .frame(height: 1)
                        .id(Self.scrollAnchorID)

                    if availableSports.count > 1 {
                        SportPicker(sport: $env.selectedSport, available: availableSports)
                            .padding(.horizontal, 16)
                    }

                    headline(activities: filtered)
                        .padding(.horizontal, 16)

                    Last5StatsView(activities: filtered).padding(.horizontal, 16)
                    ActivityCalendarView(activities: filtered).padding(.horizontal, 16)
                    PersonalRecordsView(activities: filtered, sport: env.selectedSport).padding(.horizontal, 16)
                    if env.selectedSport == .running {
                        RunPaceZonesView(activities: filtered).padding(.horizontal, 16)
                    }
                    if env.selectedSport == .cycling {
                        TrainingProgramView(activities: filtered).padding(.horizontal, 16)
                    }

                    Divider().padding(.horizontal, 16)

                    LazyVStack(spacing: 14) {
                        ForEach(filtered) { activity in
                            NavigationLink(value: activity) {
                                ActivityCard(activity: activity)
                                    .padding(.horizontal, 16)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.vertical, 16)
            }
            .navigationDestination(for: RideRecord.self) { record in
                ActivityDetailView(activity: record)
            }
            .onChange(of: router.feedScrollTrigger) { _, _ in
                withAnimation(.easeInOut(duration: 0.45)) {
                    proxy.scrollTo(Self.scrollAnchorID, anchor: .top)
                }
            }
        }
    }

    private func headline(activities: [RideRecord]) -> some View {
        let totalKm = activities.compactMap(\.distance).reduce(0, +)
        let totalElev = activities.compactMap(\.elevation).reduce(0, +)
        return VStack(alignment: .leading, spacing: 4) {
            Text("\(activities.count) sorties")
                .font(.system(.largeTitle, design: .serif).weight(.heavy))
                .foregroundStyle(AppColors.ink)
            Text("\(Int(totalKm)) km · \(Int(totalElev)) m D+")
                .font(.system(.title2, design: .serif).weight(.bold).italic())
                .foregroundStyle(AppColors.terra)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Sport picker

private struct SportPicker: View {
    @Binding var sport: Sport
    let available: [Sport]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(available) { option in
                    let isActive = sport == option
                    Button {
                        sport = option
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: option.symbol).font(.system(size: 11))
                            Text(option.displayName).font(.system(size: 11).weight(isActive ? .bold : .medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(isActive ? AppColors.terra : Color.clear),
                        )
                        .foregroundStyle(isActive ? Color.white : AppColors.inkMid)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
        }
        .background(AppColors.creamDark, in: RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(AppColors.creamBorder, lineWidth: 1))
    }
}

