import Foundation

/// One row in the bike maintenance log — "what I did to the bike,
/// when". Mirrors the web's `ServiceEvent` from
/// `src/components/explorer/pages/ServiceLogPanel.tsx` so iOS and web
/// agree on the schema.
struct ServiceEvent: Decodable, Sendable, Identifiable, Hashable {
    let id: String
    let gearId: String?
    let gearName: String?
    let kind: ServiceKind
    let date: String          // ISO8601 (date only, no time)
    let kmAtEvent: Double?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id
        case gearId     = "gear_id"
        case gearName   = "gear_name"
        case kind
        case date
        case kmAtEvent  = "km_at_event"
        case notes
    }
}

/// Server-computed "next due" snapshot per maintenance kind. The
/// server walks the user's events, looks up the recommended interval
/// for each kind (km + days), and emits one row per kind with a
/// status flag the UI uses to highlight what's overdue.
struct NextDue: Decodable, Sendable, Identifiable, Hashable {
    let kind: ServiceKind
    let lastDate: String?
    let lastKm: Double?
    let kmSince: Double?
    let daysSince: Double?
    let kmInterval: Double?
    let dayInterval: Double?
    let status: Status

    var id: ServiceKind { kind }

    enum Status: String, Decodable, Sendable {
        case fresh, due, overdue, unknown
    }

    enum CodingKeys: String, CodingKey {
        case kind
        case lastDate    = "last_date"
        case lastKm      = "last_km"
        case kmSince     = "km_since"
        case daysSince   = "days_since"
        case kmInterval  = "km_interval"
        case dayInterval = "day_interval"
        case status
    }
}

/// Response shape from GET /api/service-events.
struct ServiceEventResponse: Decodable, Sendable {
    let events: [ServiceEvent]
    let dueByKind: [NextDue]
}

extension ISO8601DateFormatter {
    /// "yyyy-MM-dd" — matches the server's expected `date` field on
    /// POST /api/service-events. Lives in Shared so both the API
    /// client and any view that does its own date math can reuse it.
    static let dateOnly: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()
}

/// Closed enum of supported maintenance kinds. Stays in sync with the
/// SQL `service_kind` enum on the server. Adding a new kind requires
/// migrating the DB, updating the server interval table, and adding
/// label + icon below — all three sides have to agree.
enum ServiceKind: String, Codable, Sendable, Hashable, CaseIterable {
    case chainLube           = "chain_lube"
    case chainClean          = "chain_clean"
    case brakeBleed          = "brake_bleed"
    case brakePadsCheck      = "brake_pads_check"
    case wheelTrue           = "wheel_true"
    case tirePressure        = "tire_pressure"
    case derailleurTune      = "derailleur_tune"
    case bottomBracketCheck  = "bottom_bracket_check"
    case cableCheck          = "cable_check"
    case bikeWash            = "bike_wash"
    case generalService      = "general_service"
    case other

    /// French label used in the UI. Same wording as the web's
    /// KIND_LABEL map for consistency.
    var label: String {
        switch self {
        case .chainLube:          return "Lubrification chaîne"
        case .chainClean:         return "Nettoyage transmission"
        case .brakeBleed:         return "Purge freins"
        case .brakePadsCheck:     return "Vérif plaquettes"
        case .wheelTrue:          return "Voilage roue"
        case .tirePressure:       return "Pression pneus"
        case .derailleurTune:     return "Réglage dérailleurs"
        case .bottomBracketCheck: return "Vérif boîtier pédalier"
        case .cableCheck:         return "Vérif câbles"
        case .bikeWash:           return "Lavage vélo"
        case .generalService:     return "Révision complète"
        case .other:              return "Autre intervention"
        }
    }

    /// SF Symbol used on iOS (the web uses Unicode glyphs — SF
    /// Symbols give iOS a sharper feel + free dark-mode color
    /// inheritance).
    var systemImage: String {
        switch self {
        case .chainLube:          return "drop.fill"
        case .chainClean:         return "sparkles"
        case .brakeBleed:         return "bandage.fill"
        case .brakePadsCheck:     return "circle.grid.cross"
        case .wheelTrue:          return "circle.dashed"
        case .tirePressure:       return "gauge.with.dots.needle.50percent"
        case .derailleurTune:     return "gearshape.2.fill"
        case .bottomBracketCheck: return "gear.circle.fill"
        case .cableCheck:         return "cable.connector.horizontal"
        case .bikeWash:           return "shower.fill"
        case .generalService:     return "wrench.and.screwdriver.fill"
        case .other:              return "ellipsis.circle"
        }
    }

    /// Display order — most-frequent / most-important first so the
    /// carnet reads top-down naturally.
    static let displayOrder: [ServiceKind] = [
        .chainLube, .chainClean,
        .brakePadsCheck, .brakeBleed,
        .tirePressure,
        .derailleurTune,
        .wheelTrue, .bottomBracketCheck, .cableCheck,
        .bikeWash, .generalService, .other,
    ]

    /// Same intervals the server hard-codes. iOS doesn't compute the
    /// "next due" status locally (the server does that), but we use
    /// these to label the empty-state cards ("Jamais effectué.
    /// Intervalle recommandé : 200 km") without an extra round-trip.
    var recommendedInterval: (km: Double?, days: Int?) {
        switch self {
        case .chainLube:          return (200,  nil)
        case .chainClean:         return (500,  nil)
        case .brakeBleed:         return (5000, 365)
        case .brakePadsCheck:     return (1000, nil)
        case .wheelTrue:          return (3000, nil)
        case .tirePressure:       return (nil,  7)
        case .derailleurTune:     return (2000, nil)
        case .bottomBracketCheck: return (5000, nil)
        case .cableCheck:         return (5000, nil)
        case .bikeWash:           return (500,  14)
        case .generalService:     return (8000, 365)
        case .other:              return (nil,  nil)
        }
    }
}
