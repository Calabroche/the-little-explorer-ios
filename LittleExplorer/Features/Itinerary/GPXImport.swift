import Foundation

/// Minimal GPX reader → `Itinerary`. Handles the common shapes exported by
/// Komoot / Strava / Garmin: a `<trk>` track (the geometry, with optional
/// `<ele>`), and/or `<rte>`/`<wpt>` points we use as waypoints. Built on
/// Foundation's XMLParser so there's no dependency.
enum GPXImport {

    /// Parse GPX bytes into an Itinerary, or nil if there's no usable track.
    static func itinerary(from data: Data) -> Itinerary? {
        let parser = GPXParser()
        guard parser.run(data: data) else { return nil }

        // Geometry: prefer the track; fall back to route points.
        var raw: [Coordinate] = parser.trackPoints.map { Coordinate(lat: $0.lat, lng: $0.lng) }
        var rawEle: [Double?] = parser.trackPoints.map(\.ele)
        if raw.count < 2 {
            raw = parser.routePoints.map { Coordinate(lat: $0.lat, lng: $0.lng) }
            rawEle = Array(repeating: nil, count: raw.count)
        }
        guard raw.count >= 2 else { return nil }

        // Cap stored geometry so backend upload + Watch sync stay small.
        let geometry: [Coordinate]
        let ele: [Double?]
        if raw.count > 2000 {
            let (g, idx) = GeoMath.downsampleByDistance(raw, n: 2000)
            geometry = g
            ele = idx.map { rawEle[$0] }
        } else {
            geometry = raw
            ele = rawEle
        }

        // Distance.
        var distM = 0.0
        for i in 1..<geometry.count { distM += GeoMath.haversine(geometry[i - 1], geometry[i]) }
        let distKm = (distM / 1000 * 10).rounded() / 10
        guard distKm > 0 else { return nil }

        // Elevation profile (downsampled to ~80, sanitised) — only if the
        // GPX actually carried elevation data.
        let (_, indices) = GeoMath.downsampleByDistance(geometry, n: 80)
        let sampled = indices.map { ele[$0] ?? 0 }
        let hasEle = sampled.contains { $0 > 0 }
        let cleanEle = hasEle ? GeoMath.sanitizeElevations(sampled) : []
        let stats = cleanEle.isEmpty ? (ascent: 0, descent: 0) : GeoMath.ascentDescent(cleanEle)

        // Waypoints: route/way points if present, else synthesise start+end.
        var waypoints: [Waypoint]
        if parser.routePoints.count >= 2 {
            waypoints = parser.routePoints.enumerated().map { i, p in
                Waypoint(name: p.name ?? "Point \(i + 1)", code: "gpx-\(i)", postal: nil,
                         lat: p.lat, lng: p.lng, label: nil, city: nil, kind: nil)
            }
        } else {
            let s = geometry.first!, e = geometry.last!
            let closed = GeoMath.haversine(s, e) < 100
            waypoints = [
                Waypoint(name: "Départ", code: "gpx-start", postal: nil, lat: s.lat, lng: s.lng, label: nil, city: nil, kind: nil),
            ]
            if !closed {
                waypoints.append(Waypoint(name: "Arrivée", code: "gpx-end", postal: nil, lat: e.lat, lng: e.lng, label: nil, city: nil, kind: nil))
            }
        }

        let loop = GeoMath.haversine(geometry.first!, geometry.last!) < 100
        // No timing in a planned-route GPX — estimate at a steady ~18 km/h.
        let durMin = Int((distKm / 18 * 60).rounded())

        return Itinerary(
            id: Itinerary.newId(),
            name: parser.name ?? "Itinéraire importé",
            createdAt: Date(),
            waypoints: waypoints,
            targetKm: distKm,
            loop: loop,
            distanceKm: distKm,
            durationMin: durMin,
            geometry: geometry,
            steps: nil,
            elevSampleIndices: cleanEle.isEmpty ? nil : indices,
            elevations: cleanEle.isEmpty ? nil : cleanEle,
            totalAscent: stats.ascent > 0 ? stats.ascent : nil,
            totalDescent: stats.descent > 0 ? stats.descent : nil,
        )
    }
}

// MARK: - XML parser

private final class GPXParser: NSObject, XMLParserDelegate {
    struct TrackPoint { let lat: Double; let lng: Double; var ele: Double? }
    struct RoutePoint { let lat: Double; let lng: Double; let name: String? }

    private(set) var trackPoints: [TrackPoint] = []
    private(set) var routePoints: [RoutePoint] = []
    private(set) var name: String?

    private var stack: [String] = []
    private var lat = 0.0, lng = 0.0
    private var eleText = ""
    private var nameText = ""

    func run(data: Data) -> Bool {
        let p = XMLParser(data: data)
        p.delegate = self
        return p.parse() && (!trackPoints.isEmpty || !routePoints.isEmpty)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let name = local(elementName)
        stack.append(name)
        switch name {
        case "trkpt", "rtept", "wpt":
            lat = Double(attributeDict["lat"] ?? "") ?? 0
            lng = Double(attributeDict["lon"] ?? "") ?? 0
            eleText = ""; nameText = ""
        case "ele": eleText = ""
        case "name": nameText = ""
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        switch stack.last {
        case "ele":  eleText  += string
        case "name": nameText += string
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        let name = local(elementName)
        let parent = stack.count >= 2 ? stack[stack.count - 2] : ""
        switch name {
        case "trkpt":
            trackPoints.append(TrackPoint(lat: lat, lng: lng, ele: Double(eleText.trimmingCharacters(in: .whitespacesAndNewlines))))
        case "rtept", "wpt":
            let n = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
            routePoints.append(RoutePoint(lat: lat, lng: lng, name: n.isEmpty ? nil : n))
        case "name":
            // A <name> directly under trk / rte / metadata is the route's name.
            if self.name == nil, ["trk", "rte", "metadata"].contains(parent) {
                let n = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !n.isEmpty { self.name = n }
            }
        default: break
        }
        if !stack.isEmpty { stack.removeLast() }
    }

    /// Strip any namespace prefix (e.g. "gpx:trkpt" → "trkpt").
    private func local(_ s: String) -> String {
        if let i = s.firstIndex(of: ":") { return String(s[s.index(after: i)...]) }
        return s
    }
}
