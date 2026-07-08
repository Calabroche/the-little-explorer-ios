import Foundation
import Observation

enum AppTab: Hashable, CaseIterable, Sendable {
    case feed, social, track, itinerary, analytics, profile
}

/// Shared cross-tab router. Owns:
///  - which tab is selected (used by RootView's TabView binding)
///  - a counter that the Feed listens to so a "go home" action can
///    both switch tabs and scroll the Feed to the top
@Observable
final class AppRouter {
    var selectedTab: AppTab = .feed
    /// Incremented on every goHome() so the Feed's ScrollViewReader
    /// fires .onChange and scrolls back to top — even if the user was
    /// already on the Feed tab.
    var feedScrollTrigger: Int = 0

    /// Tapping the brand wordmark always lands on Activités, scrolled
    /// all the way to the top.
    func goHome() {
        selectedTab = .feed
        feedScrollTrigger += 1
    }
}
