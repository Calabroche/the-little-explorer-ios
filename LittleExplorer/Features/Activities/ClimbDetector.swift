import Foundation

/// One detected climb on a ride — a contiguous ascent stretch that
/// meets the "this is a real climb" thresholds (avg grade ≥ 3 %,
/// elevation gain ≥ 30 m, length ≥ 500 m).
struct Climb: Identifiable, Hashable {
    let id: UUID = UUID()
    /// Index into the activity's altitude / distanceM arrays.
    let startIndex: Int
    let endIndex: Int
    /// Linear distance covered by the climb, meters.
    let distanceM: Double
    /// Net elevation gain across start → end, meters.
    let elevationM: Double
    /// Average grade in %, signed positive.
    let avgGradePct: Double
    /// Maximum sustained grade across the climb (over a 100 m window).
    let maxGradePct: Double
    /// Time spent climbing, seconds. Used as the "PR" metric — same
    /// distance + same start/end ≈ same climb; faster time → better.
    let durationSec: Double
    /// Climb name derived from the closest GPS waypoint or village —
    /// the detector leaves it blank; the view layer fills it in via
    /// reverse geocoding if it cares.
    var name: String
}

/// Algorithm: walk the altitude stream, accumulate elevation gain over
/// rolling windows, and emit a Climb when the run meets all thresholds.
/// Designed to match what Strava calls a "climb" without needing their
/// proprietary segment library.
enum ClimbDetector {
    /// Minimum thresholds for a stretch to count as a climb. Defaults
    /// are tuned for road / gravel cycling — running and hiking would
    /// want lower values (TODO: per-sport tuning).
    struct Thresholds {
        var minDistanceM: Double  = 500    // 500 m minimum
        var minElevationM: Double = 30     // 30 m gain
        var minAvgGradePct: Double = 3     // 3 % avg grade
        /// Stop the climb when we see this much of a downhill (rolling
        /// 100 m). Lets the algo handle false plateaus / brief descents.
        var maxNetDescentDuringClimb: Double = 8
    }

    static func detect(
        altitude: [Double],
        distanceM: [Double],
        timeS: [Double]?,
        thresholds: Thresholds = .init(),
    ) -> [Climb] {
        guard altitude.count >= 30,
              altitude.count == distanceM.count,
              altitude.count > 1 else { return [] }

        // Smooth the altitude stream with a 30-sample window to
        // suppress GPS noise — raw 1Hz altitude bounces ±3 m which
        // would otherwise fragment a single climb into 20 micro-climbs.
        let smoothed = smoothAltitude(altitude, window: 30)

        var climbs: [Climb] = []
        var i = 0
        let n = smoothed.count

        while i < n - 1 {
            // Skip non-climbing sections — slope must be positive
            // sustained at least over the next 20 samples.
            if !isAscentStarting(at: i, smoothed: smoothed, distanceM: distanceM) {
                i += 1
                continue
            }

            // Walk forward until the run loses too much elevation.
            var bestEnd = i
            var bestPeakAlt = smoothed[i]
            var j = i + 1
            while j < n {
                let alt = smoothed[j]
                if alt > bestPeakAlt {
                    bestPeakAlt = alt
                    bestEnd = j
                }
                let descentFromPeak = bestPeakAlt - alt
                if descentFromPeak > thresholds.maxNetDescentDuringClimb {
                    // We've come down enough off the peak — close the
                    // climb here (we'll cut at the peak, not at j).
                    break
                }
                j += 1
            }

            let start = i
            let end = bestEnd
            let elev = smoothed[end] - smoothed[start]
            let dist = distanceM[end] - distanceM[start]

            if elev >= thresholds.minElevationM,
               dist >= thresholds.minDistanceM {
                let avg = (elev / max(dist, 1)) * 100
                if avg >= thresholds.minAvgGradePct {
                    let maxGrade = peakSustainedGrade(
                        from: start, to: end,
                        smoothed: smoothed, distanceM: distanceM,
                    )
                    let duration: Double = {
                        guard let timeS, timeS.indices.contains(start), timeS.indices.contains(end) else { return 0 }
                        return max(0, timeS[end] - timeS[start])
                    }()
                    climbs.append(Climb(
                        startIndex: start,
                        endIndex: end,
                        distanceM: dist,
                        elevationM: elev,
                        avgGradePct: avg,
                        maxGradePct: maxGrade,
                        durationSec: duration,
                        name: "Montée \(climbs.count + 1)",
                    ))
                }
            }
            // Resume scanning after the end of this climb (or i+1 if it
            // didn't qualify, so we don't loop forever).
            i = max(end, i + 1)
        }
        return climbs
    }

    // MARK: - Smoothing + helpers

    /// Centered moving average. Returns an array the same length as the
    /// input.
    private static func smoothAltitude(_ alt: [Double], window: Int) -> [Double] {
        guard alt.count >= window else { return alt }
        var out = Array(repeating: 0.0, count: alt.count)
        for i in 0..<alt.count {
            let lo = max(0, i - window / 2)
            let hi = min(alt.count - 1, i + window / 2)
            var sum = 0.0
            for k in lo...hi { sum += alt[k] }
            out[i] = sum / Double(hi - lo + 1)
        }
        return out
    }

    /// Heuristic: a climb starts when the next 20 m of smoothed
    /// altitude trends upward more than 2 m and the gradient over
    /// that lookahead is ≥ 2 %.
    private static func isAscentStarting(at i: Int, smoothed: [Double], distanceM: [Double]) -> Bool {
        let look = 20
        guard i + look < smoothed.count else { return false }
        let elev = smoothed[i + look] - smoothed[i]
        let dist = distanceM[i + look] - distanceM[i]
        if dist < 50 { return false }
        return elev >= 2 && (elev / dist) * 100 >= 2
    }

    /// Sliding 100 m window peak grade across the climb. Reasonable
    /// approximation of what cyclists feel as "the steep bit".
    private static func peakSustainedGrade(
        from start: Int, to end: Int,
        smoothed: [Double], distanceM: [Double],
    ) -> Double {
        var maxGrade = 0.0
        var j = start
        while j < end {
            // Find k such that distanceM[k] >= distanceM[j] + 100.
            var k = j + 1
            while k < end, distanceM[k] - distanceM[j] < 100 { k += 1 }
            if k >= end { break }
            let dAlt = smoothed[k] - smoothed[j]
            let dDist = distanceM[k] - distanceM[j]
            if dDist > 50 {
                let grade = (dAlt / dDist) * 100
                if grade > maxGrade { maxGrade = grade }
            }
            j += 10  // step 10 samples — faster than 1-by-1
        }
        return min(maxGrade, 30) // cap at 30 % to filter GPS spikes
    }
}
