import Foundation

/// Mirrors the web app's SportId — the 7 supported activity types plus
/// helpers to map between the backend's `type` string and the enum.
enum Sport: String, CaseIterable, Identifiable, Codable, Sendable {
    case cycling
    case running
    case hiking
    case ski
    case snowshoe
    case walking
    case swim

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cycling:  return "Vélo"
        case .running:  return "Course"
        case .hiking:   return "Rando"
        case .ski:      return "Ski"
        case .snowshoe: return "Raquettes"
        case .walking:  return "Marche"
        case .swim:     return "Natation"
        }
    }

    var symbol: String {
        switch self {
        case .cycling:  return "bicycle"
        case .running:  return "figure.run"
        case .hiking:   return "mountain.2.fill"
        case .ski:      return "figure.skiing.downhill"
        case .snowshoe: return "snowflake"
        case .walking:  return "figure.walk"
        case .swim:     return "figure.pool.swim"
        }
    }

    /// Pages that only make sense for one sport. Mirrors the web app's
    /// nav-item filtering (Itinerary / Planner / FTP are cycling-only).
    var supportsCycling: Bool { self == .cycling }
}

extension Sport {
    /// Resolve the backend's `type` field to a Sport. Returns nil for
    /// unknown values (so they get filtered rather than crashing).
    init?(backendType: String) {
        switch backendType.lowercased() {
        case "cycling", "ride", "ebikeride":            self = .cycling
        case "running", "run":                          self = .running
        case "hiking", "hike":                          self = .hiking
        case "ski", "alpineski", "nordicski":           self = .ski
        case "snowshoe":                                self = .snowshoe
        case "walking", "walk":                         self = .walking
        case "swim", "swimming":                        self = .swim
        default: return nil
        }
    }
}

extension Array where Element == RideRecord {
    /// Filter to a single sport.
    func filtered(by sport: Sport) -> [RideRecord] {
        filter { Sport(backendType: $0.type) == sport }
    }

    /// All distinct sports actually present in the data — used to drive
    /// the sport picker so users only see what their account has.
    var availableSports: [Sport] {
        let raw = compactMap { Sport(backendType: $0.type) }
        var seen: Set<Sport> = []
        var ordered: [Sport] = []
        for s in raw where !seen.contains(s) {
            seen.insert(s)
            ordered.append(s)
        }
        // Keep canonical order from Sport.allCases for stable UI.
        return Sport.allCases.filter { ordered.contains($0) }
    }
}
