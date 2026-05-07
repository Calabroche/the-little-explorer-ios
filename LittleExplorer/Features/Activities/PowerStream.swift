import Foundation

/// One down-sampled point along the ride. Mirrors the rows produced by
/// the web app's buildChartData() — each one carries the raw streams
/// plus per-sample power computed from the same physical model.
struct ChartPoint: Identifiable, Hashable {
    var id: Double { distKm }
    let index: Int        // index back into the original 1Hz streams
    let distKm: Double
    let altitude: Double?
    let speedKmh: Double?
    let heartRate: Double?
    let gradientPct: Double
    let power: Int
    let fGrav: Double
    let fAero: Double
    let mass: Double
}

enum PowerStream {
    static let g: Double = 9.81
    static let crr: Double = 0.004
    static let cda: Double = 0.3
    static let rho: Double = 1.225
    static let fallbackMass: Double = 74.18    // Florian: 66 kg + 8.18 kg vélo
    static let fallbackRiderKg: Double = 66
    static let fallbackFtp: Int = 291

    /// Build the per-sample chart series + power model. Down-samples to
    /// at most ~300 points so SwiftUI Charts stays smooth.
    /// Returns an empty array when the ride has too few stream samples.
    static func build(from activity: RideRecord) -> [ChartPoint] {
        let hr   = activity.heartrate ?? []
        let alt  = activity.altitude ?? []
        let dist = activity.distanceM ?? []
        let speed = activity.speedKmh ?? []
        let len = min(hr.count, alt.count, dist.count, speed.count)
        guard len >= 10 else { return [] }

        let mass = activity.totalMass ?? fallbackMass
        let fr = mass * g * crr

        let window = 40
        var gradient = Array(repeating: 0.0, count: len)
        for i in window..<(len - window) {
            let dAlt = alt[i + window] - alt[i - window]
            let dDist = dist[i + window] - dist[i - window]
            if dDist >= 20 {
                let g = (dAlt / dDist) * 100
                gradient[i] = max(-25, min(25, (g * 10).rounded() / 10))
            }
        }

        var power = Array(repeating: 0, count: len)
        var fGravs = Array(repeating: 0.0, count: len)
        var fAeros = Array(repeating: 0.0, count: len)
        for i in 0..<len {
            let v = (speed[i]) / 3.6
            let gr = gradient[i] / 100
            let fGrav = mass * g * gr
            let fAero = 0.5 * rho * cda * v * v
            fGravs[i] = (fGrav * 10).rounded() / 10
            fAeros[i] = (fAero * 10).rounded() / 10
            power[i] = max(0, Int(((fGrav + fr + fAero) * v).rounded()))
        }

        let step = max(1, len / 300)
        var out: [ChartPoint] = []
        out.reserveCapacity(len / step + 1)
        var i = 0
        while i < len {
            out.append(ChartPoint(
                index: i,
                distKm: ((dist[i] / 1000) * 100).rounded() / 100,
                altitude: alt.indices.contains(i) ? (alt[i] * 10).rounded() / 10 : nil,
                speedKmh: speed.indices.contains(i) ? (speed[i] * 10).rounded() / 10 : nil,
                heartRate: hr.indices.contains(i) ? hr[i] : nil,
                gradientPct: gradient[i],
                power: power[i],
                fGrav: fGravs[i],
                fAero: fAeros[i],
                mass: mass,
            ))
            i += step
        }
        return out
    }

    /// Given a target index in the original stream, return the matching
    /// data slice for popups (used by RouteAnalysisMap).
    static func sample(at index: Int, activity: RideRecord, gradient: [Double]) -> RouteSample {
        let speedKmh = activity.speedKmh?.indices.contains(index) == true ? activity.speedKmh![index] : 0
        let speedMs = speedKmh / 3.6
        let grad = gradient.indices.contains(index) ? gradient[index] : 0
        let mass = activity.totalMass ?? fallbackMass
        let fr = mass * g * crr
        let fGrav = mass * g * (grad / 100)
        let fAero = 0.5 * rho * cda * speedMs * speedMs
        let powerW = max(0, Int(((fGrav + fr + fAero) * speedMs).rounded()))
        return RouteSample(
            distKm: ((activity.distanceM?.indices.contains(index) == true ? activity.distanceM![index] : 0) / 1000 * 100).rounded() / 100,
            heartRate: activity.heartrate?.indices.contains(index) == true ? Int(activity.heartrate![index]) : nil,
            speedKmh: (speedKmh * 10).rounded() / 10,
            powerW: powerW,
            altitude: activity.altitude?.indices.contains(index) == true ? Int(activity.altitude![index].rounded()) : nil,
            gradientPct: (grad * 10).rounded() / 10,
        )
    }

    /// Same gradient computation as build(), exposed so the map can
    /// re-use it without recomputing the full chart series.
    static func gradient(for activity: RideRecord) -> [Double] {
        let alt = activity.altitude ?? []
        let dist = activity.distanceM ?? []
        let len = min(alt.count, dist.count)
        var out = Array(repeating: 0.0, count: len)
        let window = 40
        for i in window..<(len - window) {
            let dAlt = alt[i + window] - alt[i - window]
            let dDist = dist[i + window] - dist[i - window]
            if dDist >= 20 {
                let g = (dAlt / dDist) * 100
                out[i] = max(-25, min(25, (g * 10).rounded() / 10))
            }
        }
        return out
    }
}

struct RouteSample {
    let distKm: Double
    let heartRate: Int?
    let speedKmh: Double
    let powerW: Int
    let altitude: Int?
    let gradientPct: Double
}
