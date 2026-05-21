import SwiftUI

/// Tabbed planner hub — mirrors the web's `PlannerPage` which consolidates
/// Itinéraire + Plan + Auto + Suggestions into a single page (web commit
/// c42303d). Itinéraire is the default tab and is fully implemented; the
/// other three are stubbed for now and will be ported in follow-up work.
struct PlannerHubView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case itineraire, plan, auto, proposals
        var id: String { rawValue }

        var label: String {
            switch self {
            case .itineraire: return "Itinéraire"
            case .plan: return "Plan"
            case .auto: return "Auto"
            case .proposals: return "Suggestions"
            }
        }

        var symbol: String {
            switch self {
            case .itineraire: return "point.topleft.down.to.point.bottomright.curvepath"
            case .plan: return "sparkles"
            case .auto: return "arrow.triangle.2.circlepath"
            case .proposals: return "star"
            }
        }
    }

    @State private var selected: Tab = .itineraire

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            content
        }
        .background(AppColors.cream)
    }

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Tab.allCases) { tab in
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

    @ViewBuilder
    private var content: some View {
        switch selected {
        case .itineraire:
            ItineraryView()
        case .plan:
            NavigationStack {
                TrainingPlanView()
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
}

