import Foundation
import Observation

/// Per-user store for rides recorded locally via the Track tab.
/// Backed by JSON files in the app's Documents directory:
///   local_rides_<user>.json
///
/// Saved rides are stored as full RideRecord values so they can be
/// merged into the same activity list as API-fetched activities.
/// Local IDs use the negative timestamp space so they can never
/// collide with Strava's positive activity IDs.
@Observable
final class LocalRideStore {
    private(set) var ridesByUser: [AppUser: [RideRecord]] = [:]

    private let directory: URL
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    private let decoder: JSONDecoder = JSONDecoder()

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.directory = documents
    }

    /// Returns the locally-stored rides for the given user. Loads
    /// them from disk on first access.
    func rides(for user: AppUser) -> [RideRecord] {
        if let cached = ridesByUser[user] { return cached }
        let loaded = loadFromDisk(user: user)
        ridesByUser[user] = loaded
        return loaded
    }

    /// Add a new local ride for the given user. Inserted at the head
    /// of the list (newest first) and persisted immediately.
    func add(_ ride: RideRecord, for user: AppUser) {
        var list = rides(for: user)
        list.insert(ride, at: 0)
        ridesByUser[user] = list
        persist(user: user)
    }

    /// Remove a local ride by id (only acts on local rides — Strava
    /// rides have positive IDs and won't match anything stored here).
    func remove(id: Int, for user: AppUser) {
        var list = rides(for: user)
        list.removeAll { $0.id == id }
        ridesByUser[user] = list
        persist(user: user)
    }

    // MARK: - Disk

    private func fileURL(for user: AppUser) -> URL {
        directory.appendingPathComponent("local_rides_\(user.rawValue).json")
    }

    private func loadFromDisk(user: AppUser) -> [RideRecord] {
        let url = fileURL(for: user)
        guard let data = try? Data(contentsOf: url) else { return [] }
        guard let decoded = try? decoder.decode([RideRecord].self, from: data) else { return [] }
        return decoded
    }

    private func persist(user: AppUser) {
        let list = ridesByUser[user] ?? []
        guard let data = try? encoder.encode(list) else { return }
        try? data.write(to: fileURL(for: user), options: [.atomic])
    }
}
