#if canImport(ActivityKit)
import ActivityKit
import Foundation

/// Live Activity payload for an in-progress ride.
/// Shared between the iOS app (which starts/updates the activity) and
/// the widget extension (which renders it on the Lock Screen / Dynamic Island).
/// Not available on watchOS — ActivityKit is iOS-only.
struct RideActivityAttributes: ActivityAttributes {
    public typealias ContentState = RideState

    public struct RideState: Codable, Hashable {
        var distanceKm: Double
        var durationSec: Double
        var speedKmh: Double
        var elevationGainM: Double
        var heartRate: Int?
        var nextManeuver: String?
        var nextManeuverDistanceM: Double?
        var nextManeuverSymbol: String?
        /// Current user position (mutable, ~16 bytes — cheap to push).
        /// The widget centers its map here.
        var userLat: Double?
        var userLng: Double?
    }

    public var sportLabel: String
    public var startedAt: Date
    /// Route polyline for the lock-screen Map view. Set ONCE at start
    /// (the route doesn't change during navigation) and kept small —
    /// the source publisher downsamples to ≤100 points so the whole
    /// activity payload stays under the 4KB ContentState budget.
    /// Stored as flat [[lat, lng], …] doubles instead of nested
    /// structs so the on-the-wire encoding is tighter.
    public var routePolyline: [[Double]]?
}
#endif
