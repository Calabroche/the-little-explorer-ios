import Foundation
import Observation
import os

/// Watch-side cache of itineraries pushed by the iPhone via
/// WCSession.updateApplicationContext.
///
/// One source of truth: whatever the iPhone last sent. WCSession's
/// application context is a snapshot — the OS delivers the *latest*
/// value to the Watch when reachability permits, dropping intermediate
/// updates that are no longer relevant. Perfect fit for a library that
/// the user mutates rarely and reads frequently.
///
/// We persist the decoded list to a JSON file in the Watch's sandbox
/// so a launch with no WCSession yet (Watch booted but not yet paired)
/// still shows the last-known list — better than an empty picker.
@Observable
@MainActor
final class ItineraryCache {
    private(set) var items: [Itinerary] = []

    private let logger = Logger(subsystem: "com.calabrese.little-explorer-ios.watchkitapp", category: "ItineraryCache")
    private let url: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.url = docs.appendingPathComponent("itineraries.json")
        loadFromDisk()
    }

    /// Replace the cache with a fresh list (typically just-decoded
    /// from a WCSession context). Persists to disk so the next launch
    /// has the same list before WCSession has a chance to push again.
    func set(_ list: [Itinerary]) {
        items = list
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(list)
            try data.write(to: url, options: .atomic)
            logger.notice("Itinerary cache updated: \(list.count, privacy: .public) items")
        } catch {
            logger.warning("Persist failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([Itinerary].self, from: data) {
            items = decoded
        }
    }
}
