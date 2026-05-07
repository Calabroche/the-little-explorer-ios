import SwiftUI

struct RootView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        TabView {
            ActivitiesListView()
                .tabItem { Label("Activities", systemImage: "list.bullet") }

            RideTrackerView()
                .tabItem { Label("Track", systemImage: "record.circle") }

            PlannerView()
                .tabItem { Label("Plan", systemImage: "map") }

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
    }
}

#Preview {
    RootView()
        .environment(AppEnvironment())
}
