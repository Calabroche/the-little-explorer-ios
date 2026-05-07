import CoreLocation
import Foundation

/// Lightweight geo helpers — kept here rather than CoreLocation's
/// `CLLocation.distance(from:)` so the same code works against
/// `Coordinate` (Codable, Hashable) without requiring a CL allocation
/// per call inside hot loops (downsampling 80 points, finding closest
/// segment on every GPS tick, etc.).
enum GeoMath {
    static let earthR: Double = 6_371_000

    static func deg2rad(_ d: Double) -> Double { d * .pi / 180 }

    /// Haversine distance in meters.
    static func haversine(_ a: Coordinate, _ b: Coordinate) -> Double {
        let dLat = deg2rad(b.lat - a.lat)
        let dLng = deg2rad(b.lng - a.lng)
        let sLat = sin(dLat / 2)
        let sLng = sin(dLng / 2)
        let h = sLat * sLat + cos(deg2rad(a.lat)) * cos(deg2rad(b.lat)) * sLng * sLng
        return 2 * earthR * asin(min(1, sqrt(h)))
    }

    /// Compass bearing from a to b in degrees clockwise from north.
    static func bearing(_ a: Coordinate, _ b: Coordinate) -> Double {
        let phi1 = deg2rad(a.lat), phi2 = deg2rad(b.lat)
        let dLng = deg2rad(b.lng - a.lng)
        let y = sin(dLng) * cos(phi2)
        let x = cos(phi1) * sin(phi2) - sin(phi1) * cos(phi2) * cos(dLng)
        return (atan2(y, x) * 180 / .pi).truncatingRemainder(dividingBy: 360) + (atan2(y, x) >= 0 ? 0 : 360)
    }

    /// Pick at most `n` points along the polyline, evenly spaced by
    /// cumulative distance. Returns the picked points and their indices
    /// in the original polyline.
    static func downsampleByDistance(
        _ positions: [Coordinate],
        n: Int,
    ) -> (points: [Coordinate], indices: [Int]) {
        if positions.count <= n {
            return (positions, Array(0..<positions.count))
        }
        var cumul: [Double] = [0]
        cumul.reserveCapacity(positions.count)
        for i in 1..<positions.count {
            cumul.append(cumul[i - 1] + haversine(positions[i - 1], positions[i]))
        }
        let total = cumul.last ?? 0
        if total == 0 { return ([positions[0]], [0]) }
        let step = total / Double(n - 1)

        var points: [Coordinate] = []
        var indices: [Int] = []
        var target: Double = 0
        var j = 0
        for _ in 0..<n {
            while j < cumul.count - 1, cumul[j + 1] < target { j += 1 }
            points.append(positions[j])
            indices.append(j)
            target += step
        }
        // Force the last point.
        if !points.isEmpty {
            points[points.count - 1] = positions.last!
            indices[indices.count - 1] = positions.count - 1
        }
        return (points, indices)
    }

    /// Total ascent / descent (rounded m).
    static func ascentDescent(_ elevations: [Double]) -> (ascent: Int, descent: Int) {
        var asc: Double = 0
        var desc: Double = 0
        for i in 1..<elevations.count {
            let d = elevations[i] - elevations[i - 1]
            if d > 0 { asc += d } else { desc += -d }
        }
        return (Int(asc.rounded()), Int(desc.rounded()))
    }

    /// Build a {km, ele} series along the polyline given the sampled
    /// elevations. Used by the elevation chart.
    static func elevationSeries(
        polyline: [Coordinate],
        sampleIndices: [Int],
        elevations: [Double],
    ) -> [(km: Double, ele: Double)] {
        var cumul: [Double] = [0]
        cumul.reserveCapacity(polyline.count)
        for i in 1..<polyline.count {
            cumul.append(cumul[i - 1] + haversine(polyline[i - 1], polyline[i]))
        }
        var out: [(km: Double, ele: Double)] = []
        out.reserveCapacity(sampleIndices.count)
        for k in 0..<sampleIndices.count {
            let idx = sampleIndices[k]
            guard idx < cumul.count, k < elevations.count else { continue }
            out.append((km: (cumul[idx] / 1000 * 100).rounded() / 100, ele: elevations[k].rounded()))
        }
        return out
    }

    // MARK: - Polyline projection (used by turn-by-turn nav)

    /// Closest point on a polyline. Returns segment index, parameter
    /// t ∈ [0,1], the foot of the perpendicular, and the distance in m.
    /// `searchFrom` skips earlier segments to avoid backtracking on loops.
    static func closestPoint(
        on polyline: [Coordinate],
        to p: Coordinate,
        searchFrom: Int = 0,
    ) -> (segmentIndex: Int, t: Double, foot: Coordinate, distance: Double) {
        guard polyline.count >= 2 else {
            return (searchFrom, 0, polyline.first ?? p, 0)
        }
        let cosLat = cos(deg2rad(p.lat))
        // Local equirectangular projection — meters from `p`.
        func project(_ q: Coordinate) -> (x: Double, y: Double) {
            (
                (q.lng - p.lng) * cosLat * 111_320,
                (q.lat - p.lat) * 110_540,
            )
        }
        var bestSeg = searchFrom
        var bestT: Double = 0
        var bestD2 = Double.infinity
        var bestFoot = polyline[searchFrom]

        let pp = project(p) // origin in projected coords (≈ 0,0)
        let upperBound = polyline.count - 1
        for i in max(0, searchFrom)..<upperBound {
            let a = project(polyline[i])
            let b = project(polyline[i + 1])
            let dx = b.x - a.x
            let dy = b.y - a.y
            let len2 = dx * dx + dy * dy
            guard len2 > 0 else { continue }
            var t = ((pp.x - a.x) * dx + (pp.y - a.y) * dy) / len2
            t = max(0, min(1, t))
            let fx = a.x + t * dx
            let fy = a.y + t * dy
            let d2 = (fx - pp.x) * (fx - pp.x) + (fy - pp.y) * (fy - pp.y)
            if d2 < bestD2 {
                bestD2 = d2
                bestSeg = i
                bestT = t
                let lat = polyline[i].lat + (polyline[i + 1].lat - polyline[i].lat) * t
                let lng = polyline[i].lng + (polyline[i + 1].lng - polyline[i].lng) * t
                bestFoot = Coordinate(lat: lat, lng: lng)
            }
        }
        return (bestSeg, bestT, bestFoot, sqrt(bestD2))
    }

    /// Distance from a point on the polyline to the END.
    static func distanceRemaining(
        polyline: [Coordinate],
        from segmentIndex: Int,
        t: Double,
    ) -> Double {
        guard polyline.count >= 2, segmentIndex < polyline.count - 1 else { return 0 }
        var total = haversine(polyline[segmentIndex], polyline[segmentIndex + 1]) * (1 - t)
        for i in (segmentIndex + 1)..<(polyline.count - 1) {
            total += haversine(polyline[i], polyline[i + 1])
        }
        return total
    }

    /// Distance along the polyline to a target coordinate (assumed to lie
    /// on the polyline at index ≥ searchFrom).
    static func distanceAlong(
        polyline: [Coordinate],
        from segmentIndex: Int,
        t: Double,
        to target: Coordinate,
    ) -> Double {
        guard polyline.count >= 2 else { return 0 }
        let tg = closestPoint(on: polyline, to: target, searchFrom: segmentIndex)
        if tg.segmentIndex < segmentIndex || (tg.segmentIndex == segmentIndex && tg.t <= t) {
            return 0
        }
        if tg.segmentIndex == segmentIndex {
            return haversine(polyline[segmentIndex], polyline[segmentIndex + 1]) * (tg.t - t)
        }
        var total = haversine(polyline[segmentIndex], polyline[segmentIndex + 1]) * (1 - t)
        for i in (segmentIndex + 1)..<tg.segmentIndex {
            total += haversine(polyline[i], polyline[i + 1])
        }
        total += haversine(polyline[tg.segmentIndex], polyline[tg.segmentIndex + 1]) * tg.t
        return max(0, total)
    }
}
