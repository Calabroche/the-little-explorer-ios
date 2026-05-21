import CoreLocation
import Foundation

/// Response from POST /api/route-bike. The server returns:
///   {
///     distance_m: number,
///     duration_s: number,
///     geometry:   [[lat, lng], ...],
///     steps?:     [{ start: [lat, lng], type, modifier, exit, name, distance, duration }, ...]
///   }
///
/// We decode it into a Swift-friendly shape where `geometry` and
/// `steps[].start` are real Coordinate values rather than raw number
/// pairs.
struct BikeRoute: Codable, Hashable {
    /// Total route distance in meters.
    let distance: Double
    /// Total route duration in seconds.
    let duration: Double
    /// Decoded polyline as Coordinate values.
    let geometry: [Coordinate]
    /// Turn-by-turn maneuvers, only present when the request asked for
    /// `steps: true`.
    let steps: [NavStep]?

    enum CodingKeys: String, CodingKey {
        case distance = "distance_m"
        case duration = "duration_s"
        case geometry
        case steps
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        distance = try c.decode(Double.self, forKey: .distance)
        duration = try c.decode(Double.self, forKey: .duration)
        let rawGeo = try c.decode([[Double]].self, forKey: .geometry)
        geometry = rawGeo.compactMap { pair in
            guard pair.count >= 2 else { return nil }
            return Coordinate(lat: pair[0], lng: pair[1])
        }
        steps = try c.decodeIfPresent([NavStep].self, forKey: .steps)
    }

    /// Manual encoder kept for symmetry — not used by the API client but
    /// lets the struct stay Codable for SwiftUI navigation values.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(distance, forKey: .distance)
        try c.encode(duration, forKey: .duration)
        try c.encode(geometry.map { [$0.lat, $0.lng] }, forKey: .geometry)
        try c.encodeIfPresent(steps, forKey: .steps)
    }
}

struct NavStep: Codable, Hashable, Identifiable {
    var id: Int { hashValue }
    let start: Coordinate
    let type: String
    let modifier: String
    let exit: Int?
    let name: String
    let distance: Double
    let duration: Double

    enum CodingKeys: String, CodingKey {
        case start, type, modifier, exit, name, distance, duration
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let pair = try c.decode([Double].self, forKey: .start)
        guard pair.count >= 2 else {
            throw DecodingError.dataCorruptedError(forKey: .start, in: c, debugDescription: "expected [lat, lng]")
        }
        start    = Coordinate(lat: pair[0], lng: pair[1])
        type     = try c.decode(String.self, forKey: .type)
        modifier = try c.decode(String.self, forKey: .modifier)
        exit     = try c.decodeIfPresent(Int.self, forKey: .exit)
        name     = try c.decode(String.self, forKey: .name)
        distance = try c.decode(Double.self, forKey: .distance)
        duration = try c.decode(Double.self, forKey: .duration)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode([start.lat, start.lng], forKey: .start)
        try c.encode(type, forKey: .type)
        try c.encode(modifier, forKey: .modifier)
        try c.encodeIfPresent(exit, forKey: .exit)
        try c.encode(name, forKey: .name)
        try c.encode(distance, forKey: .distance)
        try c.encode(duration, forKey: .duration)
    }

    /// Maneuver icon (SF Symbol).
    var maneuverSymbol: String {
        switch (type, modifier) {
        case ("turn", "left"), ("end of road", "left"): return "arrow.turn.up.left"
        case ("turn", "right"), ("end of road", "right"): return "arrow.turn.up.right"
        case ("turn", "sharp left"): return "arrow.uturn.left"
        case ("turn", "sharp right"): return "arrow.uturn.right"
        case ("turn", "slight left"): return "arrow.up.left"
        case ("turn", "slight right"): return "arrow.up.right"
        case ("roundabout", _), ("rotary", _): return "arrow.triangle.2.circlepath"
        case ("arrive", _): return "checkmark.circle.fill"
        case ("depart", _): return "location.fill"
        case ("merge", _): return "arrow.triangle.merge"
        case ("fork", _): return "arrow.triangle.branch"
        default: return "arrow.up"
        }
    }
}

/// Response from /api/commune-search.
struct CommuneResult: Codable, Hashable, Identifiable {
    let name: String
    let code: String
    let postal: String?
    let lat: Double
    let lng: Double
    let label: String?
    let kind: String?

    var id: String { code + (label ?? name) }
    var coordinate: Coordinate { Coordinate(lat: lat, lng: lng) }
}
