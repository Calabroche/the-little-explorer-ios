import Foundation

/// Build a GPX 1.1 document from a recorded RideRecord, with `<time>`
/// stamps on each track point so Strava's upload pipeline can reconstruct
/// pace + segments correctly.
///
/// Different from `GpxBuilder.build(...)` which is itineraries-only
/// (no per-point timestamps, no extension fields). This variant is
/// what we hand to `/api/strava/upload-activity`.
enum RideGpxBuilder {
    static func build(_ record: RideRecord) -> String {
        let startDate = parseStartDate(record.rawDate) ?? Date()
        let gps = record.gps
        let altitudes = record.altitude ?? []
        let timeS = record.timeS ?? []
        let heartrate = record.heartrate ?? []

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let metadataTime = isoFormatter.string(from: startDate)

        let trkpts: String = gps.enumerated().map { i, p -> String in
            // Walk timestamps from timeS if available, otherwise fall
            // back to evenly-spaced samples across the ride duration.
            let timestamp: Date
            if timeS.indices.contains(i) {
                timestamp = startDate.addingTimeInterval(timeS[i])
            } else {
                let pct = Double(i) / Double(max(gps.count - 1, 1))
                let totalSec = TimeInterval(record.durationMin) * 60
                timestamp = startDate.addingTimeInterval(pct * totalSec)
            }
            let timeStr = isoFormatter.string(from: timestamp)

            var inner = "\n      <time>\(timeStr)</time>"
            if altitudes.indices.contains(i) {
                inner += "\n      <ele>\(format(altitudes[i]))</ele>"
            }
            if heartrate.indices.contains(i), heartrate[i] > 0 {
                inner += hrExtension(bpm: Int(heartrate[i]))
            }
            return "    <trkpt lat=\"\(format(p.lat))\" lon=\"\(format(p.lng))\">\(inner)\n    </trkpt>"
        }.joined(separator: "\n")

        let title = esc(record.title)
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="The Little Explorer"
             xmlns="http://www.topografix.com/GPX/1/1"
             xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
             xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1"
             xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd">
          <metadata>
            <name>\(title)</name>
            <time>\(metadataTime)</time>
          </metadata>
          <trk>
            <name>\(title)</name>
            <trkseg>
        \(trkpts)
            </trkseg>
          </trk>
        </gpx>

        """
    }

    /// Garmin/Strava-compatible HR extension on a trkpt. Strava reads
    /// these and shows the HR chart on the uploaded ride.
    private static func hrExtension(bpm: Int) -> String {
        """

              <extensions>
                <gpxtpx:TrackPointExtension>
                  <gpxtpx:hr>\(bpm)</gpxtpx:hr>
                </gpxtpx:TrackPointExtension>
              </extensions>
        """
    }

    private static func parseStartDate(_ raw: String) -> Date? {
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: raw) { return d }
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        return f2.date(from: raw)
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.6f", value)
    }

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&",  with: "&amp;")
            .replacingOccurrences(of: "<",  with: "&lt;")
            .replacingOccurrences(of: ">",  with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'",  with: "&apos;")
    }
}
