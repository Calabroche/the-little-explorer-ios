import Foundation

/// One stop on a planned tour. Mirrors the web app's `Waypoint`.
struct Waypoint: Codable, Hashable, Identifiable {
    let name: String
    let code: String          // INSEE commune code (used as id and dedup key)
    var postal: String?
    let lat: Double
    let lng: Double
    /// Full human-readable address from BAN ("12 Chemin du Manoir 69570 Dardilly").
    var label: String?
    /// Commune name — only differs from `name` for street/housenumber results.
    var city: String?
    /// What kind of place this is — drives the icon in the search list.
    var kind: PlaceKind?

    var id: String { code + "-" + (label ?? name) }
    var coordinate: Coordinate { Coordinate(lat: lat, lng: lng) }

    enum PlaceKind: String, Codable, Hashable {
        case housenumber, street, locality, municipality
    }
}

// NOTE: The OSRM-step type `NavStep` already lives in Route.swift —
// reused here so we don't fork the model. Its `start` is a Coordinate
// (not a [Double] pair), so call-sites can read it directly without
// re-packing.

/// A saved tour: ordered waypoints + target km + cached routing.
struct Itinerary: Codable, Hashable, Identifiable {
    let id: String
    var name: String
    var createdAt: Date
    var waypoints: [Waypoint]
    var targetKm: Double
    var loop: Bool
    // Cached routing result.
    var distanceKm: Double?
    var durationMin: Int?
    var geometry: [Coordinate]?
    /// Turn-by-turn maneuvers used by the Watch's voice nav. Optional
    /// because itineraries saved before the field existed won't have
    /// it — the Watch falls back to silent map guidance in that case.
    var steps: [NavStep]?
    // Cached elevation profile.
    var elevSampleIndices: [Int]?
    var elevations: [Double]?
    var totalAscent: Int?
    var totalDescent: Int?

    static func newId() -> String {
        let ts = Int(Date().timeIntervalSince1970 * 1000)
        let rand = UUID().uuidString.split(separator: "-").first ?? ""
        return "itin_\(ts)_\(rand)"
    }
}

// MARK: - Wire format (shared with the web)

/// Custom Codable so the JSON payload matches the web app's Itinerary
/// exactly — same `/api/itineraries` record is read by both. Two fields
/// would otherwise diverge:
///   • geometry — the web stores `[[lat, lng]]` pairs; Swift's default
///     Codable would write `[{ "lat":…, "lng":… }]`.
///   • createdAt — the web stores an ISO-8601 string; Swift's default
///     would write a number.
/// Decoding tolerates both shapes so itineraries saved by older builds
/// (object geometry / numeric date) still load.
extension Itinerary {
    enum CodingKeys: String, CodingKey {
        case id, name, createdAt, waypoints, targetKm, loop, distanceKm
        case durationMin, geometry, steps, elevSampleIndices, elevations
        case totalAscent, totalDescent
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id          = try c.decode(String.self, forKey: .id)
        name        = try c.decode(String.self, forKey: .name)
        createdAt   = Itinerary.decodeDate(c)
        waypoints   = try c.decode([Waypoint].self, forKey: .waypoints)
        targetKm    = try c.decode(Double.self, forKey: .targetKm)
        loop        = try c.decodeIfPresent(Bool.self, forKey: .loop) ?? false
        distanceKm  = try c.decodeIfPresent(Double.self, forKey: .distanceKm)
        durationMin = try c.decodeIfPresent(Int.self, forKey: .durationMin)
        geometry    = Itinerary.decodeGeometry(c)
        steps       = try c.decodeIfPresent([NavStep].self, forKey: .steps)
        elevSampleIndices = try c.decodeIfPresent([Int].self, forKey: .elevSampleIndices)
        elevations  = try c.decodeIfPresent([Double].self, forKey: .elevations)
        totalAscent = try c.decodeIfPresent(Int.self, forKey: .totalAscent)
        totalDescent = try c.decodeIfPresent(Int.self, forKey: .totalDescent)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(Itinerary.isoOut.string(from: createdAt), forKey: .createdAt)
        try c.encode(waypoints, forKey: .waypoints)
        try c.encode(targetKm, forKey: .targetKm)
        try c.encode(loop, forKey: .loop)
        try c.encodeIfPresent(distanceKm, forKey: .distanceKm)
        try c.encodeIfPresent(durationMin, forKey: .durationMin)
        try c.encodeIfPresent(geometry?.map { [$0.lat, $0.lng] }, forKey: .geometry)
        try c.encodeIfPresent(steps, forKey: .steps)
        try c.encodeIfPresent(elevSampleIndices, forKey: .elevSampleIndices)
        try c.encodeIfPresent(elevations, forKey: .elevations)
        try c.encodeIfPresent(totalAscent, forKey: .totalAscent)
        try c.encodeIfPresent(totalDescent, forKey: .totalDescent)
    }

    // [[lat,lng]] (canonical / web) or [{lat,lng}] (legacy iOS).
    private static func decodeGeometry(_ c: KeyedDecodingContainer<CodingKeys>) -> [Coordinate]? {
        if let pairs = try? c.decode([[Double]].self, forKey: .geometry) {
            return pairs.compactMap { $0.count >= 2 ? Coordinate(lat: $0[0], lng: $0[1]) : nil }
        }
        return try? c.decode([Coordinate].self, forKey: .geometry)
    }

    // ISO-8601 string (canonical / web) or number (legacy iOS).
    private static func decodeDate(_ c: KeyedDecodingContainer<CodingKeys>) -> Date {
        if let s = try? c.decode(String.self, forKey: .createdAt) {
            if let d = isoFrac.date(from: s) { return d }
            if let d = isoPlain.date(from: s) { return d }
        }
        if let n = try? c.decode(Double.self, forKey: .createdAt) {
            return Date(timeIntervalSinceReferenceDate: n)
        }
        return Date()
    }

    private static let isoOut: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()
}

extension CommuneResult {
    /// Convert a search result into a Waypoint.
    func toWaypoint() -> Waypoint {
        Waypoint(
            name: name,
            code: code,
            postal: postal,
            lat: lat,
            lng: lng,
            label: label,
            city: nil,
            kind: kind.flatMap(Waypoint.PlaceKind.init(rawValue:)),
        )
    }
}

/// A saved favorite place (itinerary start point), synced via /api/me/places.
struct FavoritePlace: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    var label: String?
    var code: String?
    var postal: String?
    var city: String?
    var kind: String?
    let lat: Double
    let lng: Double

    func toWaypoint() -> Waypoint {
        Waypoint(name: name, code: code ?? id, postal: postal, lat: lat, lng: lng,
                 label: label, city: city, kind: kind.flatMap(Waypoint.PlaceKind.init(rawValue:)))
    }
}
