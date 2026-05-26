import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif

/// Finer-grained activity types for the Track tab. The legacy `Sport`
/// enum is kept for feed filtering + backend compatibility (it only
/// knows the 7 broad categories); `SportSubtype` is what the user
/// actually picks before recording a ride. We store the subtype's
/// rawValue in `RideRecord.originalType` so the feed still groups
/// rides correctly via `canonicalSport`.
enum SportSubtype: String, CaseIterable, Hashable, Codable, Identifiable {
    // ── Cycling family ──────────────────────────────────────────────
    case roadCycling      = "RoadCycling"        // route
    case mountainBike     = "MountainBike"       // VTT
    case gravel           = "Gravel"
    case ebike            = "EBike"
    case indoorCycling    = "IndoorCycling"      // RPM / home trainer

    // ── Running / walking family ────────────────────────────────────
    case running          = "Running"
    case trailRunning     = "TrailRunning"
    case walking          = "Walking"
    case hiking           = "Hiking"             // randonnée
    case trekking         = "Trekking"           // trek long

    // ── Snow / water ────────────────────────────────────────────────
    case alpineSki        = "AlpineSki"
    case nordicSki        = "NordicSki"
    case snowshoe         = "Snowshoe"
    case swimming         = "Swimming"

    // ── Indoor fitness ──────────────────────────────────────────────
    case strength         = "Strength"           // muscu / haltères
    case hiit             = "HIIT"
    case yoga             = "Yoga"
    case pilates          = "Pilates"
    case rowingMachine    = "RowingMachine"
    case ellipticalTrainer = "Elliptical"
    case dance            = "Dance"

    var id: String { rawValue }

    /// The broad category this subtype belongs to. Drives the section
    /// grouping in the Track picker.
    var category: SportCategory {
        switch self {
        case .roadCycling, .mountainBike, .gravel, .ebike, .indoorCycling:
            return .cycling
        case .running, .trailRunning, .walking, .hiking, .trekking:
            return .footing
        case .alpineSki, .nordicSki, .snowshoe:
            return .snow
        case .swimming:
            return .water
        case .strength, .hiit, .yoga, .pilates, .rowingMachine, .ellipticalTrainer, .dance:
            return .indoor
        }
    }

    /// True when the subtype is recorded outdoors with a meaningful
    /// GPS trace — the Track view shows a map only for these. Indoor
    /// subtypes (RPM, pilates, muscu, …) get a metrics-only screen
    /// because their GPS trace is a useless dot.
    var isOutdoor: Bool {
        switch self {
        case .indoorCycling, .strength, .hiit, .yoga, .pilates,
             .rowingMachine, .ellipticalTrainer, .dance:
            return false
        default:
            return true
        }
    }

    var displayName: String {
        switch self {
        case .roadCycling:      return "Vélo route"
        case .mountainBike:     return "VTT"
        case .gravel:           return "Gravel"
        case .ebike:            return "Vélo électrique"
        case .indoorCycling:    return "Home trainer / RPM"
        case .running:          return "Course à pied"
        case .trailRunning:     return "Trail"
        case .walking:          return "Marche"
        case .hiking:           return "Randonnée"
        case .trekking:         return "Trek"
        case .alpineSki:        return "Ski alpin"
        case .nordicSki:        return "Ski de fond"
        case .snowshoe:         return "Raquettes"
        case .swimming:         return "Natation"
        case .strength:         return "Musculation"
        case .hiit:             return "HIIT"
        case .yoga:             return "Yoga"
        case .pilates:          return "Pilates"
        case .rowingMachine:    return "Rameur"
        case .ellipticalTrainer: return "Elliptique"
        case .dance:            return "Danse / Zumba"
        }
    }

    /// SF Symbol for the subtype.
    var symbol: String {
        switch self {
        case .roadCycling:      return "bicycle"
        case .mountainBike:     return "bicycle"
        case .gravel:           return "bicycle"
        case .ebike:            return "bolt.fill"
        case .indoorCycling:    return "figure.indoor.cycle"
        case .running:          return "figure.run"
        case .trailRunning:     return "figure.run.treadmill"
        case .walking:          return "figure.walk"
        case .hiking:           return "mountain.2.fill"
        case .trekking:         return "backpack.fill"
        case .alpineSki:        return "figure.skiing.downhill"
        case .nordicSki:        return "figure.skiing.crosscountry"
        case .snowshoe:         return "snowflake"
        case .swimming:         return "figure.pool.swim"
        case .strength:         return "dumbbell.fill"
        case .hiit:             return "flame.fill"
        case .yoga:             return "figure.yoga"
        case .pilates:          return "figure.pilates"
        case .rowingMachine:    return "figure.rower"
        case .ellipticalTrainer: return "figure.elliptical"
        case .dance:            return "figure.dance"
        }
    }

    /// Map back to the broad Sport enum used for feed filtering +
    /// backend round-tripping. Indoor sports map to .cycling for now
    /// (no dedicated "Salle" category yet) so they at least land
    /// somewhere consistent on the feed.
    var canonicalSport: Sport {
        switch self {
        case .roadCycling, .mountainBike, .gravel, .ebike, .indoorCycling:
            return .cycling
        case .running, .trailRunning:
            return .running
        case .walking:
            return .walking
        case .hiking, .trekking:
            return .hiking
        case .alpineSki, .nordicSki:
            return .ski
        case .snowshoe:
            return .snowshoe
        case .swimming:
            return .swim
        case .strength, .hiit, .yoga, .pilates, .rowingMachine,
             .ellipticalTrainer, .dance:
            // Indoor fitness has no perfect home in the legacy Sport
            // enum — pick cycling so it shows in the default feed.
            return .cycling
        }
    }

    /// MET-based calorie multiplier used by the indoor-metrics screen
    /// when no other estimate is available.
    var metEquivalent: Double {
        switch self {
        case .strength, .pilates, .yoga:    return 3.5
        case .hiit:                          return 8.0
        case .indoorCycling:                 return 7.5
        case .rowingMachine:                 return 7.0
        case .ellipticalTrainer:             return 5.0
        case .dance:                         return 6.0
        default:                             return 5.0
        }
    }

    #if canImport(SwiftUI)
    /// Subtype tint. We can't reach into AppColors here (Shared/ is
    /// linked from the Watch target too where AppColors isn't
    /// available) so the hex values mirror the AppColors light-mode
    /// palette inline.
    var color: Color {
        switch category {
        case .cycling:  return Color(red: 0.77, green: 0.38, blue: 0.16)   // terra  C4602A
        case .footing:  return Color(red: 0.42, green: 0.60, blue: 0.37)   // green  6B9A5E
        case .snow:     return Color(red: 0.29, green: 0.48, blue: 0.61)   // blue   4A7A9C
        case .water:    return Color(red: 0.20, green: 0.60, blue: 0.80)
        case .indoor:   return Color(red: 0.60, green: 0.40, blue: 0.70)
        }
    }
    #endif
}

enum SportCategory: String, CaseIterable, Identifiable {
    case cycling
    case footing
    case snow
    case water
    case indoor

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cycling: return "Vélo"
        case .footing: return "Course & marche"
        case .snow:    return "Neige"
        case .water:   return "Eau"
        case .indoor:  return "En salle"
        }
    }

    var symbol: String {
        switch self {
        case .cycling: return "bicycle"
        case .footing: return "figure.run"
        case .snow:    return "snowflake"
        case .water:   return "drop.fill"
        case .indoor:  return "dumbbell.fill"
        }
    }

    /// Subtypes in display order under this category.
    var subtypes: [SportSubtype] {
        SportSubtype.allCases.filter { $0.category == self }
    }
}
