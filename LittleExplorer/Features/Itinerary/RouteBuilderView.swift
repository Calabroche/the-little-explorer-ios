import SwiftUI

/// "Parcours auto" — port of `src/components/explorer/RouteBuilder.tsx`.
/// User sets target distance + elevation + terrain + direction; we run
/// a hard filter (±5 km distance always, ±10% elev in strict mode) over
/// `PlannerLibrary.routes`, score the survivors, and return the top 5.
/// If nothing passes strict, we fall back to a distance-only filter and
/// flag the result as approximate.
struct RouteBuilderView: View {
    @Environment(AppEnvironment.self) private var environment

    @State private var targetDist: Double = 25
    @State private var targetElev: Double = 300
    @State private var terrain: TerrainFilter = .any
    @State private var direction: DirectionFilter = .any
    @State private var hasGenerated: Bool = false
    @State private var didSeedDefaults: Bool = false

    enum TerrainFilter: String, CaseIterable { case any, flat, hilly
        var label: String { self == .any ? "Indifférent" : self == .flat ? "Plat / roulant" : "Vallonné / cols" }
    }
    enum DirectionFilter: Hashable {
        case any
        case fixed(LoopDirection)
        var label: String {
            switch self {
            case .any:              return "Surprise"
            case .fixed(let d):     return d.rawValue
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                intro
                form
                generateButton
                if hasGenerated {
                    let result = computeMatches()
                    if result.approximate {
                        approximateBanner
                    }
                    if result.matches.isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: 10) {
                            ForEach(result.matches) { route in
                                NavigationLink(value: LoopSuggestion(
                                    id: route.id,
                                    category: nil,
                                    title: route.name,
                                    distanceKm: Int(route.distanceKm),
                                    elevationM: Int(route.elevationM),
                                    tss: estimatedTss(for: route),
                                    cues: cues(for: route),
                                    desc: "Boucle au départ et arrivée de Chemin du Manoir, Dardilly. \(route.waypoints.count) points clés.",
                                    colorHex: colorHex(for: route, approximate: result.approximate),
                                )) {
                                    routeCard(route: route, approximate: result.approximate)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .background(AppColors.cream)
        .onAppear { seedDefaultsIfNeeded() }
        .onChange(of: environment.activityStore.activities.count) { _, _ in
            didSeedDefaults = false
            seedDefaultsIfNeeded()
        }
    }

    // MARK: - Header + intro

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text("§ PLANIFICATEUR").font(.system(size: 10).weight(.bold)).tracking(1.5).foregroundStyle(AppColors.terra)
                Rectangle().fill(AppColors.creamBorder).frame(width: 20, height: 1)
                Text("CRÉE TON PROCHAIN PARCOURS").font(.system(size: 10).weight(.bold)).tracking(1.5).foregroundStyle(AppColors.inkMid)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Construis ta sortie.")
                    .font(.system(.title, design: .serif).weight(.heavy))
                    .foregroundStyle(AppColors.ink)
                Text("Quatre outils, une page.")
                    .font(.system(.title, design: .serif).weight(.bold).italic())
                    .foregroundStyle(AppColors.terra)
            }
            .padding(.top, 4)
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Génère une boucle depuis Dardilly avec une distance + un dénivelé cibles. L'algo te propose un tracé parmi 38 boucles préconçues.")
                .font(.system(size: 12)).foregroundStyle(AppColors.inkLight).lineSpacing(2)
            (Text("Toutes les boucles partent & arrivent à Chemin du Manoir, Dardilly. Distance respectée à ")
                + Text("±5 km").bold().foregroundColor(AppColors.terra)
                + Text(" (toujours), D+ à ")
                + Text("±10%").bold().foregroundColor(AppColors.terra)
                + Text(" en mode strict."))
                .font(.system(size: 11)).foregroundStyle(AppColors.inkMid).lineSpacing(2)
        }
    }

    // MARK: - Form

    private var form: some View {
        VStack(spacing: 14) {
            slider(label: "DISTANCE", value: $targetDist, range: 10...120, step: 1, unit: "km")
            slider(label: "DÉNIVELÉ POSITIF", value: $targetElev, range: 50...1000, step: 10, unit: "m")
            terrainPicker
            directionPicker
        }
        .padding(14)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppColors.creamBorder, lineWidth: 1))
    }

    private func slider(label: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(.system(size: 10).weight(.bold)).tracking(1.2).foregroundStyle(AppColors.inkLight)
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(Int(value.wrappedValue))")
                        .font(.system(.title2, design: .serif).weight(.bold))
                        .foregroundStyle(AppColors.ink)
                    Text(unit).font(.system(size: 11)).foregroundStyle(AppColors.inkLight)
                }
            }
            Slider(value: value, in: range, step: step)
                .tint(AppColors.terra)
            HStack {
                Text("\(Int(range.lowerBound)) \(unit)").font(.system(size: 9)).foregroundStyle(AppColors.inkLight)
                Spacer()
                Text("\(Int(range.upperBound)) \(unit)").font(.system(size: 9)).foregroundStyle(AppColors.inkLight)
            }
        }
    }

    private var terrainPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TYPE DE TERRAIN").font(.system(size: 10).weight(.bold)).tracking(1.2).foregroundStyle(AppColors.inkLight)
            HStack(spacing: 6) {
                ForEach(TerrainFilter.allCases, id: \.self) { t in
                    chip(label: t.label, selected: terrain == t) {
                        terrain = t
                    }
                }
                Spacer()
            }
        }
    }

    private var directionPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DIRECTION DEPUIS DARDILLY").font(.system(size: 10).weight(.bold)).tracking(1.2).foregroundStyle(AppColors.inkLight)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip(label: "Surprise", selected: direction == .any) { direction = .any }
                    ForEach(LoopDirection.allCases, id: \.self) { d in
                        chip(label: d.rawValue, selected: direction == .fixed(d)) {
                            direction = .fixed(d)
                        }
                    }
                }
            }
        }
    }

    private func chip(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12).weight(selected ? .bold : .medium))
                .foregroundStyle(selected ? AppColors.terra : AppColors.inkMid)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(selected ? AppColors.terraLight : AppColors.creamDark, in: RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(selected ? AppColors.terra : AppColors.creamBorder, lineWidth: 1),
                )
        }
        .buttonStyle(.plain)
    }

    private var generateButton: some View {
        Button {
            hasGenerated = true
        } label: {
            Text("GÉNÉRER MES PARCOURS  →")
                .font(.system(size: 12).weight(.bold)).tracking(1.5)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppColors.terra, in: RoundedRectangle(cornerRadius: 3))
        }
        .buttonStyle(.plain)
    }

    private var approximateBanner: some View {
        HStack(alignment: .top) {
            Rectangle().fill(AppColors.terra).frame(width: 3)
            Text("Aucune boucle exacte trouvée. Voici les plus proches en distance — D+ et direction approximatifs.")
                .font(.system(size: 11)).foregroundStyle(AppColors.inkMid).lineSpacing(2)
            Spacer()
        }
        .padding(10)
        .background(AppColors.creamDark, in: RoundedRectangle(cornerRadius: 3))
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 18)).foregroundStyle(AppColors.inkLight)
            Text("Aucune boucle dans cette plage de distance.").font(.system(size: 12)).foregroundStyle(AppColors.inkLight)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private func routeCard(route: LibraryRoute, approximate: Bool) -> some View {
        let colorHex = colorHex(for: route, approximate: approximate)
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(approximate ? "APPROXIMATION" : "GÉNÉRÉ")
                    .font(.system(size: 10).weight(.bold)).tracking(1.2)
                    .foregroundStyle(.white)
                Spacer()
                Text("VOIR LE TRACÉ →")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(hex: colorHex))

            VStack(alignment: .leading, spacing: 10) {
                Text(route.name)
                    .font(.system(.title3, design: .serif).weight(.bold))
                    .foregroundStyle(AppColors.ink)

                HStack(spacing: 0) {
                    statColumn(label: "DISTANCE", value: "\(Int(route.distanceKm))", unit: "km", color: AppColors.ink)
                    statColumn(label: "D+",       value: "\(Int(route.elevationM))", unit: "m",  color: AppColors.ink)
                    statColumn(label: "DIR.",     value: route.direction.rawValue,   unit: "",   color: AppColors.terra)
                    statColumn(label: "TSS",      value: "\(estimatedTss(for: route))", unit: "", color: Color(hex: colorHex))
                }
            }
            .padding(14)
        }
        .background(AppColors.surface)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppColors.creamBorder, lineWidth: 1))
        .cornerRadius(4)
    }

    private func statColumn(label: String, value: String, unit: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 9).weight(.bold)).tracking(1.0).foregroundStyle(AppColors.inkLight)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.system(.title2, design: .serif).weight(.bold)).foregroundStyle(color)
                if !unit.isEmpty {
                    Text(unit).font(.system(size: 10)).foregroundStyle(AppColors.inkLight)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Filtering

    private func computeMatches() -> (matches: [LibraryRoute], approximate: Bool) {
        let inp = BuilderInputs(targetDist: targetDist, targetElev: targetElev, direction: direction, terrain: terrain)
        let strict = PlannerLibrary.routes
            .filter { passesHardFilter($0, inp: inp) }
            .map { ($0, scoreRoute($0, inp: inp)) }
            .sorted { $0.1 < $1.1 }
            .prefix(5)
            .map { $0.0 }
        if !strict.isEmpty { return (Array(strict), false) }

        let fallback = PlannerLibrary.routes
            .filter { isWithinDistanceWindow($0, target: inp.targetDist) }
            .map { ($0, scoreRoute($0, inp: inp)) }
            .sorted { $0.1 < $1.1 }
            .prefix(5)
            .map { $0.0 }
        return (Array(fallback), true)
    }

    private struct BuilderInputs {
        let targetDist: Double
        let targetElev: Double
        let direction: DirectionFilter
        let terrain: TerrainFilter
    }

    private let distToleranceKm: Double = 5
    private let elevTolerance: Double = 0.10

    private func isWithinDistanceWindow(_ r: LibraryRoute, target: Double) -> Bool {
        abs(r.distanceKm - target) <= distToleranceKm
    }

    private func passesHardFilter(_ r: LibraryRoute, inp: BuilderInputs) -> Bool {
        if !isWithinDistanceWindow(r, target: inp.targetDist) { return false }
        if abs(r.elevationM - inp.targetElev) / max(inp.targetElev, 1) > elevTolerance { return false }
        switch inp.terrain {
        case .any:   break
        case .flat:  if r.hilly { return false }
        case .hilly: if !r.hilly { return false }
        }
        switch inp.direction {
        case .any:           break
        case .fixed(let d):
            if r.direction != d, !d.adjacent.contains(r.direction) { return false }
        }
        return true
    }

    private func scoreRoute(_ r: LibraryRoute, inp: BuilderInputs) -> Double {
        let distScore = abs(r.distanceKm - inp.targetDist) / max(inp.targetDist, 1)
        let elevScore = abs(r.elevationM - inp.targetElev) / max(inp.targetElev, 1)
        var dirScore: Double = 0
        if case .fixed(let d) = inp.direction {
            if r.direction == d { dirScore = 0 }
            else if d.adjacent.contains(r.direction) { dirScore = 0.3 }
            else { dirScore = 0.8 }
        }
        var terrainScore: Double = 0
        switch inp.terrain {
        case .any: terrainScore = 0
        case .flat:  terrainScore = r.hilly ? 0.5 : 0
        case .hilly: terrainScore = r.hilly ? 0 : 0.5
        }
        return distScore * 2 + elevScore * 1.5 + dirScore + terrainScore
    }

    // MARK: - Helpers

    private func estimatedTss(for route: LibraryRoute) -> Int {
        let avg = computeAvg()
        let ratio = route.distanceKm / max(avg.dist, 1)
        let mult = route.hilly ? 1.15 : 1.0
        return Int((Double(avg.tss) * ratio * mult).rounded())
    }

    private func cues(for route: LibraryRoute) -> [String] {
        var cues: [String] = []
        if route.hilly {
            cues.append("Gérer l'effort dans les montées")
        } else {
            cues.append("Rythme régulier, sans à-coups")
        }
        if route.distanceKm >= 40 {
            cues.append("Ravitaillement toutes les 45 min")
        }
        cues.append("Départ et arrivée Chemin du Manoir, Dardilly")
        return cues
    }

    private func colorHex(for route: LibraryRoute, approximate: Bool) -> String {
        if approximate { return "C4602A" }
        if route.hilly { return route.distanceKm >= 40 ? "5A7A9E" : "C4602A" }
        return route.distanceKm >= 30 ? "9B6FB5" : "C4602A"
    }

    private func computeAvg() -> (dist: Double, elev: Double, tss: Int) {
        let activities = environment.activityStore.filtered(by: environment.selectedSport)
            .sorted(by: { $0.rawDate > $1.rawDate })
        let last5 = Array(activities.prefix(5))
        guard !last5.isEmpty else { return (25, 300, 80) }
        let dist = last5.map { $0.distance ?? 0 }.reduce(0, +) / Double(last5.count)
        let elev = last5.map { $0.elevation ?? 0 }.reduce(0, +) / Double(last5.count)
        let tssVals = last5.compactMap { $0.tss }
        let tss = tssVals.isEmpty ? 80 : Int(Double(tssVals.reduce(0, +)) / Double(tssVals.count))
        return (dist, elev, tss)
    }

    private func seedDefaultsIfNeeded() {
        guard !didSeedDefaults else { return }
        let avg = computeAvg()
        targetDist = max(10, min(120, avg.dist))
        targetElev = max(50, min(1000, avg.elev))
        didSeedDefaults = true
    }
}
