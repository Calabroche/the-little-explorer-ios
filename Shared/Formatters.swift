import Foundation

enum RideFormatter {
    static func distance(_ meters: Double) -> String {
        if meters < 1000 { return "\(Int(meters)) m" }
        return String(format: "%.2f km", meters / 1000)
    }

    static func duration(_ seconds: Double) -> String {
        let s = Int(seconds)
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, sec)
            : String(format: "%d:%02d", m, sec)
    }

    static func speed(_ kmh: Double) -> String {
        String(format: "%.1f km/h", kmh)
    }

    static func elevation(_ meters: Double) -> String {
        "\(Int(meters)) m"
    }
}
