import SwiftUI

@main
struct LittleExplorerApp: App {
    @State private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
        }
    }
}
