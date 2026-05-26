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
            Log.sync.error("backgroundSyncStrava skipped: \(error.localizedDescription, privacy: .public)")
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
                VStack(alignment: .leading, spacing: 18) {
                    // Invisible anchor at the very top — the brand-tap
                    // action scrolls back to this id.
                    Color.clear
                        .frame(height: 1)
                        .id(Self.scrollAnchorID)

                    FeedHero(
                        userName: env.session.profile?.name,
                        sport: $env.selectedSport,
                        availableSports: availableSports,
                        activities: filtered,
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, -10)   // tighten the gap to the BrandHeader

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
                            // contextMenu: long-press the card to get a
                            // Delete option WITHOUT opening the detail
                            // view. This is the escape hatch when a
                            // record's data triggers the detail-view
                            // crash — user can purge the bad ride from
                            // here without ever rendering the broken
                            // ActivityDetailView body.
                            .contextMenu {
                                if activity.id < 0 {
                                    Button(role: .destructive) {
                                        env.localRides.remove(id: activity.id, for: env.currentUser)
                                        env.activityStore.refreshLocal(user: env.currentUser)
                                    } label: {
                                        Label("Supprimer cette sortie", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.top, 4)
                .padding(.bottom, 16)
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

}

// MARK: - Hero (greeting + period stats card)

/// Editorial top-of-feed module: a time-of-day greeting, the current
/// month in a serif headline, and a period-scoped stats card showing
/// the totals (sorties / km / D+ / heures) for the active sport.
/// Replaces the previous plain "X sorties · Y km" text block — same
/// data, much more visible.
private struct FeedHero: View {
    let userName: String?
    @Binding var sport: Sport
    let availableSports: [Sport]
    let activities: [RideRecord]
    @State private var period: HeroPeriod = .month

    enum HeroPeriod: String, CaseIterable, Identifiable {
        case month, last30, last90, year, all
        var id: String { rawValue }

        var label: String {
            switch self {
            case .month:  return "Ce mois"
            case .last30: return "30 j"
            case .last90: return "3 mois"
            case .year:   return "2026"
            case .all:    return "Tout"
            }
        }

        /// Activities matching this period — uses local-tz comparison
        /// against the rawDate ISO string.
        func filter(_ activities: [RideRecord], now: Date = .now) -> [RideRecord] {
            let cal = Calendar.current
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return activities.filter { record in
                let date: Date? = formatter.date(from: record.rawDate)
                    ?? ISO8601DateFormatter().date(from: record.rawDate)
                guard let date else { return false }
                switch self {
                case .month:
                    return cal.isDate(date, equalTo: now, toGranularity: .month)
                case .year:
                    return cal.isDate(date, equalTo: now, toGranularity: .year)
                case .last30:
                    let cutoff = cal.date(byAdding: .day, value: -30, to: now) ?? now
                    return date >= cutoff
                case .last90:
                    let cutoff = cal.date(byAdding: .day, value: -90, to: now) ?? now
                    return date >= cutoff
                case .all:
                    return true
                }
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            greetingBlock
            statsCard
        }
    }

    // MARK: - Greeting + month/year

    @ViewBuilder
    private var greetingBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(greeting)
                    .font(.system(size: 13).weight(.semibold))
                    .foregroundStyle(AppColors.inkLight)
                if let firstName {
                    Text(firstName)
                        .font(.system(size: 13).weight(.bold))
                        .foregroundStyle(AppColors.inkMid)
                }
            }
            // Month/year on the left, sport accordion on the right —
            // they share the same baseline so the picker is right next
            // to "Mai 2026" instead of taking a separate row below.
            HStack(alignment: .center, spacing: 12) {
                Text(monthYearLabel)
                    .font(.system(.largeTitle, design: .serif).weight(.heavy))
                    .foregroundStyle(AppColors.ink)
                Spacer(minLength: 6)
                if availableSports.count > 1 {
                    SportPickerAccordion(sport: $sport, available: availableSports)
                        .frame(maxWidth: 180, alignment: .trailing)
                }
            }
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Bonjour"
        case 12..<18: return "Bel après-midi"
        default:      return "Bonsoir"
        }
    }

    private var firstName: String? {
        userName?.split(separator: " ").first.map(String.init)
    }

    private var monthYearLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        formatter.locale = Locale(identifier: "fr_FR")
        return formatter.string(from: Date()).capitalized
    }

    // MARK: - Period stats card

    private var statsCard: some View {
        let scoped = period.filter(activities)
        let totalKm   = scoped.compactMap(\.distance).reduce(0, +)
        let totalElev = scoped.compactMap(\.elevation).reduce(0, +)
        let totalMin  = scoped.map(\.durationMin).reduce(0, +)
        let hours = Double(totalMin) / 60
        let totalDuration = totalMin >= 60
            ? String(format: "%dh %02d", totalMin / 60, totalMin % 60)
            : "\(totalMin) min"
        let avgSpeed: Double? = hours > 0 ? totalKm / hours : nil

        return VStack(alignment: .leading, spacing: 14) {
            // Period selector chip row.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(HeroPeriod.allCases) { p in
                        Button {
                            period = p
                        } label: {
                            Text(p.label)
                                .font(.system(size: 11).weight(period == p ? .bold : .medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(period == p ? AppColors.terra : AppColors.creamDark, in: Capsule())
                                .overlay(Capsule().stroke(AppColors.creamBorder, lineWidth: 1))
                                .foregroundStyle(period == p ? Color.white : AppColors.inkMid)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // 3-column big stats row.
            HStack(spacing: 0) {
                heroStat(value: "\(scoped.count)",        unit: "SORTIES")
                Divider().frame(height: 36).background(AppColors.creamBorder)
                heroStat(value: "\(Int(totalKm.rounded()))", unit: "KM")
                Divider().frame(height: 36).background(AppColors.creamBorder)
                heroStat(value: "\(Int(totalElev.rounded()))", unit: "M D+")
            }

            // Secondary line: total time + avg speed.
            HStack(spacing: 12) {
                Label(totalDuration, systemImage: "clock")
                    .font(.system(size: 11).weight(.semibold))
                    .foregroundStyle(AppColors.inkMid)
                if let avgSpeed {
                    Label(String(format: "%.1f km/h", avgSpeed), systemImage: "speedometer")
                        .font(.system(size: 11).weight(.semibold))
                        .foregroundStyle(AppColors.inkMid)
                }
                Spacer()
            }
        }
        .padding(14)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColors.creamBorder, lineWidth: 1))
    }

    private func heroStat(value: String, unit: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.title, design: .serif).weight(.heavy))
                .foregroundStyle(AppColors.ink)
                .monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(unit)
                .font(.system(size: 9).weight(.bold)).tracking(1.2)
                .foregroundStyle(AppColors.inkLight)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Sport picker

/// Native iOS Menu-style sport selector. Tap the chip → a compact
/// system dropdown appears with all available sports. Selection
/// is one tap (no separate close action), Apple handles the
/// animation + dismiss + accessibility automatically. The visible
/// chip stays compact whether or not the menu is open.
private struct SportPickerAccordion: View {
    @Binding var sport: Sport
    let available: [Sport]

    var body: some View {
        Menu {
            ForEach(available) { option in
                Button {
                    sport = option
                } label: {
                    Label(option.displayName, systemImage: option.symbol)
                    if option == sport {
                        // The checkmark next to the active item makes
                        // the current selection unambiguous when the
                        // menu opens.
                        Image(systemName: "checkmark")
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: sport.symbol)
                    .font(.system(size: 12).weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(sport.color, in: Circle())
                Text(sport.displayName)
                    .font(.system(size: 14).weight(.bold))
                    .foregroundStyle(AppColors.ink)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9).weight(.bold))
                    .foregroundStyle(AppColors.inkLight)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(AppColors.surface, in: Capsule())
            .overlay(Capsule().stroke(AppColors.creamBorder, lineWidth: 1))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }
}

/// Legacy horizontal chip strip — kept for any place that still wants
/// it (none right now). The accordion above is the default for the
/// Feed.
private struct SportPicker: View {
    @Binding var sport: Sport
    let available: [Sport]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(available) { option in
                    let isActive = sport == option
                    Button {
                        sport = option
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: option.symbol).font(.system(size: 13).weight(.semibold))
                            Text(option.displayName).font(.system(size: 13).weight(isActive ? .bold : .medium))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(
                            Capsule().fill(isActive ? option.color : AppColors.surface),
                        )
                        .overlay(Capsule().stroke(isActive ? Color.clear : AppColors.creamBorder, lineWidth: 1))
                        .foregroundStyle(isActive ? Color.white : AppColors.inkMid)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

