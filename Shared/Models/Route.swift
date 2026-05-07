import CoreLocation
import Foundation

/// Response from POST /api/route-bike (when steps:true).
struct BikeRoute: Codable, Hashable {
    let distance: Double
    let duration: Double
    let geometry: [Coordinate]
    let steps: [NavStep]?
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
