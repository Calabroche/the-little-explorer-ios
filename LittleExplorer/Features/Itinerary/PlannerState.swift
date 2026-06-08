import Foundation
import Observation
import CoreLocation

/// Drives the Itinerary builder: waypoints, target distance, loop flag,
/// cached routing + elevation. Mirrors the web's ItineraryPage state.
@Observable
final class PlannerState {
    // Inputs
    var waypoints: [Waypoint] = []
    var targetKm: Double = 50
    var loop: Bool = false
    var name: String = ""
    var activeId: String?
    /// OSRM routing profile: "bike" (default) or "foot" (running).
    var routingProfile: String = "bike"

    // Cols / summits near the departure (cycling only).
    var colRadiusKm: Double = 25
    var cols: [APIClient.Col] = []
    var colsLoading: Bool = false

    // Cached routing result (refreshed when waypoints change).
    var geometry: [Coordinate]?
    var distanceMeters: Double?
    var durationSeconds: Double?
    var routing: Bool = false
    var routeError: String?
    var extending: Bool = false

    // Cached elevation profile.
    var elevSeries: [ElevationSample] = []
    var elevations: [Double]?
    var elevSampleIndices: [Int]?
    var ascent: Int = 0
    var descent: Int = 0
    var elevationLoading: Bool = false

    // Index in the elevation series being highlighted (drag on the chart).
    var hoverIndex: Int?

    private let api: APIClient

    private var routingTask: Task<Void, Never>?
    private var elevationTask: Task<Void, Never>?
    private var colsTask: Task<Void, Never>?
    private var colsFetchedKey = ""

    init(api: APIClient = .shared) {
        self.api = api
    }

    // MARK: - Waypoint manipulation

    func add(_ waypoint: Waypoint) {
        guard !waypoints.contains(where: { $0.code == waypoint.code }) else { return }
        waypoints.append(waypoint)
        scheduleRouteRefresh()
    }

    // MARK: - Click-to-add a precise map point

    /// Best-effort reverse geocode used by the map's "add this point?"
    /// confirmation to name the tapped spot (street / commune).
    func reverseLookup(lat: Double, lng: Double) async -> CommuneResult? {
        try? await api.reverseGeocode(lat: lat, lng: lng).first
    }

    /// Append a point tapped on the map to the end of the route. Keeps the
    /// EXACT tapped coordinates (so the route passes precisely there) and
    /// mints a unique synthetic `code` (`pt:lat,lng`) so several points in
    /// the same commune don't collide with the INSEE-code dedup.
    func addPrecisePoint(lat: Double, lng: Double, from result: CommuneResult?) {
        let wp = Waypoint(
            name: result?.name ?? String(format: "%.4f, %.4f", lat, lng),
            code: String(format: "pt:%.5f,%.5f", lat, lng),
            postal: result?.postal,
            lat: lat,
            lng: lng,
            label: result?.label,
            city: nil,
            kind: result?.kind.flatMap(Waypoint.PlaceKind.init(rawValue:)) ?? .locality,
        )
        waypoints.append(wp)
        scheduleRouteRefresh()
    }

    func remove(at index: Int) {
        guard waypoints.indices.contains(index) else { return }
        waypoints.remove(at: index)
        scheduleRouteRefresh()
    }

    func move(fromOffsets: IndexSet, toOffset: Int) {
        waypoints.move(fromOffsets: fromOffsets, toOffset: toOffset)
        scheduleRouteRefresh()
    }

    func move(at index: Int, by delta: Int) {
        let target = index + delta
        guard waypoints.indices.contains(index), waypoints.indices.contains(target) else { return }
        waypoints.swapAt(index, target)
        scheduleRouteRefresh()
    }

    func clearAll() {
        waypoints.removeAll()
        geometry = nil
        distanceMeters = nil
        durationSeconds = nil
        routeError = nil
        elevSeries = []
        elevations = nil
        elevSampleIndices = nil
        ascent = 0
        descent = 0
        name = ""
        activeId = nil
        cols = []
        colsFetchedKey = ""
    }

    func setLoop(_ loop: Bool) {
        self.loop = loop
        scheduleRouteRefresh()
    }

    func setTargetKm(_ km: Double) {
        self.targetKm = km
        // Target only affects auto-extend; no need to re-route on every drag.
    }

    // MARK: - Cols near the departure (cycling only)

    func setColRadius(_ km: Double) {
        guard km != colRadiusKm else { return }
        colRadiusKm = km
        scheduleColsRefresh(force: true)
    }

    /// Refetch the cols around the departure (waypoint #1) into `cols`. Cycling
    /// only; debounced + cached by departure + radius so it doesn't re-hit the
    /// API on every keystroke. The backend caches successful lookups, so this is
    /// cheap once an area is warm.
    func scheduleColsRefresh(force: Bool = false) {
        colsTask?.cancel()
        guard routingProfile == "bike", let dep = waypoints.first else {
            cols = []
            colsFetchedKey = ""
            return
        }
        let key = String(format: "%.3f,%.3f,%.0f", dep.lat, dep.lng, colRadiusKm)
        if !force && key == colsFetchedKey && !cols.isEmpty { return }
        let lat = dep.lat, lng = dep.lng, radius = colRadiusKm
        colsTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, !Task.isCancelled else { return }
            await self.loadCols(lat: lat, lng: lng, radius: radius, key: key)
        }
    }

    private func loadCols(lat: Double, lng: Double, radius: Double, key: String) async {
        colsLoading = true
        let result = (try? await api.cols(lat: lat, lng: lng, radiusKm: radius)) ?? []
        guard !Task.isCancelled else { colsLoading = false; return }
        cols = result
        if !result.isEmpty { colsFetchedKey = key }
        colsLoading = false
    }

    /// Index of the waypoint that represents a col: exact synthetic code, or —
    /// for routes built before the cols feature — any stop within ~250 m. Mirrors
    /// the web's proximity matching.
    func colWaypointIndex(_ col: APIClient.Col) -> Int? {
        let code = String(format: "col:%.5f,%.5f", col.lat, col.lng)
        if let exact = waypoints.firstIndex(where: { $0.code == code }) { return exact }
        let target = CLLocation(latitude: col.lat, longitude: col.lng)
        var best: Int? = nil
        var bestD = 250.0
        for (i, w) in waypoints.enumerated() {
            let d = CLLocation(latitude: w.lat, longitude: w.lng).distance(from: target)
            if d < bestD { bestD = d; best = i }
        }
        return best
    }

    func isColSelected(_ col: APIClient.Col) -> Bool { colWaypointIndex(col) != nil }

    /// Add a col to the route, or remove it (proximity-aware) if already in.
    func toggleCol(_ col: APIClient.Col) {
        if let idx = colWaypointIndex(col) {
            remove(at: idx)
            return
        }
        let wp = Waypoint(
            name: col.name,
            code: String(format: "col:%.5f,%.5f", col.lat, col.lng),
            postal: col.city,
            lat: col.lat,
            lng: col.lng,
            label: col.ele.map { "\(col.name) - \($0) m" } ?? col.name,
            city: col.city,
            kind: .locality,
        )
        waypoints.append(wp)
        scheduleRouteRefresh()
    }

    /// Return the waypoints actually sent to OSRM — appends start at end
    /// for closed loops.
    func effectiveWaypoints() -> [Waypoint] {
        guard loop, waypoints.count >= 2 else { return waypoints }
        return waypoints + [waypoints[0]]
    }

    // MARK: - Route fetching

    private func scheduleRouteRefresh() {
        routingTask?.cancel()
        routingTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await self?.computeRoute()
        }
        // The departure may have changed → refresh the nearby cols too (cheap,
        // debounced + cached).
        scheduleColsRefresh()
    }

    private func computeRoute() async {
        let eff = effectiveWaypoints()
        guard eff.count >= 2 else {
            geometry = nil
            distanceMeters = nil
            durationSeconds = nil
            routeError = nil
            elevSeries = []
            elevations = nil
            elevSampleIndices = nil
            ascent = 0
            descent = 0
            return
        }
        routing = true
        routeError = nil
        do {
            let route = try await api.bikeRoute(waypoints: eff.map(\.coordinate), steps: false, profile: routingProfile)
            geometry = route.geometry
            distanceMeters = route.distance
            durationSeconds = route.duration
            await fetchElevation()
        } catch {
            routeError = error.localizedDescription
            geometry = nil
            distanceMeters = nil
            durationSeconds = nil
        }
        routing = false
    }

    private func fetchElevation() async {
        guard let geometry, geometry.count >= 2 else {
            elevSeries = []
            elevations = nil
            elevSampleIndices = nil
            ascent = 0
            descent = 0
            return
        }
        let (points, indices) = GeoMath.downsampleByDistance(geometry, n: 80)
        elevationLoading = true
        defer { elevationLoading = false }
        do {
            let raw = try await api.elevation(for: points)
            let values = GeoMath.sanitizeElevations(raw)
            let series = GeoMath.elevationSeries(polyline: geometry, sampleIndices: indices, elevations: values)
            elevSeries = series.map { ElevationSample(km: $0.km, elevation: $0.ele) }
            elevations = values
            elevSampleIndices = indices
            let stats = GeoMath.ascentDescent(values)
            ascent = stats.ascent
            descent = stats.descent
        } catch {
            // Elevation is decorative — silent fail keeps the page usable
            // when opentopodata rate-limits us.
            elevSeries = []
            elevations = nil
            elevSampleIndices = nil
            ascent = 0
            descent = 0
        }
    }

    // MARK: - Auto-extend

    /// Find a perpendicular detour that brings the route close to targetKm.
    /// Mirrors the web's findDetour.
    func autoExtend() async {
        guard let distanceMeters else { return }
        let distanceKm = distanceMeters / 1000
        guard targetKm - distanceKm >= 3 else { return }
        let minWaypoints = loop ? 1 : 2
        guard waypoints.count >= minWaypoints else { return }
        extending = true
        defer { extending = false }

        let eff = effectiveWaypoints()
        // Find the longest leg.
        var bestI = 0
        var bestD: Double = 0
        for i in 0..<(eff.count - 1) {
            let d = GeoMath.haversine(eff[i].coordinate, eff[i + 1].coordinate)
            if d > bestD { bestD = d; bestI = i }
        }
        let a = eff[bestI]
        let b = eff[bestI + 1]
        let midLat = (a.lat + b.lat) / 2
        let midLng = (a.lng + b.lng) / 2

        let dLat = b.lat - a.lat
        let dLng = b.lng - a.lng
        let perpLat = -dLng
        let perpLng = dLat
        let norm = max(hypot(perpLat, perpLng), 1e-9)

        let extraKm = targetKm - distanceKm
        let offsetKm = max(3, min(12, extraKm / 4))
        let cosLat = cos(GeoMath.deg2rad(midLat))
        let exclude = waypoints.map(\.code).joined(separator: ",")

        let candidates: [(Double, Double)] = [
            (
                midLat + (perpLat / norm) * (offsetKm / 111),
                midLng + (perpLng / norm) * (offsetKm / (111 * (cosLat == 0 ? 1 : cosLat))),
            ),
            (
                midLat - (perpLat / norm) * (offsetKm / 111),
                midLng - (perpLng / norm) * (offsetKm / (111 * (cosLat == 0 ? 1 : cosLat))),
            ),
        ]
        for (lat, lng) in candidates {
            do {
                let results = try await api.reverseGeocode(lat: lat, lng: lng, exclude: exclude)
                if let first = results.first {
                    let insertAt = (bestI == waypoints.count - 1 && loop)
                        ? waypoints.count
                        : bestI + 1
                    waypoints.insert(first.toWaypoint(), at: min(insertAt, waypoints.count))
                    scheduleRouteRefresh()
                    return
                }
            } catch {
                continue
            }
        }
    }

    // MARK: - Save / load

    func snapshot() -> Itinerary {
        Itinerary(
            id: activeId ?? Itinerary.newId(),
            name: name.isEmpty ? defaultName() : name,
            createdAt: Date(),
            waypoints: waypoints,
            targetKm: targetKm,
            loop: loop,
            distanceKm: distanceMeters.map { ($0 / 1000 * 10).rounded() / 10 },
            durationMin: durationSeconds.map { Int(($0 / 60).rounded()) },
            geometry: geometry,
            elevSampleIndices: elevSampleIndices,
            elevations: elevations,
            totalAscent: ascent > 0 ? ascent : nil,
            totalDescent: descent > 0 ? descent : nil,
        )
    }

    func load(_ itinerary: Itinerary) {
        routingTask?.cancel()
        elevationTask?.cancel()
        activeId = itinerary.id
        name = itinerary.name
        waypoints = itinerary.waypoints
        targetKm = itinerary.targetKm
        loop = itinerary.loop
        geometry = itinerary.geometry
        distanceMeters = itinerary.distanceKm.map { $0 * 1000 }
        durationSeconds = itinerary.durationMin.map { Double($0 * 60) }
        routeError = nil
        if let geometry = itinerary.geometry,
           let indices = itinerary.elevSampleIndices,
           let savedElevations = itinerary.elevations {
            let elevations = GeoMath.sanitizeElevations(savedElevations)
            let series = GeoMath.elevationSeries(polyline: geometry, sampleIndices: indices, elevations: elevations)
            elevSeries = series.map { ElevationSample(km: $0.km, elevation: $0.ele) }
            self.elevations = elevations
            self.elevSampleIndices = indices
            // Recompute from the cleaned series so D+/D− match the chart
            // (saved values may have been inflated by the old 0-spikes).
            let stats = GeoMath.ascentDescent(elevations)
            ascent = stats.ascent
            descent = stats.descent
        } else {
            elevSeries = []
            elevations = nil
            elevSampleIndices = nil
            ascent = 0
            descent = 0
        }
    }

    func defaultName() -> String {
        guard let first = waypoints.first?.name, let last = waypoints.last?.name else { return "Itinéraire" }
        return waypoints.count > 1 ? "\(first) → \(last)" : first
    }
}

/// One sample on the elevation chart.
struct ElevationSample: Identifiable, Hashable {
    var id: Double { km }
    let km: Double
    let elevation: Double
}
