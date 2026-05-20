import SwiftUI

/// App root. Gates on auth: if there's no token in SessionStore (= user
/// hasn't signed in yet) we show LoginView. Once a token is present we
/// render the real tab bar.
///
/// Token-aware: whenever SessionStore.token changes we push it into
/// APIClient so all subsequent requests carry the Bearer header.
struct RootView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var router = AppRouter()

    var body: some View {
        Group {
            if environment.session.isAuthenticated {
                authenticatedRoot
            } else {
                LoginView()
            }
        }
        // Keep APIClient's auth token in sync with the session. We
        // hop to the actor inside Task so the actor's state mutation
        // stays cleanly serialized.
        .task(id: environment.session.token) {
            let token = environment.session.token
            await environment.api.setAuthToken(token)
            if token != nil {
                // First request right after sign-in: fetch the profile
                // so the UI has something to render (avatar, name).
                do {
                    let profile = try await environment.api.me()
                    environment.session.profile = profile
                } catch {
                    // If the token's already invalid, kick back to login.
                    if case APIError.unauthorized = error {
                        environment.session.clear()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var authenticatedRoot: some View {
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
