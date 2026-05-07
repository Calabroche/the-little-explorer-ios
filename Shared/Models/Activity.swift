import Foundation

struct Activity: Codable, Identifiable, Hashable {
    let id: String
    let type: String
    let originalType: String?
    let title: String
    let date: String
    let rawDate: String
    let location: String?
    let duration: String
    let durationMin: Double
    let distance: Double?
    let speed: Double?
    let maxSpeed: Double?
    let elevation: Double?
    let descent: Double?
    let gps: [Coordinate]
    let altitude: [Double]?
    let speedKmh: [Double]?
    let heartrate: [Double]?
    let distanceM: [Double]?
    let timeS: [Double]?
    let maxIncline: Double?
    let minIncline: Double?
    let avgHr: Int?
    let maxHr: Int?
    let calories: Int?
    let np: Int?
    let avgPower: Int?
    let tss: Int?
    let ifFactor: Double?
    let vi: Double?
    let wkg: Double?
    let ef: Double?
    let trimp: Int?
    let vam: Double?
    let ftp: Int?
    let weather: Weather?

    enum CodingKeys: String, CodingKey {
        case id, type, title, date, location, duration, distance, speed, elevation, descent, gps, altitude, heartrate, calories, np, tss, vi, wkg, ef, trimp, vam, ftp, weather
        case originalType = "original_type"
        case rawDate = "rawDate"
        case durationMin = "duration_min"
        case maxSpeed = "max_speed"
        case speedKmh = "speed_kmh"
        case distanceM = "distance_m"
        case timeS = "time_s"
        case maxIncline = "max_incline"
        case minIncline = "min_incline"
        case avgHr = "avg_hr"
        case maxHr = "max_hr"
        case avgPower = "avg_power"
        case ifFactor = "if_factor"
    }
}

struct Weather: Codable, Hashable {
    let temp: Double?
    let condition: String?
    let icon: String?
    let windSpeed: Double?
    let humidity: Int?

    enum CodingKeys: String, CodingKey {
        case temp, condition, icon, humidity
        case windSpeed = "wind_speed"
    }
}

extension Activity {
    /// Sport icon (SF Symbol).
    var sportSymbol: String {
        switch type.lowercased() {
        case "ride", "cycling", "bike", "ebikeride": return "bicycle"
        case "run", "running": return "figure.run"
        case "walk", "hike", "hiking": return "figure.walk"
        default: return "mappin.and.ellipse"
        }
    }
}
