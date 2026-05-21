import Foundation
import os

/// App-wide logging facade. Wraps `os.Logger` so messages go to the
/// system's unified log (visible in Console.app + Xcode), AND so the
/// in-app DiagnosticsView can read them back via OSLogStore.
///
/// Use the category constants below (one per subsystem) rather than
/// creating arbitrary ones — keeps the diagnostics filter useful.
///
/// Example:
///   Log.api.error("activities fetch failed: \(error.localizedDescription, privacy: .public)")
///   Log.nav.info("started navigation, \(steps.count) steps")
enum Log {
    static let subsystem = "com.calabrese.little-explorer-ios"

    static let api      = Logger(subsystem: subsystem, category: "api")
    static let nav      = Logger(subsystem: subsystem, category: "nav")
    static let tracking = Logger(subsystem: subsystem, category: "tracking")
    static let auth     = Logger(subsystem: subsystem, category: "auth")
    static let sync     = Logger(subsystem: subsystem, category: "sync")
    static let watch    = Logger(subsystem: subsystem, category: "watch")
    static let ui       = Logger(subsystem: subsystem, category: "ui")
    static let app      = Logger(subsystem: subsystem, category: "app")

    /// All categories — exposed so the diagnostics view can offer a
    /// "this category only" filter chip bar.
    static let allCategories: [String] = [
        "api", "nav", "tracking", "auth", "sync", "watch", "ui", "app",
    ]
}
