import SwiftUI

/// "Performances" — destination in the Analyses hub that gathers the
/// two heavy training-load cards that used to live at the bottom of
/// the Feed:
///   • Personal Records (best power efforts for cycling, best paces for
///     running)
///   • Programme d'entraînement TSS (cycling-only — bar chart of the
///     last 10 rides, next-ride prediction, 10 % rule explainer)
///
/// Moved out of the Feed because the home tab was getting long: scroll
/// fatigue + the records grids re-rendered on every sport change. Now
/// the user opts in by tapping into Analyses → Performances.
///
/// Inline sport chip at the top (Vélo / Course) drives what the cards
/// show; it does NOT mutate the global `env.selectedSport` so toggling
/// here doesn't change what the Feed displays.
struct PerformanceView: View {
    @Environment(AppEnvironment.self) private var environment

    /// Seeded once from the global selected sport so the screen lands
    /// on whatever the user was already browsing.
    @State private var sport: Sport = .cycling
    @State private var didSeed: Bool = false

    var body: some View {
        let activities = environment.activityStore.activities
        let filtered = activities.filter { matches(sport: sport, activity: $0) }

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headline
                sportChips
                PersonalRecordsView(activities: filtered, sport: sport)
                if sport == .cycling {
                    TrainingProgramView(activities: filtered)
                }
                if filtered.isEmpty {
                    emptyMessage
                }
            }
            .padding(16)
        }
        .background(AppColors.cream)
        .navigationTitle("Performances")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !didSeed {
                // Map the global selected sport to one of the two we
                // support here (cycling / running). Anything else
                // (hike, ski, swim…) falls back to cycling so the screen
                // has data to show.
                sport = environment.selectedSport == .running ? .running : .cycling
                didSeed = true
            }
        }
    }

    // MARK: - Header

    private var headline: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text("§ PERF").font(.system(size: 10).weight(.bold)).tracking(1.5).foregroundStyle(AppColors.terra)
                Rectangle().fill(AppColors.creamBorder).frame(width: 20, height: 1)
                Text("PERFORMANCES").font(.system(size: 10).weight(.bold)).tracking(1.5).foregroundStyle(AppColors.inkMid)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Tes records.")
                    .font(.system(.title, design: .serif).weight(.heavy))
                    .foregroundStyle(AppColors.ink)
                Text("Et ta charge.")
                    .font(.system(.title, design: .serif).weight(.bold).italic())
                    .foregroundStyle(AppColors.terra)
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Sport chip selector (cycling / running)

    private var sportChips: some View {
        HStack(spacing: 8) {
            chip(label: "Vélo", symbol: "bicycle", active: sport == .cycling) { sport = .cycling }
            chip(label: "Course", symbol: "figure.run", active: sport == .running) { sport = .running }
            Spacer(minLength: 0)
        }
    }

    private func chip(label: String, symbol: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 11))
                Text(label).font(.system(size: 12).weight(active ? .bold : .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(active ? AppColors.terra : AppColors.surface))
            .overlay(Capsule().stroke(AppColors.creamBorder, lineWidth: 1))
            .foregroundStyle(active ? Color.white : AppColors.inkMid)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty state

    private var emptyMessage: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 32))
                .foregroundStyle(AppColors.inkLight)
            Text("Pas encore de sortie \(sport == .cycling ? "vélo" : "course") enregistrée.")
                .font(.system(size: 12))
                .foregroundStyle(AppColors.inkLight)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    // MARK: - Helpers

    /// Activity → matches(sport) — matches what the Feed does so the
    /// filtered list reads consistently between the two screens.
    private func matches(sport: Sport, activity: RideRecord) -> Bool {
        switch sport {
        case .cycling: return activity.type == "cycling"
        case .running: return activity.type == "running"
        default:       return false
        }
    }
}
