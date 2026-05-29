import Foundation

/// A ride recorded standalone on the Apple Watch, buffered locally
/// until the iPhone is reachable (then sent over WCSession in Phase 2).
///
/// Schema is intentionally minimal — just enough for the iPhone to
/// reconstruct a `RideRecord` and feed the rest of the app:
///   • id        — negative-timestamp convention (same as iOS local
///                 rides) so it can never collide with a Strava id.
///   • date      — ISO 8601 start time.
///   • duration  — total elapsed seconds.
///   • gps       — sampled coordinates (one per second when GPS fix
///                 holds; sparser when in tunnels / urban canyons).
///   • timeS     — relative seconds-from-start for each gps point
///                 (same length as gps).
///   • altitude  — meters above sea level per point (same length).
///   • heartrate — average per second (length matches gps when HR
///                 sensor was active; empty otherwise).
///   • distanceM — total ride distance in meters (computed from gps).
///   • sport     — fixed "cycling" for v1; could open up later.
struct PendingRide: Codable, Identifiable, Hashable, Sendable {
    let id: Int64
    let date: String
    let durationSeconds: Double
    let gps: [Coordinate]
    let timeS: [Double]
    let altitude: [Double]
    let heartrate: [Double]
    let distanceM: Double
    let sport: String
    /// Set when the rider picked a planned itinerary on the Watch
    /// before starting. Lets the iPhone correlate the ride to the
    /// route (and eventually surface "% completion" / deviation
    /// stats in Phase D).
    let itineraryId: String?
}
