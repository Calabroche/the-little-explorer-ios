import CoreLocation
import Foundation

/// A bike shop / repairer near the rider, from OpenStreetMap via the web
/// app's `/api/bike-shops` endpoint. Mirrors the web "Trouver un
/// professionnel" feature. Field names match the JSON 1:1 (the API already
/// sends camelCase), so no CodingKeys are needed.
struct BikeShop: Decodable, Sendable, Identifiable, Hashable {
    let id: String
    let name: String
    let lat: Double
    let lng: Double
    let distKm: Double
    let address: String?
    let phone: String?
    let website: String?
    let hours: String?
    let repairs: Bool          // OSM explicitly tags repair
    let type: String           // "shop" | "repair" | "sports"
    let brandMatch: Bool        // rider's brand found in OSM tags
    let brandOnSite: Bool       // rider's brand found on the shop's website
    let brands: [String]        // all known brands found (OSM tag + website scan)

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    /// True when the shop looks like a specialist for the rider's brand,
    /// flagged either in OSM tags or found on its website. Drives the
    /// special marker colour, same as the web.
    var isSpecialist: Bool { brandMatch || brandOnSite }
}

/// Well-known bike brands offered in the "ma marque de vélo" picker. Mirrors
/// the web's `BIKE_BRANDS` (src/lib/bikeBrands.ts). Distinctive names only —
/// common-word brands (Rose, Marin, Liv…) are left out on purpose so the
/// server-side website scan doesn't get false positives.
enum BikeBrands {
    static let all: [String] = [
        "Canyon", "Specialized", "Trek", "Giant", "Cannondale", "Scott", "Cube",
        "BMC", "Bianchi", "Merida", "Orbea", "Lapierre", "Cervélo", "Pinarello",
        "Look", "Focus", "Wilier", "Colnago", "Ridley", "Santa Cruz", "Decathlon",
        "Van Rysel", "Moustache", "Riese & Müller",
        "Brompton", "Kona", "Tern", "Surly", "Haibike", "Kalkhoff", "Commencal",
        "Vitus", "Norco", "VanMoof", "Gitane", "Peugeot", "Gazelle", "Cowboy",
        "Argon 18", "Sunn", "Rockrider", "Btwin",
    ]

    /// Default the rider's brand to Canyon (Florian's bike), like the web.
    static let defaultBrand = "Canyon"
}
