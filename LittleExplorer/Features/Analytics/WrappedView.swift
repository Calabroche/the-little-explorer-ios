import SwiftUI

/// Year-in-review carousel — mirrors the web's WrappedPage with 8 cards
/// (cover, distance, elevation vs. Mont Blanc, count, longest ride,
/// biggest climb, top sport, best month, outro). Auto-advances every
/// 5.5s; tap left edge to go back, right edge to skip forward.
struct WrappedView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var year: Int?
    @State private var cardIndex: Int = 0
    @State private var paused: Bool = false
    @State private var advanceTask: Task<Void, Never>?

    private static let autoAdvanceSeconds: Double = 5.5
    private static let montBlanc: Double = 4810

    var body: some View {
        let activities = environment.activityStore.filtered(by: environment.selectedSport)
        let availableYears = availableYears(activities: activities)

        Group {
            if availableYears.isEmpty || year == nil || compute(year: year!, activities: activities) == nil {
                VStack(spacing: 12) {
                    Image(systemName: "sparkles").font(.system(size: 28)).foregroundStyle(AppColors.inkLight)
                    Text("Pas encore d'activité.").font(.caption).foregroundStyle(AppColors.inkLight)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppColors.cream)
            } else {
                let stats = compute(year: year!, activities: activities)!
                let cards = visibleCards(stats: stats)
                let safeIndex = min(cardIndex, cards.count - 1)
                let card = cards[safeIndex]

                ZStack {
                    card.background
                        .ignoresSafeArea()
                        .animation(.easeInOut(duration: 0.5), value: cardIndex)

                    VStack(spacing: 0) {
                        topBar(cards: cards, currentIndex: safeIndex, availableYears: availableYears, fg: card.fg)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                        Spacer(minLength: 0)
                    }

                    GeometryReader { geo in
                        Color.clear.contentShape(Rectangle())
                            .onTapGesture { location in
                                if location.x < geo.size.width * 0.25 { previous(cardCount: cards.count) }
                                else { advance(cardCount: cards.count) }
                            }
                    }

                    cardBody(card: card, stats: stats)
                        .padding(.horizontal, 28)
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if year == nil { year = availableYears.first }
            scheduleAdvance(activities: activities)
        }
        .onDisappear { advanceTask?.cancel() }
        .onChange(of: year) { _, _ in
            cardIndex = 0
            scheduleAdvance(activities: activities)
        }
        .onChange(of: cardIndex) { _, _ in scheduleAdvance(activities: activities) }
        .onChange(of: paused) { _, _ in scheduleAdvance(activities: activities) }
    }

    // MARK: - Cards

    private struct Card {
        let key: String
        let fg: Color
        let accent: Color
        let background: AnyView
        let render: (YearStats) -> AnyView
    }

    private func visibleCards(stats: YearStats) -> [Card] {
        var cards: [Card] = []

        // 0 — Cover
        cards.append(Card(
            key: "cover",
            fg: .white,
            accent: .white,
            background: AnyView(LinearGradient(colors: [AppColors.terra, AppColors.terraLight], startPoint: .topLeading, endPoint: .bottomTrailing)),
            render: { stats in
                AnyView(
                    VStack(alignment: .leading, spacing: 14) {
                        Text("BILAN").font(.system(size: 11).weight(.semibold)).tracking(2).foregroundStyle(.white.opacity(0.9))
                        Text("\(stats.year)")
                            .font(.system(size: 120, design: .serif).weight(.heavy))
                            .foregroundStyle(.white)
                        Text("Une année à pédaler.")
                            .font(.system(.title, design: .serif).weight(.bold).italic())
                            .foregroundStyle(.white.opacity(0.95))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading),
                )
            },
        ))

        // 1 — Total distance
        cards.append(Card(
            key: "distance",
            fg: AppColors.ink, accent: AppColors.terra,
            background: AnyView(LinearGradient(colors: [AppColors.cream, AppColors.creamDark], startPoint: .topLeading, endPoint: .bottomTrailing)),
            render: { stats in AnyView(bigNumberCard(tag: "DISTANCE", number: stats.distance.formatted(), unit: "km", caption: "Vous avez parcouru autant de kilomètres cette année.", fg: AppColors.ink, accent: AppColors.terra)) },
        ))

        // 2 — Elevation
        cards.append(Card(
            key: "elevation",
            fg: AppColors.ink, accent: AppColors.green,
            background: AnyView(LinearGradient(colors: [AppColors.cream, AppColors.creamDark], startPoint: .topLeading, endPoint: .bottomTrailing)),
            render: { stats in
                let blancs = (Double(stats.elevation) / Self.montBlanc * 10).rounded() / 10
                let caption = blancs >= 0.5
                    ? "Soit \(String(format: "%.1f", blancs)) Mont Blanc gravi\(blancs > 1 ? "s" : "")."
                    : "Cumulés sur l'année."
                return AnyView(bigNumberCard(tag: "DÉNIVELÉ POSITIF", number: stats.elevation.formatted(), unit: "m D+", caption: caption, fg: AppColors.ink, accent: AppColors.green))
            },
        ))

        // 3 — Count + hours
        cards.append(Card(
            key: "count",
            fg: .white, accent: .white,
            background: AnyView(LinearGradient(colors: [AppColors.green, AppColors.greenLight], startPoint: .topLeading, endPoint: .bottomTrailing)),
            render: { stats in
                AnyView(
                    VStack(alignment: .leading, spacing: 28) {
                        Text("AU TOTAL").font(.system(size: 11).weight(.semibold)).tracking(2).foregroundStyle(.white.opacity(0.9))
                        VStack(alignment: .leading, spacing: 24) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(stats.count)").font(.system(size: 110, design: .serif).weight(.heavy)).foregroundStyle(.white)
                                Text("ACTIVITÉS").font(.system(size: 13).weight(.semibold)).tracking(2).foregroundStyle(.white.opacity(0.9))
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(stats.hours)h").font(.system(size: 80, design: .serif).weight(.bold)).foregroundStyle(.white.opacity(0.92))
                                Text("HEURES À TRACER").font(.system(size: 13).weight(.semibold)).tracking(2).foregroundStyle(.white.opacity(0.9))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading),
                )
            },
        ))

        // 4 — Longest
        if let longest = stats.longest {
            cards.append(Card(
                key: "longest",
                fg: AppColors.ink, accent: AppColors.terra,
                background: AnyView(LinearGradient(colors: [AppColors.cream, AppColors.creamDark], startPoint: .topLeading, endPoint: .bottomTrailing)),
                render: { _ in
                    AnyView(bigNumberCard(
                        tag: "LA PLUS LONGUE",
                        number: "\(Int((longest.distance ?? 0).rounded()))",
                        unit: "km",
                        caption: "\(longest.title)\n\(longest.date)\(longest.elevation.map { " · \(Int($0)) m D+" } ?? "")",
                        fg: AppColors.ink,
                        accent: AppColors.terra,
                    ))
                },
            ))
        }

        // 5 — Biggest climb
        if let climb = stats.biggestClimb, (climb.elevation ?? 0) >= 100 {
            cards.append(Card(
                key: "climb",
                fg: AppColors.ink, accent: AppColors.blue,
                background: AnyView(LinearGradient(colors: [AppColors.cream, AppColors.creamDark], startPoint: .topLeading, endPoint: .bottomTrailing)),
                render: { _ in
                    AnyView(bigNumberCard(
                        tag: "L'ASCENSION",
                        number: "\(Int((climb.elevation ?? 0).rounded()))",
                        unit: "m D+",
                        caption: "\(climb.title)\n\(climb.date) · \(Int((climb.distance ?? 0).rounded())) km",
                        fg: AppColors.ink,
                        accent: AppColors.blue,
                    ))
                },
            ))
        }

        // 6 — Top sport
        if let top = stats.topSport {
            cards.append(Card(
                key: "topSport",
                fg: .white, accent: .white,
                background: AnyView(LinearGradient(colors: [AppColors.blue, AppColors.creamDark], startPoint: .topLeading, endPoint: .bottomTrailing)),
                render: { _ in
                    AnyView(
                        VStack(alignment: .leading, spacing: 24) {
                            Text("VOTRE SPORT FAVORI").font(.system(size: 11).weight(.semibold)).tracking(2).foregroundStyle(.white.opacity(0.9))
                            Text(top.sport.displayName)
                                .font(.system(size: 90, design: .serif).weight(.heavy))
                                .foregroundStyle(.white)
                            Text("\(top.count) sortie\(top.count > 1 ? "s" : "") · \(Int(top.distance.rounded())) km parcourus.")
                                .font(.system(.title3, design: .serif).italic())
                                .foregroundStyle(.white.opacity(0.95))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading),
                    )
                },
            ))
        }

        // 7 — Best month
        if let bestMonth = stats.bestMonth {
            cards.append(Card(
                key: "bestMonth",
                fg: AppColors.ink, accent: AppColors.terra,
                background: AnyView(LinearGradient(colors: [AppColors.cream, AppColors.creamDark], startPoint: .topLeading, endPoint: .bottomTrailing)),
                render: { stats in
                    let monthName = monthNames[bestMonth.idx]
                    let maxDist = stats.monthlyDist.max() ?? 1
                    return AnyView(
                        VStack(alignment: .leading, spacing: 16) {
                            Text("LE MOIS RECORD").font(.system(size: 11).weight(.semibold)).tracking(2).foregroundStyle(AppColors.terra)
                            Text(monthName)
                                .font(.system(size: 90, design: .serif).weight(.heavy))
                                .foregroundStyle(AppColors.ink)
                            Text("\(Int(bestMonth.distance.rounded())) km parcourus.")
                                .font(.system(.title3, design: .serif).italic())
                                .foregroundStyle(AppColors.inkMid)
                            HStack(alignment: .bottom, spacing: 4) {
                                ForEach(0..<12, id: \.self) { i in
                                    let h = maxDist > 0 ? CGFloat(stats.monthlyDist[i] / maxDist * 100) : 0
                                    let isBest = i == bestMonth.idx
                                    VStack(spacing: 4) {
                                        Rectangle()
                                            .fill(isBest ? AppColors.terra : AppColors.inkLight.opacity(0.4))
                                            .frame(maxWidth: .infinity)
                                            .frame(height: Swift.max(stats.monthlyDist[i] > 0 ? 3 : 0, h))
                                            .clipShape(RoundedRectangle(cornerRadius: 2))
                                        Text(monthNames[i].prefix(3).uppercased())
                                            .font(.system(size: 9))
                                            .foregroundStyle(AppColors.inkLight)
                                    }
                                }
                            }
                            .frame(height: 110, alignment: .bottom)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading),
                    )
                },
            ))
        }

        // 8 — Outro
        cards.append(Card(
            key: "outro",
            fg: .white, accent: .white,
            background: AnyView(LinearGradient(colors: [AppColors.terra, AppColors.green], startPoint: .topLeading, endPoint: .bottomTrailing)),
            render: { stats in
                AnyView(
                    VStack(alignment: .leading, spacing: 24) {
                        Text("MERCI POUR \(stats.year)").font(.system(size: 12).weight(.semibold)).tracking(2).foregroundStyle(.white.opacity(0.9))
                        Text("À l'an prochain.")
                            .font(.system(.largeTitle, design: .serif).weight(.heavy).italic())
                            .foregroundStyle(.white)
                        Text("\(stats.count) sorties · \(stats.distance.formatted()) km · \(stats.elevation.formatted()) m D+ · \(stats.hours)h sur la route.")
                            .font(.system(.body, design: .serif))
                            .foregroundStyle(.white.opacity(0.95))
                            .lineSpacing(4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading),
                )
            },
        ))

        return cards
    }

    private func bigNumberCard(tag: String, number: String, unit: String?, caption: String?, fg: Color, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(tag).font(.system(size: 11).weight(.semibold)).tracking(2).foregroundStyle(accent)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(number).font(.system(size: 90, design: .serif).weight(.heavy)).foregroundStyle(fg)
                if let unit { Text(unit).font(.system(size: 22)).foregroundStyle(accent) }
            }
            if let caption {
                Text(caption)
                    .font(.system(.body, design: .serif).italic())
                    .foregroundStyle(fg.opacity(0.85))
                    .lineSpacing(4)
                    .frame(maxWidth: 540, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func cardBody(card: Card, stats: YearStats) -> some View {
        card.render(stats)
            .id(card.key)
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    private func topBar(cards: [Card], currentIndex: Int, availableYears: [Int], fg: Color) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(cards.indices, id: \.self) { i in
                    let active = i == currentIndex
                    Rectangle()
                        .fill(active ? fg.opacity(0.95) : fg.opacity(0.3))
                        .frame(height: 2)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 1))
                }
            }
            HStack(spacing: 6) {
                ForEach(availableYears, id: \.self) { y in
                    let active = year == y
                    Button {
                        year = y
                    } label: {
                        Text("\(y)")
                            .font(.system(size: 11).weight(active ? .bold : .medium))
                            .tracking(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .foregroundStyle(active ? AppColors.ink : fg)
                            .background(active ? Color.white : Color.white.opacity(0.18), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button {
                    paused.toggle()
                } label: {
                    Image(systemName: paused ? "play.fill" : "pause.fill")
                        .foregroundStyle(fg)
                        .padding(8)
                        .background(Color.white.opacity(0.18), in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Year stats

    private struct YearStats {
        let year: Int
        let count: Int
        let distance: Int
        let elevation: Int
        let hours: Int
        let longest: RideRecord?
        let biggestClimb: RideRecord?
        let topSport: TopSport?
        let bestMonth: BestMonth?
        let monthlyDist: [Double]
    }

    private struct TopSport { let sport: Sport; let count: Int; let distance: Double }
    private struct BestMonth { let idx: Int; let distance: Double }

    private func availableYears(activities: [RideRecord]) -> [Int] {
        let calendar = Calendar(identifier: .gregorian)
        var set = Set<Int>()
        for a in activities {
            if let d = RideDate.parse(a.rawDate) {
                set.insert(calendar.component(.year, from: d))
            }
        }
        return set.sorted(by: >)
    }

    private func compute(year: Int, activities: [RideRecord]) -> YearStats? {
        let calendar = Calendar(identifier: .gregorian)
        let inYear = activities.filter {
            guard let d = RideDate.parse($0.rawDate) else { return false }
            return calendar.component(.year, from: d) == year
        }
        guard !inYear.isEmpty else { return nil }

        let distance = Int(inYear.compactMap(\.distance).reduce(0, +).rounded())
        let elevation = Int(inYear.compactMap(\.elevation).reduce(0, +).rounded())
        let hours = Int((Double(inYear.map(\.durationMin).reduce(0, +)) / 60).rounded())

        let longest = inYear.max(by: { ($0.distance ?? 0) < ($1.distance ?? 0) })
        let biggestClimb = inYear.max(by: { ($0.elevation ?? 0) < ($1.elevation ?? 0) })

        var sportAgg: [Sport: (count: Int, distance: Double)] = [:]
        for a in inYear {
            guard let s = Sport(backendType: a.type) else { continue }
            var entry = sportAgg[s] ?? (0, 0)
            entry.count += 1
            entry.distance += a.distance ?? 0
            sportAgg[s] = entry
        }
        let top = sportAgg.max(by: { $0.value.distance < $1.value.distance }).map {
            TopSport(sport: $0.key, count: $0.value.count, distance: $0.value.distance)
        }

        var monthly = Array(repeating: 0.0, count: 12)
        for a in inYear {
            guard let d = RideDate.parse(a.rawDate) else { continue }
            let m = calendar.component(.month, from: d) - 1
            if monthly.indices.contains(m) { monthly[m] += a.distance ?? 0 }
        }
        let bestIdx = monthly.indices.max(by: { monthly[$0] < monthly[$1] }) ?? 0
        let bestMonth = monthly[bestIdx] > 0 ? BestMonth(idx: bestIdx, distance: monthly[bestIdx]) : nil

        return YearStats(
            year: year,
            count: inYear.count,
            distance: distance,
            elevation: elevation,
            hours: hours,
            longest: longest,
            biggestClimb: biggestClimb,
            topSport: top,
            bestMonth: bestMonth,
            monthlyDist: monthly,
        )
    }

    // MARK: - Auto-advance

    private func scheduleAdvance(activities: [RideRecord]) {
        advanceTask?.cancel()
        guard !paused else { return }
        advanceTask = Task { [year, cardIndex] in
            try? await Task.sleep(for: .seconds(Self.autoAdvanceSeconds))
            guard !Task.isCancelled, year == self.year, cardIndex == self.cardIndex else { return }
            let stats = self.year.flatMap { self.compute(year: $0, activities: activities) }
            let count = stats.map { self.visibleCards(stats: $0).count } ?? 0
            advance(cardCount: count)
        }
    }

    @MainActor
    private func advance(cardCount: Int) {
        guard cardCount > 0 else { return }
        cardIndex = (cardIndex + 1) % cardCount
    }

    @MainActor
    private func previous(cardCount: Int) {
        guard cardCount > 0 else { return }
        cardIndex = (cardIndex - 1 + cardCount) % cardCount
    }

    private let monthNames = [
        "Janvier", "Février", "Mars", "Avril", "Mai", "Juin",
        "Juillet", "Août", "Septembre", "Octobre", "Novembre", "Décembre",
    ]
}
