import Foundation

/// Build a GPX 1.1 string from a planned itinerary. Output is compatible
/// with Garmin / Wahoo / phone navigation apps.
enum GpxBuilder {
    static func build(
        name: String,
        waypoints: [Waypoint],
        polyline: [Coordinate],
        elevations: [Double]? = nil,
    ) -> String {
        let useEle = elevations.map { $0.count == polyline.count } ?? false
        let now = ISO8601DateFormatter().string(from: Date())

        let wpts = waypoints.map { w in
            let cmt = w.postal.map { "    <cmt>\(esc($0))</cmt>\n" } ?? ""
            return """
              <wpt lat="\(format(w.lat))" lon="\(format(w.lng))">
                <name>\(esc(w.name))</name>
            \(cmt)  </wpt>
            """
        }.joined(separator: "\n")

        let trkpts = polyline.enumerated().map { i, p -> String in
            let ele = useEle ? "\n      <ele>\(format(elevations![i]))</ele>" : ""
            return """
                <trkpt lat="\(format(p.lat))" lon="\(format(p.lng))">\(ele)
                </trkpt>
            """
        }.joined(separator: "\n")

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="The Little Explorer"
             xmlns="http://www.topografix.com/GPX/1/1"
             xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
             xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd">
          <metadata>
            <name>\(esc(name))</name>
            <time>\(now)</time>
          </metadata>
        \(wpts)
          <trk>
            <name>\(esc(name))</name>
            <trkseg>
        \(trkpts)
            </trkseg>
          </trk>
        </gpx>

        """
    }

    static func slugify(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive], locale: .current).lowercased()
        var out = ""
        var prevDash = false
        for ch in folded {
            if ch.isLetter || ch.isNumber {
                out.append(ch)
                prevDash = false
            } else if !prevDash, !out.isEmpty {
                out.append("-")
                prevDash = true
            }
        }
        if out.hasSuffix("-") { out.removeLast() }
        let trimmed = String(out.prefix(60))
        return trimmed.isEmpty ? "itineraire" : trimmed
    }

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.6f", value)
    }
}
