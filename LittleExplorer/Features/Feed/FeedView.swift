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
                .navigationTitle("Activités")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Picker("User", selection: $env.currentUser) {
                            ForEach(AppUser.allCases) { Text($0.displayName).tag($0) }
                        }
                        .pickerStyle(.menu)
                    }
                }
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

                LazyVStack(spacing: 8) {
                    ForEach(filtered) { activity in
                        NavigationLink(value: activity) {
                            ActivityCardRow(activity: activity)
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

// MARK: - Activity card row

private struct ActivityCardRow: View {
    let activity: RideRecord

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(AppColors.terraLight)
                    .frame(width: 44, height: 44)
                Image(systemName: activity.sportSymbol)
                    .foregroundStyle(AppColors.terra)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(activity.title)
                    .font(.system(.subheadline, design: .serif).weight(.bold))
                    .foregroundStyle(AppColors.ink)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Text(activity.date)
                    if let dist = activity.distance { Text("· \(String(format: "%.1f", dist)) km") }
                    if let elev = activity.elevation { Text("· \(Int(elev)) m") }
                    Text("· \(activity.duration)")
                }
                .font(.caption)
                .foregroundStyle(AppColors.inkLight)
                if let tss = activity.tss {
                    Text("TSS \(tss)")
                        .font(.caption2)
                        .foregroundStyle(AppColors.terra)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppColors.creamBorder, lineWidth: 1))
    }
}
