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
            content(env: env)
                .background(AppColors.cream)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        BrandLockup()
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Picker("User", selection: $env.currentUser) {
                            ForEach(AppUser.allCases) { Text($0.displayName).tag($0) }
                        }
                        .pickerStyle(.menu)
                    }
                }
                .toolbarTitleDisplayMode(.inline)
                .task { await env.activityStore.load(user: env.currentUser) }
                .refreshable { await env.activityStore.load(user: env.currentUser, force: true) }
                .onChange(of: env.currentUser) { _, newUser in
                    Task { await env.activityStore.load(user: newUser) }
                }
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
    }
}

private struct FeedScrollView: View {
    @Bindable var env: AppEnvironment

    var body: some View {
        let allActivities = env.activityStore.activities
        let filtered = env.activityStore.filtered(by: env.selectedSport)
        let availableSports = allActivities.availableSports

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if availableSports.count > 1 {
                    SportPicker(sport: $env.selectedSport, available: availableSports)
                        .padding(.horizontal, 16)
                }

                headline(activities: filtered)
                    .padding(.horizontal, 16)

                if env.selectedSport == .cycling {
                    TrainingProgramView(activities: filtered).padding(.horizontal, 16)
                }
                ActivityCalendarView(activities: filtered).padding(.horizontal, 16)
                PersonalRecordsView(activities: filtered, sport: env.selectedSport).padding(.horizontal, 16)
                if env.selectedSport == .running {
                    RunPaceZonesView(activities: filtered).padding(.horizontal, 16)
                }
                Last5StatsView(activities: filtered).padding(.horizontal, 16)

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

