import Foundation
import Observation
import os

/// Local JSON store for rides recorded standalone on the Watch.
///
/// Layout: `<Documents>/pending-rides/<id>.json`, one file per ride.
/// Atomic file writes (Foundation handles the temp-file-rename dance
/// when you pass `.atomic`) so a crash mid-write never leaves the
/// directory with a corrupt half-file.
///
/// Why JSON and not SQLite or Core Data: this is buffer storage
/// (Phase 2 will transfer + delete each file). We're talking dozens
/// of rides at most, sized in single-digit MB each. No querying, no
/// indexes, no relations — JSON is the right tool. Swap to SQLite if
/// we ever need to scan rides without loading them all.
@Observable
@MainActor
final class PendingRideStore {
    private(set) var pending: [PendingRide] = []

    private let logger = Logger(subsystem: "com.calabrese.little-explorer-ios.watchkitapp", category: "PendingRideStore")
    private let fileManager = FileManager.default
    private let directory: URL

    init() {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        directory = docs.appendingPathComponent("pending-rides", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        reload()
    }

    /// Re-read the whole directory. Cheap (handful of small files),
    /// called on init and whenever a write completes — keeps the
    /// observable `pending` array in sync with disk.
    func reload() {
        guard let urls = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            pending = []
            return
        }
        let decoder = JSONDecoder()
        pending = urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> PendingRide? in
                guard let data = try? Data(contentsOf: url),
                      let ride = try? decoder.decode(PendingRide.self, from: data) else {
                    logger.warning("Skipping unreadable pending ride at \(url.lastPathComponent)")
                    return nil
                }
                return ride
            }
            .sorted { $0.id > $1.id }   // newest first
    }

    /// Persist a ride to disk. Returns the file URL on success so the
    /// caller (Phase 2 sync) can later target the exact file to delete.
    @discardableResult
    func save(_ ride: PendingRide) -> URL? {
        let url = directory.appendingPathComponent("\(ride.id).json")
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]    // stable byte-output across runs
            let data = try encoder.encode(ride)
            try data.write(to: url, options: .atomic)
            reload()
            logger.notice("Saved pending ride \(ride.id, privacy: .public) (\(data.count) bytes)")
            return url
        } catch {
            logger.error("Save failed for ride \(ride.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Remove a single ride from disk — used by Phase 2 once the
    /// iPhone has confirmed receipt.
    func remove(id: Int64) {
        let url = directory.appendingPathComponent("\(id).json")
        try? fileManager.removeItem(at: url)
        reload()
    }
}
