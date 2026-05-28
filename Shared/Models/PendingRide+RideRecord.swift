import Foundation

/// PendingRide → RideRecord conversion used iPhone-side when a ride
/// transferred from the Watch arrives over WCSession. The PendingRide
/// model is intentionally minimal (just enough to fit a transfer
/// payload); RideRecord is what every iOS feed/chart expects, so we
/// fill the gap here by deriving everything we can and leaving the
/// rest nil (FTP, TSS, weather… nothing the Watch can know).
///
/// Naming convention: the title carries "Apple Watch" + the start
/// date so the user spots Watch-recorded rides at a glance in the
/// feed (next to Strava-imported ones).
extension PendingRide {
    func toRideRecord() -> RideRecord {
        let start = ISO8601DateFormatter().date(from: date) ?? Date()
        let mins  = Int((durationSeconds / 60).rounded())
        let km    = distanceM / 1000

        // Average speed from total distance / total time. Strava does
        // the same — gives the user a sensible number even when the
        // GPS speed stream is noisy.
        let avgKmh: Double = durationSeconds > 0
            ? (km / (durationSeconds / 3600))
            : 0

        // Elevation gain = sum of positive altitude deltas. Smoothed
        // over a 3-sample window to drop GPS noise (otherwise a
        // flat ride accumulates 200 m of phantom climb just from
        // altimeter jitter).
        let elev = elevationGain(altitude)

        // Cumulative distance per GPS point — used by the per-point
        // hover tooltip on the activity card map.
        var dCum: [Double] = []
        dCum.reserveCapacity(gps.count)
        var running: Double = 0
        for i in 0..<gps.count {
            if i > 0 {
                running += haversine(gps[i - 1], gps[i])
            }
            dCum.append(running)
        }

        return RideRecord(
            id:            Int(id),
            type:          sport,
            originalType:  nil,
            title:         "Sortie Apple Watch \(humanDate(start))",
            date:          humanDate(start),
            rawDate:       date,
            location:      "France",
            duration:      formatDuration(mins),
            durationMin:   mins,
            distance:      km,
            speed:         avgKmh,
            maxSpeed:      nil,
            elevation:     elev,
            descent:       elev,           // we report the same number for ascent / descent; refine in Phase 4 if needed
            gps:           gps,
            altitude:      altitude.isEmpty ? nil : altitude,
            speedKmh:      nil,            // not stored on the Watch side yet
            heartrate:     heartrate.isEmpty ? nil : heartrate,
            distanceM:     dCum.isEmpty ? nil : dCum,
            timeS:         timeS.isEmpty ? nil : timeS,
            maxIncline:    nil,
            minIncline:    nil,
            avgHr:         heartrate.isEmpty ? nil : heartrate.reduce(0, +) / Double(heartrate.count),
            maxHr:         heartrate.isEmpty ? nil : Int(heartrate.max() ?? 0),
            calories:      nil,
            np:            nil,
            avgPower:      nil,
            tss:           nil,
            ifFactor:      nil,
            vi:            nil,
            wkg:           nil,
            ef:            nil,
            trimp:         nil,
            vam:           nil,
            ftp:           nil,
            weather:       nil,
            bestEfforts:   nil,
            photos:        nil,
            hrZones:       nil,
            aed:           nil,
            riderKg:       nil,
            totalMass:     nil,
            paceSPerKm:    nil,
            // Watch rides aren't bound to a Strava gear yet — Phase 4
            // could let the user pick a bike before tapping Start.
            gearId:        nil,
            gearName:      nil,
        )
    }
}

// ── Helpers ─────────────────────────────────────────────────────────

private func humanDate(_ d: Date) -> String {
    let fmt = DateFormatter()
    fmt.dateStyle = .medium
    fmt.locale = Locale(identifier: "fr_FR")
    return fmt.string(from: d)
}

private func formatDuration(_ minutes: Int) -> String {
    let h = minutes / 60
    let m = minutes % 60
    return h > 0 ? "\(h)h\(String(format: "%02d", m))" : "\(m)min"
}

/// Sum of positive altitude deltas with a tiny smoothing window so
/// 1-meter altimeter jitter doesn't masquerade as climbing.
private func elevationGain(_ alt: [Double]) -> Double {
    guard alt.count >= 3 else { return 0 }
    var gain: Double = 0
    var prev = alt[0]
    for i in 1..<alt.count {
        let smoothed = (alt[i - 1] + alt[i] + alt[min(i + 1, alt.count - 1)]) / 3
        let delta = smoothed - prev
        if delta > 0.5 {     // ignore < 0.5 m blips
            gain += delta
            prev = smoothed
        } else if delta < -0.5 {
            prev = smoothed
        }
    }
    return gain
}

/// Great-circle distance between two Coordinates, in meters.
private func haversine(_ a: Coordinate, _ b: Coordinate) -> Double {
    let R = 6_371_000.0
    let lat1 = a.lat * .pi / 180
    let lat2 = b.lat * .pi / 180
    let dLat = (b.lat - a.lat) * .pi / 180
    let dLng = (b.lng - a.lng) * .pi / 180
    let h = sin(dLat / 2) * sin(dLat / 2)
          + cos(lat1) * cos(lat2) * sin(dLng / 2) * sin(dLng / 2)
    return 2 * R * atan2(sqrt(h), sqrt(1 - h))
}
