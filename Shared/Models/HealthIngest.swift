import Foundation

/// Payload for POST /api/activities/ingest — a workout read from Apple
/// HealthKit, pushed to the web back-end so it lands in public.activities
/// exactly like a Strava-synced ride. Field names are snake_case to match
/// the endpoint 1:1 (the JSON encoder emits property names verbatim).
struct HealthIngestPayload: Encodable, Sendable {
    let uuid:             String        // HealthKit workout UUID (stable id)
    let type:             String        // Strava-style: Ride, Run, Hike, Walk, Swim…
    let name:             String?
    let start_date:       String        // ISO8601
    let duration_s:       Double
    let distance_m:       Double        // total distance
    let elevation_gain_m: Double
    let calories:         Double?
    let avg_hr:           Double?
    let max_hr:           Double?
    // Streams — aligned to the GPS route samples.
    let gps:              [[Double]]     // [lat, lng]
    let altitude:         [Double]
    let time_s:           [Double]       // seconds from start
    let distance_stream:  [Double]       // cumulative metres
    let heartrate:        [Double]
    let speed_kmh:        [Double]
}
