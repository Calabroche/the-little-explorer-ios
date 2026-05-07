import CoreLocation
import Foundation

struct Coordinate: Codable, Hashable, Sendable {
    let lat: Double
    let lng: Double

    var clLocation: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}
