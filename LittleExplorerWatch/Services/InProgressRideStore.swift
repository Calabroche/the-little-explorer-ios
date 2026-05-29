import Foundation
import os

/// Crash-recovery store for the *active* ride.
///
/// While a ride is being recorded, `WorkoutManager` calls
/// `save(snapshot:)` every ~30 s with the current buffer (GPS fixes,
/// elapsed time, etc.). The snapshot lives in
/// `Documents/in-progress.json` until either:
///   • The user taps End → cleared by `WorkoutManager.end()`.
///   • The Watch reboots mid-ride → the file survives, and on next
///     app launch we detect it and offer to resume / finalize.
///
/// Why a separate file from PendingRideStore: PendingRide is for
/// *completed* rides waiting to sync; this is for the *in-progress*
/// state, which has different semantics (no id assigned yet, may grow
/// after each save, only one at a time).
struct InProgressSnapshot: Codable, Sendable {
    let startedAt: Date
    let lastUpdate: Date
    let elapsed: TimeInterval
    let distanceM: Double
    /// Sampled GPS points so far. We don't store full CLLocations —
    /// just (lat, lng, alt, timestamp) tuples that map cleanly back
    /// to what `buildPendingRide` consumes.
    let fixes: [Fix]
    let hrSamples: [HRSample]

    struct Fix: Codable, Sendable {
        let lat: Double
        let lng: Double
        let alt: Double
        let t: Date
    }
    struct HRSample: Codable, Sendable {
        let t: Date
        let value: Double
    }
}

final class InProgressRideStore {
    private let logger = Logger(subsystem: "com.calabrese.little-explorer-ios.watchkitapp", category: "InProgressRideStore")
    private let url: URL
    /// A snapshot older than this is treated as stale (the user
    /// presumably forgot, or the Watch was off for too long for it to
    /// be useful). Keeps us from surfacing a phantom "resume?" prompt
    /// days after a crashed ride.
    private static let maxAgeHours: Double = 6

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.url = docs.appendingPathComponent("in-progress.json")
    }

    /// Persist the current ride state. Atomic write so a crash mid-
    /// write doesn't corrupt the file.
    func save(_ snapshot: InProgressSnapshot) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(snapshot)
            try data.write(to: url, options: .atomic)
        } catch {
            logger.error("save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Read and return any pending snapshot that's not stale. Returns
    /// nil if the file doesn't exist, can't be decoded, or is older
    /// than `maxAgeHours`.
    func loadIfFresh() -> InProgressSnapshot? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(InProgressSnapshot.self, from: data) else {
            logger.warning("loadIfFresh: decode failed, dropping orphan file")
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        let ageHours = Date.now.timeIntervalSince(snapshot.lastUpdate) / 3600
        guard ageHours <= Self.maxAgeHours else {
            logger.notice("loadIfFresh: snapshot is \(ageHours, format: .fixed(precision: 1), privacy: .public) h old (> \(Self.maxAgeHours, privacy: .public)) — dropping")
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return snapshot
    }

    /// Wipe the on-disk snapshot. Called when a ride ends cleanly so
    /// we don't trip the "resume?" prompt next launch.
    func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}
