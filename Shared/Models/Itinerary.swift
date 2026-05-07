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
