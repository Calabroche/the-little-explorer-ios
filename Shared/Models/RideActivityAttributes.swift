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
    }

    public var sportLabel: String
    public var startedAt: Date
}
#endif
