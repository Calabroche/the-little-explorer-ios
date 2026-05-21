import SwiftUI

/// "Sorties suggérées" — port of `src/components/explorer/RouteProposals.tsx`.
/// 6 hardcoded proposal categories, each scaled relative to the user's
/// last-5-rides averages (distance / elevation / TSS). Tapping a card
/// pushes a detail view listing its 5 alternate tracks.
struct RouteProposalsView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
        }
        .background(AppColors.cream)
    }

    @ViewBuilder
    private var content: some View {
        let activities = environment.activityStore.filtered(by: environment.selectedSport)
            .sorted(by: { $0.rawDate > $1.rawDate })
        let last5 = Array(activities.prefix(5))

        if last5.count < 2 {
            VStack(spacing: 8) {
                Image(systemName: "sparkles").font(.system(size: 24)).foregroundStyle(AppColors.inkLight)
                Text("Pas encore assez de sorties pour proposer des parcours.")
                    .font(.system(size: 12)).foregroundStyle(AppColors.inkLight)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(40)
        } else {
            let avg = computeAverages(last5: last5)
            let proposals = makeProposals(avg: avg)

            VStack(alignment: .leading, spacing: 12) {
                header(avg: avg)
                ForEach(proposals) { p in
                    NavigationLink(value: p) {
                        proposalCard(p)
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationDestination(for: LoopSuggestion.self) { p in
                LoopSuggestionDetailView(suggestion: p)
            }
        }
    }

    private func header(avg: Averages) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text("§ ROUTES").font(.system(size: 10).weight(.bold)).tracking(1.5).foregroundStyle(AppColors.green)
                Rectangle().fill(AppColors.creamBorder).frame(width: 20, height: 1)
                Text("6 SORTIES PROPOSÉES").font(.system(size: 10).weight(.bold)).tracking(1.5).foregroundStyle(AppColors.inkMid)
            }
            Text("Basé sur tes 5 dernières sorties · dist. moy. \(avg.distKm) km · D+ moy. \(avg.elevM) m · TSS moy. \(avg.tss)")
                .font(.system(size: 11)).foregroundStyle(AppColors.inkLight)
                .italic()
        }
    }

    private func proposalCard(_ p: LoopSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(p.category?.tag ?? "")
                    .font(.system(size: 10).weight(.bold)).tracking(1.2)
                    .foregroundStyle(.white)
                Spacer()
                Text("VOIR LE TRACÉ →")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(hex: p.colorHex))

            VStack(alignment: .leading, spacing: 12) {
                Text(p.title)
                    .font(.system(.title3, design: .serif).weight(.bold))
                    .foregroundStyle(AppColors.ink)

                HStack(spacing: 0) {
                    statColumn(label: "DISTANCE", value: "\(p.distanceKm)", unit: "km", color: AppColors.ink)
                    statColumn(label: "D+",       value: "\(p.elevationM)", unit: "m",  color: AppColors.ink)
                    statColumn(label: "TSS",      value: "\(p.tss)",        unit: "",   color: Color(hex: p.colorHex))
                }
                .padding(.bottom, 10)
                .overlay(Rectangle().fill(AppColors.creamBorder).frame(height: 1), alignment: .bottom)

                Text(p.desc)
                    .font(.system(size: 12)).foregroundStyle(AppColors.inkMid)
                    .lineSpacing(2)

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(p.cues.enumerated()), id: \.offset) { _, cue in
                        HStack(alignment: .top, spacing: 6) {
                            Text("›").foregroundStyle(Color(hex: p.colorHex)).font(.system(size: 11))
                            Text(cue).font(.system(size: 11)).foregroundStyle(AppColors.inkLight)
                        }
                    }
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

    // MARK: - Computation

    private struct Averages { let distKm: Int; let elevM: Int; let tss: Int }

    private func computeAverages(last5: [RideRecord]) -> Averages {
        let distKm = Int((last5.map { $0.distance ?? 0 }.reduce(0, +)) / Double(last5.count))
        let elevM  = Int((last5.map { $0.elevation ?? 0 }.reduce(0, +)) / Double(last5.count))
        let tssVals = last5.compactMap { $0.tss }
        let tss = tssVals.isEmpty ? 80 : Int(Double(tssVals.reduce(0, +)) / Double(tssVals.count))
        return Averages(distKm: distKm, elevM: elevM, tss: tss)
    }

    private func makeProposals(avg: Averages) -> [LoopSuggestion] {
        let d = Double(avg.distKm)
        let e = Double(avg.elevM)
        let tss = Double(avg.tss)

        return [
            LoopSuggestion(
                id: "progression",
                category: .progression,
                title: ProposalCategory.progression.title,
                distanceKm: Int((d * 1.1).rounded()),
                elevationM: Int((e * 1.05).rounded()),
                tss: Int((tss * 1.1).rounded()),
                cues: [
                    "Montée progressive dès le départ",
                    "Maintenir cadence en crête",
                    "Retour en Z2",
                ],
                desc: "Boucles propres ~\(Int((d * 0.9).rounded()))-\(Int((d * 1.15).rounded())) km autour de Dardilly. IF cible 0.75–0.80.",
                colorHex: "C4602A",
            ),
            LoopSuggestion(
                id: "climb",
                category: .climb,
                title: ProposalCategory.climb.title,
                distanceKm: Int((d * 0.85).rounded()),
                elevationM: Int((e * 1.4).rounded()),
                tss: Int((tss * 1.15).rounded()),
                cues: [
                    "D+ cible : ~\(Int((e * 1.4).rounded())) m",
                    "Montées à 60–75% FC max",
                    "Descentes prudence côté Saône",
                ],
                desc: "D+ ×1.4 via les crêtes des Monts d'Or. Montées à 60–75% FCmax.",
                colorHex: "6B9A5E",
            ),
            LoopSuggestion(
                id: "recovery",
                category: .recovery,
                title: ProposalCategory.recovery.title,
                distanceKm: Int((d * 0.62).rounded()),
                elevationM: Int((e * 0.45).rounded()),
                tss: Int((tss * 0.5).rounded()),
                cues: [
                    "FC < 65% FCmax strictement",
                    "Terrain roulant",
                    "Effort ressenti 4/10 max",
                ],
                desc: "Zone 1–2 uniquement, \(Int((d * 0.5).rounded()))–\(Int((d * 0.75).rounded())) km. TSS cible < \(Int((tss * 0.55).rounded())).",
                colorHex: "4A7A9C",
            ),
            LoopSuggestion(
                id: "volume",
                category: .volume,
                title: ProposalCategory.volume.title,
                distanceKm: Int((d * 1.2).rounded()),
                elevationM: Int(e.rounded()),
                tss: Int((tss * 1.2).rounded()),
                cues: [
                    "Rythme Z2 constant",
                    "Ravitaillement toutes les 45 min",
                    "Ne pas forcer en montée",
                ],
                desc: "+\(Int((d * 0.2).rounded())) km de volume (~\(Int((d * 1.0).rounded()))-\(Int((d * 1.4).rounded())) km). Z2, temps en selle maximal.",
                colorHex: "9B6FB5",
            ),
            LoopSuggestion(
                id: "volume-relief",
                category: .volumeRelief,
                title: ProposalCategory.volumeRelief.title,
                distanceKm: Int((d * 1.2).rounded()),
                elevationM: Int((e * 1.15).rounded()),
                tss: Int((tss * 1.35).rounded()),
                cues: [
                    "Gérer l'effort sur les cols",
                    "Ravitaillement solide",
                    "Récup complète le lendemain",
                ],
                desc: "+\(Int((d * 0.2).rounded())) km ET +\(Int((e * 0.15).rounded())) m D+. Sortie exigeante (~\(Int((d * 1.0).rounded()))-\(Int((d * 1.4).rounded())) km).",
                colorHex: "C4602A",
            ),
            LoopSuggestion(
                id: "big",
                category: .big,
                title: ProposalCategory.big.title,
                distanceKm: 50,
                elevationM: Int((e * 1.3).rounded()),
                tss: Int((tss * 1.5).rounded()),
                cues: [
                    "Sortir tôt le matin",
                    "Prévoir 2 bidons + barre",
                    "Rythme Z2 sauf montées clés",
                ],
                desc: "6 tracés de 40 à 60 km. Choisis selon ta forme du jour.",
                colorHex: "4A7A9C",
            ),
        ]
    }
}

/// Placeholder detail view for a proposed loop. The web version opens
/// RouteModal with a Leaflet map preview + GPX export — porting that
/// fully would require OSRM integration on iOS. For now we show the
/// metadata and cues, with a "Build it in Itinéraire" prompt.
struct LoopSuggestionDetailView: View {
    let suggestion: LoopSuggestion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(suggestion.title)
                    .font(.system(.largeTitle, design: .serif).weight(.heavy))
                    .foregroundStyle(AppColors.ink)

                HStack(spacing: 24) {
                    stat(label: "DISTANCE", value: "\(suggestion.distanceKm)", unit: "km")
                    stat(label: "D+",       value: "\(suggestion.elevationM)", unit: "m")
                    stat(label: "TSS",      value: "\(suggestion.tss)",        unit: "")
                }

                Text(suggestion.desc)
                    .font(.system(size: 14)).foregroundStyle(AppColors.inkMid)
                    .lineSpacing(3)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("CONSEILS").font(.system(size: 10).weight(.bold)).tracking(1.4).foregroundStyle(AppColors.terra)
                    ForEach(Array(suggestion.cues.enumerated()), id: \.offset) { _, cue in
                        HStack(alignment: .top, spacing: 8) {
                            Text("›").foregroundStyle(Color(hex: suggestion.colorHex))
                            Text(cue).font(.system(size: 13)).foregroundStyle(AppColors.inkMid)
                        }
                    }
                }

                Spacer()
                Text("Construis le tracé dans l'onglet Itinéraire pour avoir la carte + le GPX.")
                    .font(.system(size: 11).italic())
                    .foregroundStyle(AppColors.inkLight)
            }
            .padding(16)
        }
        .background(AppColors.cream)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func stat(label: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 9).weight(.bold)).tracking(1.0).foregroundStyle(AppColors.inkLight)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.system(.title, design: .serif).weight(.bold)).foregroundStyle(AppColors.ink)
                if !unit.isEmpty {
                    Text(unit).font(.system(size: 11)).foregroundStyle(AppColors.inkLight)
                }
            }
        }
    }
}
