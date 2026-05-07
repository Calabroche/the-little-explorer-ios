import SwiftUI

struct RootView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var router = AppRouter()

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.selectedTab) {
            FeedView()
                .tabItem { Label("Activités", systemImage: "list.bullet") }
                .tag(AppTab.feed)

            RideTrackerView()
                .tabItem { Label("Track", systemImage: "record.circle") }
                .tag(AppTab.track)

            ItineraryView()
                .tabItem { Label("Itinéraire", systemImage: "map") }
                .tag(AppTab.itinerary)

            AnalyticsHubView()
                .tabItem { Label("Analyses", systemImage: "chart.bar.xaxis") }
                .tag(AppTab.analytics)

            ProfileView()
                .tabItem { Label("Profil", systemImage: "person.crop.circle") }
                .tag(AppTab.profile)
        }
        .environment(router)
    }
}

#Preview {
    RootView()
        .environment(AppEnvironment())
}
