import SwiftUI

/// Tabbed planner hub. Top-level picker chooses the SPORT CATEGORY
/// (Vélo / Course), then the second-level tab bar only shows the
/// sub-features that make sense for that sport:
///
///   Vélo:    Itinéraire + Plan + Auto + Suggestions  (the full menu)
///   Course:  Itinéraire + Plan                       (no cycling-route library)
///
/// Snow / Water / Indoor categories exist on the Track recorder but
/// were intentionally removed from the planner — generating a 12-week
/// progression for yoga or pool laps wasn't pulling its weight. The
/// SportCategory enum still has those cases for the Track picker; we
/// just don't expose them here.
///
/// Default category reads from `env.selectedSport` mapped to its
/// SportCategory; user can change it via the chip bar at the top
/// without affecting the global selectedSport (the planner picker
/// is local to this view).
struct PlannerHubView: View {
    /// The only categories the planner exposes. Drives the chip bar
    /// at the top — `SportCategory.allCases` would also list snow /
    /// water / indoor which we hide here.
    private static let plannerCategories: [SportCategory] = [.cycling, .footing]

    @Environment(AppEnvironment.self) private var environment

    enum Tab: String, Identifiable {
        case itineraire, plan, auto, proposals
        var id: String { rawValue }

        var label: String {
            switch self {
            case .itineraire: return "Itinéraire"
            case .plan:       return "Plan"
            case .auto:       return "Auto"
            case .proposals:  return "Suggestions"
            }
        }

        var symbol: String {
            switch self {
            case .itineraire: return "point.topleft.down.to.point.bottomright.curvepath"
            case .plan:       return "sparkles"
            case .auto:       return "arrow.triangle.2.circlepath"
            case .proposals:  return "star"
            }
        }
    }

    @State private var category: SportCategory = .cycling
    @State private var selected: Tab = .itineraire
    @State private var didSeedCategory: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            categoryBar
            tabBar
            Divider()
            content
        }
        .background(AppColors.cream)
        .onAppear {
            // Seed the planner's category once from the user's global
            // selectedSport so first-time visitors don't have to pick.
            if !didSeedCategory {
                category = category(forGlobal: environment.selectedSport)
                selected = availableTabs(for: category).first ?? .plan
                didSeedCategory = true
            }
        }
    }

    // MARK: - Top: category chips

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Self.plannerCategories) { cat in
                    let isActive = category == cat
                    Button {
                        category = cat
                        // Snap to a valid tab for the new category.
                        let tabs = availableTabs(for: cat)
                        if !tabs.contains(selected) {
                            selected = tabs.first ?? .plan
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: cat.symbol).font(.system(size: 11))
                            Text(cat.displayName).font(.system(size: 12).weight(isActive ? .bold : .medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Capsule().fill(isActive ? AppColors.terra : AppColors.surface),
                        )
                        .overlay(Capsule().stroke(AppColors.creamBorder, lineWidth: 1))
                        .foregroundStyle(isActive ? Color.white : AppColors.inkMid)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(AppColors.cream)
    }

    // MARK: - Second row: sub-feature tabs

    private var tabBar: some View {
        let tabs = availableTabs(for: category)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(tabs) { tab in
                    let isActive = selected == tab
                    Button {
                        selected = tab
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tab.symbol).font(.system(size: 12))
                            Text(tab.label).font(.system(size: 13).weight(isActive ? .bold : .medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isActive ? AppColors.terra : Color.clear),
                        )
                        .foregroundStyle(isActive ? Color.white : AppColors.inkMid)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(AppColors.creamDark)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch selected {
        case .itineraire:
            ItineraryView()
        case .plan:
            NavigationStack {
                TrainingPlanView(category: category)
            }
        case .auto:
            NavigationStack {
                RouteBuilderView()
            }
        case .proposals:
            NavigationStack {
                RouteProposalsView()
            }
        }
    }

    // MARK: - Sport → tabs mapping

    /// Which sub-features make sense for this sport category. Cycling
    /// gets the full deal because the route library + algos were
    /// built around it; running gets Itinéraire + Plan. The other
    /// SportCategory cases (snow / water / indoor) aren't reachable
    /// from the planner — see `plannerCategories` — but the switch
    /// stays exhaustive in case the enum gains a new case.
    private func availableTabs(for cat: SportCategory) -> [Tab] {
        switch cat {
        case .cycling: return [.itineraire, .plan, .auto, .proposals]
        case .footing: return [.itineraire, .plan]
        case .snow, .water, .indoor:
            // Defensive — not reachable through the chip bar.
            return [.plan]
        }
    }

    /// Map the global Sport enum to its SportCategory so the user's
    /// favorite sport lands them on the right planner section. Sports
    /// whose category was retired from the planner (ski / snowshoe /
    /// swim) fall back to cycling — they still have full UI on the
    /// Track recorder, just not in the planner.
    private func category(forGlobal sport: Sport) -> SportCategory {
        switch sport {
        case .cycling:                       return .cycling
        case .running, .walking, .hiking:    return .footing
        case .ski, .snowshoe, .swim:         return .cycling
        }
    }
}
