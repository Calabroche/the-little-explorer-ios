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
        /// Upper sanity cap. Even the world's worst road climbs
        /// (Mauna Kea, Mortirolo, Angliru) average ≤ 13 % over their
        /// full length. A "climb" averaging more than 15 % almost
        /// always means GPS-altitude corruption (signal lost under a
        /// tunnel / dense canopy, watch reporting altitude = 0 for a
        /// stretch, then jumping back to the real value). Rejecting
        /// it here is more honest than letting it pollute the
        /// detected-climbs list with a phantom Mortirolo.
        var maxAvgGradePct: Double = 15
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

        // STEP 1 — outlier rejection.
        // Without this, a single sample of `altitude = 0` (the watch
        // briefly loses vertical lock under a railway tunnel, dense
        // forest, etc.) survives the moving average smoothing as a
        // 200-300 m altitude dip. The dip generates a phantom climb
        // on the recovery side that averages 25-30 % grade. Clean
        // BEFORE smoothing so the average isn't polluted.
        let cleaned = cleanAltitudeOutliers(altitude)
        // STEP 2 — smooth the cleaned altitude stream with a 30-sample
        // window to suppress GPS noise. Raw 1Hz altitude bounces ±3 m
        // which would otherwise fragment a single climb into 20
        // micro-climbs.
        let smoothed = smoothAltitude(cleaned, window: 30)

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
                if avg >= thresholds.minAvgGradePct,
                   avg <= thresholds.maxAvgGradePct {
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

    /// Replace clearly-corrupt altitude samples with a linear
    /// interpolation between their valid neighbors. Two checks:
    ///   1. `altitude == 0` — the sentinel a GPS chipset writes when
    ///      it has horizontal lock but no vertical fix. Real road
    ///      cycling samples are essentially never exactly zero.
    ///   2. Single-sample spikes — a value that differs from BOTH
    ///      its neighbors by > 30 m. 30 m/sec vertical would mean
    ///      a 108 km/h vertical descent, which is physically out of
    ///      reach for a bike. Anything past it is GPS noise.
    /// Runs of invalid samples are interpolated linearly between
    /// the last valid sample before and the first valid sample
    /// after. Leading / trailing invalid runs are filled with the
    /// nearest valid value.
    private static func cleanAltitudeOutliers(_ alt: [Double]) -> [Double] {
        let n = alt.count
        guard n >= 3 else { return alt }

        // Build the validity mask.
        var valid = Array(repeating: true, count: n)
        for i in 0..<n where alt[i] == 0 { valid[i] = false }
        // Spike check on positions still considered valid.
        for i in 1..<(n - 1) where valid[i] {
            let prev = alt[i - 1]
            let next = alt[i + 1]
            if abs(alt[i] - prev) > 30 && abs(alt[i] - next) > 30 {
                valid[i] = false
            }
        }

        // Interpolate invalid runs.
        var out = alt
        var i = 0
        while i < n {
            if valid[i] { i += 1; continue }
            let runStart = i
            while i < n && !valid[i] { i += 1 }
            let runEnd = i  // exclusive
            let before: Double? = runStart > 0 ? out[runStart - 1] : nil
            let after:  Double? = runEnd  < n ? out[runEnd]     : nil
            switch (before, after) {
            case let (b?, a?):
                let span = Double(runEnd - runStart + 1)
                for k in runStart..<runEnd {
                    let t = Double(k - runStart + 1) / span
                    out[k] = b + (a - b) * t
                }
            case let (b?, nil):
                for k in runStart..<runEnd { out[k] = b }
            case let (nil, a?):
                for k in runStart..<runEnd { out[k] = a }
            case (nil, nil):
                break  // whole series invalid, leave alone
            }
        }
        return out
    }

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
