import Foundation

/// French/English text + arrow glyphs for OSRM maneuvers. Drives the
/// turn-by-turn banner and the voice prompts.
enum ManeuverFormatter {
    enum Lang { case fr, en }

    static func arrow(for step: NavStep?) -> String {
        guard let step else { return "✓" }
        if step.type == "arrive" { return "🏁" }
        if step.type == "depart" { return "▲" }
        if step.type == "roundabout" || step.type == "rotary" { return "↻" }
        switch step.modifier {
        case "left":         return "←"
        case "sharp left":   return "⤺"
        case "slight left":  return "↖"
        case "right":        return "→"
        case "sharp right":  return "⤻"
        case "slight right": return "↗"
        case "uturn":        return "⤴"
        default:             return "↑"
        }
    }

    /// Short core phrase, no distance, no street.
    static func core(_ step: NavStep, lang: Lang = .fr) -> String {
        let dict = phrases(for: lang)
        switch step.type {
        case "depart": return dict.depart
        case "arrive": return dict.arrive
        case "roundabout", "rotary":
            if let exit = step.exit, exit > 0, exit < ordinals.count {
                let ord = lang == .fr ? ordinals[exit] : "\(exit)"
                return dict.roundabout.replacingOccurrences(of: "{n}", with: ord)
            }
            return dict.roundaboutNoExit
        default: break
        }
        switch step.modifier {
        case "left":         return dict.turnLeft
        case "right":        return dict.turnRight
        case "slight left":  return dict.slightLeft
        case "slight right": return dict.slightRight
        case "sharp left":   return dict.sharpLeft
        case "sharp right":  return dict.sharpRight
        case "uturn":        return dict.uturn
        default:             return dict.continue
        }
    }

    /// Speech-ready sentence with distance prefix and street name.
    static func sentence(_ step: NavStep, distance: Double?, lang: Lang = .fr) -> String {
        let dict = phrases(for: lang)
        let core = core(step, lang: lang)
        let onto: String = {
            guard !step.name.isEmpty,
                  step.type != "arrive",
                  step.type != "depart" else { return "" }
            return dict.onto.replacingOccurrences(of: "{name}", with: step.name)
        }()
        guard let distance, step.type != "arrive" else { return core + onto }
        if distance < 30 { return core + onto }
        return dict.inDistance.replacingOccurrences(of: "{d}", with: distanceText(distance, lang: lang))
            + core.lowercased() + onto
    }

    static func distanceText(_ meters: Double, lang: Lang = .fr) -> String {
        if meters < 30 { return lang == .fr ? "maintenant" : "now" }
        if meters < 1000 { return "\(Int((meters / 10).rounded()) * 10) m" }
        return String(format: "%.1f km", meters / 1000)
    }

    enum AnnounceLevel: String {
        case far, mid, near, now
    }

    /// Decide whether a fresh announcement should fire at this distance,
    /// given what's already been said for this step. Schedules ~1.2km / ~500m
    /// / ~150m / ~30m prompts.
    static func pickAnnouncement(
        distance: Double,
        already: Set<AnnounceLevel>,
    ) -> AnnounceLevel? {
        if distance < 30, !already.contains(.now) { return .now }
        if distance < 150, !already.contains(.near) { return .near }
        if distance < 500, !already.contains(.mid) { return .mid }
        if distance < 1200, !already.contains(.far) { return .far }
        return nil
    }

    // MARK: - Vocabulary

    private struct Phrases {
        let depart, arrive, `continue`, turnLeft, turnRight, slightLeft, slightRight,
            sharpLeft, sharpRight, uturn, roundabout, roundaboutNoExit, inDistance, onto: String
    }

    private static let ordinals = ["", "1ère", "2e", "3e", "4e", "5e", "6e", "7e"]

    private static func phrases(for lang: Lang) -> Phrases {
        switch lang {
        case .fr:
            return Phrases(
                depart: "Départ",
                arrive: "Vous êtes arrivé",
                continue: "Continuez tout droit",
                turnLeft: "Tournez à gauche",
                turnRight: "Tournez à droite",
                slightLeft: "Légère gauche",
                slightRight: "Légère droite",
                sharpLeft: "Tournez fortement à gauche",
                sharpRight: "Tournez fortement à droite",
                uturn: "Faites demi-tour",
                roundabout: "Au rond-point, prenez la {n} sortie",
                roundaboutNoExit: "Au rond-point",
                inDistance: "Dans {d}, ",
                onto: " sur {name}",
            )
        case .en:
            return Phrases(
                depart: "Start",
                arrive: "You have arrived",
                continue: "Continue straight",
                turnLeft: "Turn left",
                turnRight: "Turn right",
                slightLeft: "Slight left",
                slightRight: "Slight right",
                sharpLeft: "Sharp left",
                sharpRight: "Sharp right",
                uturn: "Make a U-turn",
                roundabout: "At the roundabout, take exit {n}",
                roundaboutNoExit: "At the roundabout",
                inDistance: "In {d}, ",
                onto: " onto {name}",
            )
        }
    }
}
