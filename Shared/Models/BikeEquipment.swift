import Foundation

/// Mirror of the web's `EquipmentRow` / `EquipmentResponse` shape
/// returned by GET /api/equipment. Decoded straight from the JSON the
/// server computes — totals + per-item wear come pre-computed so the
/// iOS view doesn't have to re-sum activities locally.
struct EquipmentResponse: Decodable, Sendable {
    let totalKm: Double
    let items: [BikeEquipment]
}

struct BikeEquipment: Decodable, Sendable, Identifiable {
    let id: String
    let name: String
    let kind: String                  // SQL enum — matches BikeEquipmentKind below
    let installedAt: String           // ISO8601
    let installedAtKm: Double
    let lifetimeKm: Int
    let replacedAt: String?
    let notes: String?
    let totalKmToday: Double
    let kmSinceInstall: Double
    let wearRatio: Double

    enum CodingKeys: String, CodingKey {
        case id, name, kind
        case installedAt    = "installed_at"
        case installedAtKm  = "installed_at_km"
        case lifetimeKm     = "lifetime_km"
        case replacedAt     = "replaced_at"
        case notes
        case totalKmToday   = "totalKmToday"
        case kmSinceInstall = "kmSinceInstall"
        case wearRatio      = "wearRatio"
    }
}

/// Per-kind UI metadata. Mirrors the web's `KIND_META` map in
/// EquipmentPage.tsx so a piece's category, label, and icon are
/// identical on both surfaces. When adding a new kind here, add it
/// to the web's map too — they're the contract between client and
/// server.
enum BikeEquipmentKind {
    static func category(for kind: String) -> Category {
        switch kind {
        case "frame", "fork":
            return .cadre
        case "chain", "cassette", "crankset", "bottom_bracket",
             "derailleur_front", "derailleur_rear", "battery_di2":
            return .transmission
        case "brake_mount", "brake_lever_front", "brake_lever_rear",
             "brake_pads_front", "brake_pads_rear",
             "brake_rotor_front", "brake_rotor_rear":
            return .freins
        case "wheel_front", "wheel_rear",
             "tire_front", "tire_rear",
             "thru_axle_front", "thru_axle_rear":
            return .roues
        default:
            return .autre
        }
    }

    static func label(for kind: String) -> String {
        switch kind {
        case "frame":              return "Cadre"
        case "fork":               return "Fourche"
        case "chain":              return "Chaîne"
        case "cassette":           return "Cassette"
        case "crankset":           return "Pédalier"
        case "bottom_bracket":     return "Boîtier de pédalier"
        case "derailleur_front":   return "Dérailleur avant"
        case "derailleur_rear":    return "Dérailleur arrière"
        case "battery_di2":        return "Batterie Di2"
        case "brake_mount":        return "Adaptateur frein"
        case "brake_lever_front":  return "Levier frein avant"
        case "brake_lever_rear":   return "Levier frein arrière"
        case "brake_pads_front":   return "Plaquettes avant"
        case "brake_pads_rear":    return "Plaquettes arrière"
        case "brake_rotor_front":  return "Disque avant"
        case "brake_rotor_rear":   return "Disque arrière"
        case "wheel_front":        return "Roue avant"
        case "wheel_rear":         return "Roue arrière"
        case "tire_front":         return "Pneu avant"
        case "tire_rear":          return "Pneu arrière"
        case "thru_axle_front":    return "Axe traversant avant"
        case "thru_axle_rear":     return "Axe traversant arrière"
        case "cables":             return "Câbles + gaines"
        case "bar_tape":           return "Guidoline"
        case "pedals":             return "Pédales"
        default:                   return "Autre"
        }
    }

    /// SF Symbols glyph for each kind. SwiftUI-native, scales with
    /// Dynamic Type, and renders the same on every device.
    static func symbol(for kind: String) -> String {
        switch kind {
        case "frame", "fork":      return "bicycle"
        case "chain":              return "link"
        case "cassette":           return "circle.dotted"
        case "crankset", "pedals": return "gearshape.2"
        case "bottom_bracket":     return "circle.circle"
        case "derailleur_front",
             "derailleur_rear":    return "arrow.triangle.swap"
        case "battery_di2":        return "battery.75percent"
        case "brake_mount":        return "wrench.adjustable"
        case "brake_lever_front",
             "brake_lever_rear":   return "hand.point.up.left"
        case "brake_pads_front",
             "brake_pads_rear":    return "rectangle.compress.vertical"
        case "brake_rotor_front",
             "brake_rotor_rear":   return "circle.dashed"
        case "wheel_front",
             "wheel_rear":         return "circle"
        case "tire_front",
             "tire_rear":          return "circle.dashed.inset.filled"
        case "thru_axle_front",
             "thru_axle_rear":     return "line.diagonal"
        case "cables":             return "cable.connector"
        case "bar_tape":           return "scribble"
        default:                   return "plus.circle"
        }
    }

    enum Category: String, CaseIterable {
        case cadre, transmission, freins, roues, autre

        var label: String {
            switch self {
            case .cadre:        return "Cadre"
            case .transmission: return "Transmission"
            case .freins:       return "Freins"
            case .roues:        return "Roues"
            case .autre:        return "Autre"
            }
        }
    }
}
