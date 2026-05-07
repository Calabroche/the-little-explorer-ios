import SwiftUI

struct RootView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        TabView {
            FeedView()
                .tabItem { Label("Activités", systemImage: "list.bullet") }

            RideTrackerView()
                .tabItem { Label("Track", systemImage: "record.circle") }

            ItineraryView()
                .tabItem { Label("Itinéraire", systemImage: "map") }

            AnalyticsHubView()
                .tabItem { Label("Analyses", systemImage: "chart.bar.xaxis") }

            ProfileView()
                .tabItem { Label("Profil", systemImage: "person.crop.circle") }
        }
    }
}

#Preview {
    RootView()
        .environment(AppEnvironment())
}
