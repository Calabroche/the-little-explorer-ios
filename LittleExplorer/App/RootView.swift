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
    /// Drives the one-time welcome cover. Set true on first appearance of
    /// the authenticated UI when `hasSeenWelcome` is still false.
    @State private var showWelcome = false

    var body: some View {
        ZStack {
            Group {
                if environment.session.isAuthenticated {
                    authenticatedRoot
                } else {
                    LoginView()
                }
            }
        }
        // Best-effort stale Live Activity cleanup. Runs once after the
        // scene has rendered so a misbehaving ActivityKit call can't
        // prevent the UI from appearing on launch.
        .task {
            await environment.endStaleLiveActivities()
        }
        // Keep APIClient's auth token in sync with the session. We
        // hop to the actor inside Task so the actor's state mutation
        // stays cleanly serialized.
        .task(id: environment.session.token) {
            let token = environment.session.token
            await environment.api.setAuthToken(token)
            if token != nil {
                // Now that the bearer token is set, start pulling workouts from
                // Apple Health into the back-end (Strava-independent ingestion).
                environment.startHealthKitSync()
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
            // Home = the social feed (activities from people you follow),
            // Strava-style. Search + your own data live elsewhere now.
            SocialFeedView()
                .tabItem { Label("Accueil", systemImage: "house") }
                .tag(AppTab.feed)

            RideTrackerView()
                .tabItem { Label("Track", systemImage: "record.circle") }
                .tag(AppTab.track)

            PlannerHubView()
                .tabItem { Label("Planificateur", systemImage: "map") }
                .tag(AppTab.itinerary)

            AnalyticsHubView()
                .tabItem { Label("Analyses", systemImage: "chart.bar.xaxis") }
                .tag(AppTab.analytics)

            // Profil = your data: follower/following counts + all your
            // activities with the heatmap (FeedView is your dashboard).
            FeedView()
                .tabItem { Label("Profil", systemImage: "person.crop.circle") }
                .tag(AppTab.profile)
        }
        .environment(router)
        // First time a signed-in user reaches the tab bar, greet them
        // with the welcome screen (+ link to the full guide). Read the
        // persisted flag imperatively here; the cover itself is driven by
        // local @State so it dismisses cleanly on "Commencer".
        .onAppear {
            if !environment.hasSeenWelcome { showWelcome = true }
        }
        .fullScreenCover(isPresented: $showWelcome) {
            WelcomeView {
                environment.hasSeenWelcome = true
                showWelcome = false
            }
        }
    }
}

#Preview {
    RootView()
        .environment(AppEnvironment())
}
