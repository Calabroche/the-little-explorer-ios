import Foundation
import Observation

/// Per-user library of saved itineraries. Backed by UserDefaults — the
/// app has no auth, so saves live on the device. Mirrors the web app's
/// localStorage scheme.
@Observable
final class ItineraryStore {
    private(set) var items: [Itinerary] = []
    private var loadedFor: AppUser?

    private let defaults: UserDefaults
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(user: AppUser) {
        guard loadedFor != user else { return }
        loadedFor = user
        if let data = defaults.data(forKey: key(for: user)),
           let decoded = try? decoder.decode([Itinerary].self, from: data) {
            items = decoded
        } else {
            items = []
        }
    }

    func upsert(_ itinerary: Itinerary, user: AppUser) {
        load(user: user)
        if let idx = items.firstIndex(where: { $0.id == itinerary.id }) {
            items[idx] = itinerary
        } else {
            items.insert(itinerary, at: 0) // newest first
        }
        persist(user: user)
    }

    func remove(id: String, user: AppUser) {
        load(user: user)
        items.removeAll { $0.id == id }
        persist(user: user)
    }

    private func persist(user: AppUser) {
        guard let data = try? encoder.encode(items) else { return }
        defaults.set(data, forKey: key(for: user))
    }

    private func key(for user: AppUser) -> String {
        "tle_itineraries_\(user.rawValue)"
    }
}
