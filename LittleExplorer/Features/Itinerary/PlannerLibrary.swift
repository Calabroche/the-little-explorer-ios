import Foundation

/// Cardinal direction from the Dardilly HOME anchor. Used by both
/// RouteBuilder (filtering) and RouteProposals (route variants).
enum LoopDirection: String, CaseIterable, Hashable, Codable {
    case n = "N", ne = "NE", e = "E", se = "SE", s = "S", sw = "SW", w = "W", nw = "NW"

    /// Compass-adjacent directions (±45°). Used by the route filter to
    /// keep neighbouring orientations in scope.
    var adjacent: [LoopDirection] {
        switch self {
        case .n:  return [.ne, .nw]
        case .ne: return [.n,  .e]
        case .e:  return [.ne, .se]
        case .se: return [.e,  .s]
        case .s:  return [.se, .sw]
        case .sw: return [.s,  .w]
        case .w:  return [.sw, .nw]
        case .nw: return [.w,  .n]
        }
    }
}

/// A predefined loop from Chemin du Manoir, Dardilly. Waypoints are
/// listed in order of traversal. Mirrors the LIBRARY array in
/// `RouteBuilder.tsx`. Coordinates are pinned to D-road intersections
/// so OSRM (or any router) sticks to major roads.
struct LibraryRoute: Identifiable, Hashable {
    let id: String
    let name: String
    let distanceKm: Double
    let elevationM: Double
    let direction: LoopDirection
    let hilly: Bool
    let waypoints: [Coordinate]
}

/// One of the 6 proposal categories. Mirrors the inline tag/color/title
/// triplets in `RouteProposals.tsx`. Kept as an enum so tracks +
/// scaling + description live with the category.
enum ProposalCategory: String, CaseIterable, Hashable {
    case progression, climb, recovery, volume, volumeRelief, big

    var tag: String {
        switch self {
        case .progression:  return "PROGRESSION +10%"
        case .climb:        return "TRAVAIL D+"
        case .recovery:     return "RÉCUPÉRATION ACTIVE"
        case .volume:       return "COURSE AUX KM +20%"
        case .volumeRelief: return "KM + DÉNIVELÉ +20%/+15%"
        case .big:          return "40-60 KM"
        }
    }

    var title: String {
        switch self {
        case .progression:  return "Classique boucle"
        case .climb:        return "Cols des Monts d'Or"
        case .recovery:     return "Sortie légère"
        case .volume:       return "Longue distance"
        case .volumeRelief: return "Volume & relief"
        case .big:          return "Grande boucle"
        }
    }
}

/// One generated suggestion shown as a card. Same shape used by both
/// RouteProposals and RouteBuilder.
struct LoopSuggestion: Identifiable, Hashable {
    let id: String
    let category: ProposalCategory?
    let title: String
    let distanceKm: Int
    let elevationM: Int
    let tss: Int
    let cues: [String]
    let desc: String
    /// Hex color shown on the card chip header.
    let colorHex: String
}

/// Predefined 38-route library. Same coordinates as the web's
/// `LIBRARY` constant — kept in sync by hand. If you add a route here
/// keep it in the same band order (short / hilly / endurance / long).
enum PlannerLibrary {
    /// Home anchor for every loop: Chemin du Manoir, Dardilly.
    static let home = Coordinate(lat: 45.8183, lng: 4.7521)

    static let routes: [LibraryRoute] = [
        // Récup & courtes
        r("marcy",           "Marcy / Charbonnières",         13, 100, .s,  false, [(45.7848,4.7591),(45.7806,4.7280)]),
        r("lent-aller",      "Lentilly aller",                14, 130, .nw, false, [(45.8351,4.6965),(45.8170,4.7048)]),
        r("sd-doux",         "Saint-Didier doux",             15, 180, .ne, false, [(45.8316,4.7706),(45.8418,4.7894)]),
        r("loz-plat",        "Lozanne plat",                  17, 220, .nw, false, [(45.8351,4.6965),(45.8514,4.6826)]),
        r("3villages",       "Tour des trois villages",       19, 200, .s,  false, [(45.7937,4.7770),(45.7848,4.7591),(45.7806,4.7280)]),
        r("lent-charbo-doux","Lentilly / Charbonnières doux", 20, 230, .w,  false, [(45.8351,4.6965),(45.8170,4.7048),(45.7848,4.7591)]),

        // Multi-sommets courts à fort D+
        r("cindre",          "Mont Cindre direct",            14, 320, .ne, true,  [(45.8316,4.7706),(45.8553,4.7921),(45.8418,4.7894)]),
        r("verdun-cindre",   "Mont Verdun + Mont Cindre",     16, 430, .n,  true,  [(45.8316,4.7706),(45.8418,4.7894),(45.8553,4.7921),(45.7937,4.7770)]),
        r("sc-sr",           "Saint-Cyr / Saint-Romain",      18, 480, .ne, true,  [(45.8316,4.7706),(45.8553,4.7921),(45.8385,4.8197),(45.8418,4.7894)]),
        r("triple-mdor",     "Triple sommet Monts d'Or",      20, 550, .n,  true,  [(45.8316,4.7706),(45.8553,4.7921),(45.8385,4.8197),(45.8553,4.7921),(45.8418,4.7894)]),
        r("cindre-champ",    "Mont Cindre × Champagne ×2",    22, 600, .ne, true,  [(45.8316,4.7706),(45.8553,4.7921),(45.8418,4.7894),(45.7937,4.7770),(45.8316,4.7706),(45.8553,4.7921)]),

        // Endurance moyennes
        r("verdun",          "Mont Verdun",                   22, 380, .ne, true,  [(45.8316,4.7706),(45.8553,4.7921),(45.8418,4.7894)]),
        r("lent-class",      "Lentilly classique",            22, 260, .w,  false, [(45.8351,4.6965),(45.8170,4.7048),(45.7848,4.7591)]),
        r("civ-loz",         "Civrieux / Lozanne",            24, 300, .nw, false, [(45.8316,4.7706),(45.8666,4.7191),(45.8514,4.6826)]),
        r("marcy-lent",      "Marcy / Lentilly",              26, 280, .w,  false, [(45.8351,4.6965),(45.8170,4.7048),(45.7806,4.7280),(45.7848,4.7591)]),
        r("sc-boucle",       "Saint-Cyr boucle",              28, 420, .ne, true,  [(45.8316,4.7706),(45.8418,4.7894),(45.8553,4.7921),(45.7937,4.7770)]),

        // Course aux km
        r("loz-grand",       "Lozanne grand tour",            30, 380, .nw, false, [(45.8316,4.7706),(45.8666,4.7191),(45.8514,4.6826),(45.8170,4.7048)]),
        r("vaug",            "Vaugneray",                     32, 480, .sw, true,  [(45.8170,4.7048),(45.7501,4.7065),(45.7848,4.7591)]),
        r("chessy-civ",      "Chessy via Civrieux",           34, 460, .nw, true,  [(45.8316,4.7706),(45.8666,4.7191),(45.8980,4.6828),(45.8514,4.6826)]),
        r("arbresle-plat",   "L'Arbresle plat",               36, 420, .w,  false, [(45.8170,4.7048),(45.8369,4.6175),(45.7848,4.7591)]),
        r("chessy-chazay",   "Chessy via Chazay",             38, 480, .nw, true,  [(45.8316,4.7706),(45.8666,4.7191),(45.8765,4.6990),(45.8980,4.6828),(45.8514,4.6826)]),

        // Volume + relief
        r("triple-col",      "Triple col Monts d'Or",         40, 600, .n,  true,  [(45.8316,4.7706),(45.8918,4.7765),(45.8915,4.8089),(45.8385,4.8197),(45.8553,4.7921),(45.8418,4.7894)]),
        r("chessy-vaug",     "Chessy / Vaugneray",            43, 520, .w,  true,  [(45.8514,4.6826),(45.8980,4.6828),(45.8170,4.7048),(45.7501,4.7065),(45.7848,4.7591)]),
        r("curis-pol",       "Curis / Poleymieux complet",    46, 620, .n,  true,  [(45.8316,4.7706),(45.8918,4.7765),(45.8915,4.8089),(45.8385,4.8197),(45.8553,4.7921),(45.8418,4.7894),(45.7937,4.7770)]),
        r("arbresle-vaug",   "L'Arbresle / Vaugneray",        50, 580, .w,  true,  [(45.8514,4.6826),(45.8369,4.6175),(45.7501,4.7065),(45.7848,4.7591)]),

        // Grandes boucles
        r("sainbel-arb",     "Sain-Bel / L'Arbresle",         55, 680, .w,  true,  [(45.8514,4.6826),(45.8369,4.6175),(45.8204,4.5703),(45.7501,4.7065),(45.7848,4.7591)]),
        r("tarare-vaug",     "Tarare / Vaugneray",            60, 760, .w,  true,  [(45.8514,4.6826),(45.8369,4.6175),(45.8989,4.4310),(45.7501,4.7065),(45.7848,4.7591)]),

        // Très longues : Beaujolais
        r("pontcharra",      "Pontcharra / Tarare",           70, 850,  .w,  true, [(45.8514,4.6826),(45.8980,4.6828),(45.9249,4.5908),(45.8728,4.5077),(45.8204,4.5703),(45.7501,4.7065),(45.7848,4.7591)]),
        r("oingt-tarare",    "Oingt / Tarare",                75, 900,  .w,  true, [(45.8514,4.6826),(45.8980,4.6828),(45.9285,4.5894),(45.8989,4.4310),(45.8204,4.5703),(45.7501,4.7065)]),
        r("beauj-sud",       "Tour Beaujolais sud",           85, 1050, .nw, true, [(45.9362,4.7224),(45.8944,4.6633),(45.9162,4.6122),(45.9285,4.5894),(45.8989,4.4310),(45.8204,4.5703),(45.7501,4.7065)]),
        r("beauj-crus",      "Tour crus du Beaujolais",       95, 1200, .nw, true, [(45.9362,4.7224),(45.8944,4.6633),(45.9249,4.5908),(45.9162,4.6122),(45.8989,4.4310),(45.8728,4.5077),(45.8204,4.5703),(45.7501,4.7065)]),
        r("beauj-grande",    "Grande randonnée Beaujolais",  110, 1400, .nw, true, [(45.9362,4.7224),(45.8944,4.6633),(45.9249,4.5908),(45.9162,4.6122),(45.8989,4.4310),(45.8581,4.5158),(45.8728,4.5077),(45.8204,4.5703),(45.7501,4.7065)]),
    ]

    private static func r(_ id: String, _ name: String, _ dist: Double, _ elev: Double, _ dir: LoopDirection, _ hilly: Bool, _ pts: [(Double, Double)]) -> LibraryRoute {
        LibraryRoute(
            id: id, name: name,
            distanceKm: dist, elevationM: elev,
            direction: dir, hilly: hilly,
            waypoints: pts.map { Coordinate(lat: $0.0, lng: $0.1) },
        )
    }
}
