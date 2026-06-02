import SwiftUI
import Charts

/// Native mirror of the web's /admin/metrics dashboard. Fetches the same
/// `GET /api/admin/metrics` endpoint and renders the KPI tiles, a 30-day
/// DAU chart, the onboarding funnel, Strava-sync health, and a per-user
/// activity tail (one expandable row per user). Restricted to the
/// allowlist — the server returns 403 for anyone else.
///
/// Keep in rough sync with src/app/admin/metrics/page.tsx on the web.
struct AdminMetricsView: View {
    @Environment(AppEnvironment.self) private var environment

    @State private var metrics: APIClient.AdminMetrics?
    @State private var loadState: LoadState = .idle

    enum LoadState: Equatable { case idle, loading, loaded, failed(String) }

    var body: some View {
        Group {
            switch loadState {
            case .idle, .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let msg):
                ContentUnavailableView("Erreur", systemImage: "exclamationmark.triangle", description: Text(msg))
            case .loaded:
                if let metrics {
                    content(metrics)
                }
            }
        }
        .background(AppColors.cream.ignoresSafeArea())
        .navigationTitle("Métriques")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func content(_ m: APIClient.AdminMetrics) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                kpiGrid(m.totals)
                dauSection(m.dau)
                funnelSection(m.funnel)
                syncSection(m.sync)
                ActivityTailSection(recent: m.recent)
            }
            .padding(16)
        }
    }

    // MARK: KPI tiles

    private func kpiGrid(_ t: APIClient.AdminMetrics.Totals) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            kpi("Utilisateurs", t.users)
            kpi("DAU auj.",     t.dauToday)
            kpi("Signups 7j",   t.signups7d)
            kpi("Activités",    t.activities)
            kpi("Events 7j",    t.events7d)
            kpi("Exports",      t.exportsTotal)
        }
    }

    private func kpi(_ label: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(value)")
                .font(.system(size: 22, design: .serif).weight(.heavy))
                .foregroundStyle(AppColors.ink)
            Text(label.uppercased())
                .font(.system(size: 9).weight(.bold))
                .tracking(0.6)
                .foregroundStyle(AppColors.inkLight)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppColors.creamBorder, lineWidth: 1))
    }

    // MARK: DAU chart

    private func dauSection(_ dau: [APIClient.AdminMetrics.DauPoint]) -> some View {
        Card("DAU — 30 jours") {
            if dau.isEmpty {
                Text("Pas de données.").font(.caption).foregroundStyle(AppColors.inkLight)
            } else {
                Chart(dau) { p in
                    BarMark(
                        x: .value("Jour", p.day),
                        y: .value("Utilisateurs", p.count),
                    )
                    .foregroundStyle(AppColors.terra)
                }
                .chartXAxis(.hidden)
                .frame(height: 140)
            }
        }
    }

    // MARK: Funnel

    private func funnelSection(_ f: APIClient.AdminMetrics.Funnel) -> some View {
        let steps: [(String, Int)] = [
            ("Signup",          f.signup),
            ("Bienvenue vue",   f.welcomeDone),
            ("Sport choisi",    f.sportDone),
            ("Profil rempli",   f.profileDone),
            ("Strava connecté", f.stravaConnected),
            ("(skip Strava)",   f.stravaSkipped),
            ("Complete",        f.complete),
        ]
        let maxVal = max(steps.map(\.1).max() ?? 1, 1)
        return Card("Onboarding") {
            VStack(spacing: 8) {
                ForEach(steps.indices, id: \.self) { i in
                    let step = steps[i]
                    HStack(spacing: 10) {
                        Text(step.0)
                            .font(.system(size: 12))
                            .foregroundStyle(AppColors.inkMid)
                            .frame(width: 110, alignment: .leading)
                            .lineLimit(1)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3).fill(AppColors.creamBorder)
                                RoundedRectangle(cornerRadius: 3).fill(AppColors.terra)
                                    .frame(width: max(2, geo.size.width * CGFloat(step.1) / CGFloat(maxVal)))
                            }
                        }
                        .frame(height: 14)
                        Text("\(step.1)")
                            .font(.system(size: 12).weight(.semibold))
                            .foregroundStyle(AppColors.ink)
                            .frame(width: 38, alignment: .trailing)
                    }
                }
            }
        }
    }

    // MARK: Sync

    private func syncSection(_ s: APIClient.AdminMetrics.Sync) -> some View {
        Card("Sync Strava — 7 jours") {
            HStack(spacing: 12) {
                miniStat("Reçus",  "\(s.received7d)")
                miniStat("Syncés", "\(s.synced7d)")
                miniStat("Succès", "\(Int((s.successRate * 100).rounded()))%")
            }
        }
    }

    private func miniStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 18, design: .serif).weight(.bold))
                .foregroundStyle(AppColors.ink)
            Text(label.uppercased())
                .font(.system(size: 9).weight(.bold))
                .tracking(0.6)
                .foregroundStyle(AppColors.inkLight)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Load

    private func load() async {
        loadState = .loading
        do {
            let fetched = try await environment.api.adminMetrics()
            await MainActor.run {
                metrics = fetched
                loadState = .loaded
            }
        } catch {
            await MainActor.run {
                loadState = .failed(error.localizedDescription)
            }
        }
    }
}

// MARK: - Card wrapper

private struct Card<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 10).weight(.bold))
                .tracking(1.2)
                .foregroundStyle(AppColors.terra)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppColors.creamBorder, lineWidth: 1))
    }
}

// MARK: - Per-user activity tail

private struct ActivityTailSection: View {
    let recent: [APIClient.AdminMetrics.RecentEvent]

    private struct UserGroup: Identifiable {
        let id: String
        let name: String
        let events: [APIClient.AdminMetrics.RecentEvent]
        let last: String
    }

    private var groups: [UserGroup] {
        var order: [String] = []
        var map: [String: [APIClient.AdminMetrics.RecentEvent]] = [:]
        for e in recent {
            let key = e.userId ?? "__anon__"
            if map[key] == nil { map[key] = []; order.append(key) }
            map[key]?.append(e)
        }
        return order.map { key -> UserGroup in
            let evs  = map[key] ?? []
            let name = evs.first?.userName ?? (key == "__anon__" ? "Anonyme" : String(key.prefix(8)))
            let last = evs.map(\.occurredAt).max() ?? ""
            return UserGroup(id: key, name: name, events: evs, last: last)
        }
        .sorted { $0.last > $1.last }
    }

    var body: some View {
        Card("Activité par utilisateur") {
            if groups.isEmpty {
                Text("Aucun event.").font(.caption).foregroundStyle(AppColors.inkLight)
            } else {
                VStack(spacing: 0) {
                    // Column headers
                    HStack {
                        Text("UTILISATEUR")
                            .font(.system(size: 9).weight(.bold)).tracking(0.8)
                            .foregroundStyle(AppColors.inkLight)
                        Spacer()
                        Text("ÉVÉNEMENTS")
                            .font(.system(size: 9).weight(.bold)).tracking(0.8)
                            .foregroundStyle(AppColors.inkLight)
                    }
                    .padding(.vertical, 6)
                    Divider().overlay(AppColors.creamBorder)

                    ForEach(groups) { group in
                        UserActivityRow(name: group.name, last: group.last, events: group.events)
                    }
                }
            }
        }
    }
}

private struct UserActivityRow: View {
    let name: String
    let last: String
    let events: [APIClient.AdminMetrics.RecentEvent]
    @State private var expanded = false

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Text(name)
                        .font(.system(size: 13).weight(.semibold))
                        .foregroundStyle(AppColors.ink)
                        .lineLimit(1)
                    Spacer()
                    Text(MetricsDate.short(last))
                        .font(.system(size: 10))
                        .foregroundStyle(AppColors.inkLight)
                    Text("\(events.count)")
                        .font(.system(size: 12).weight(.semibold))
                        .foregroundStyle(AppColors.inkMid)
                        .frame(minWidth: 22, alignment: .trailing)
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10).weight(.semibold))
                        .foregroundStyle(AppColors.terra)
                }
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 0) {
                    // Detail column headers
                    HStack {
                        Text("ÉVÉNEMENT")
                            .font(.system(size: 8).weight(.bold)).tracking(0.6)
                            .foregroundStyle(AppColors.inkLight)
                        Spacer()
                        Text("DATE · DÉTAILS")
                            .font(.system(size: 8).weight(.bold)).tracking(0.6)
                            .foregroundStyle(AppColors.inkLight)
                    }
                    .padding(.bottom, 4)

                    ForEach(events) { e in
                        HStack(alignment: .top, spacing: 10) {
                            Text(e.type)
                                .font(.system(size: 11).weight(.semibold))
                                .foregroundStyle(AppColors.terra)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(MetricsDate.short(e.occurredAt))
                                    .font(.system(size: 10))
                                    .foregroundStyle(AppColors.inkLight)
                                if let p = e.properties, !p.isEmpty {
                                    Text(p.display)
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundStyle(AppColors.inkMid)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.trailing)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .padding(.vertical, 5)
                        Divider().overlay(AppColors.creamBorder)
                    }
                }
                .padding(.leading, 10)
                .padding(.bottom, 6)
            }

            Divider().overlay(AppColors.creamBorder)
        }
    }
}

// MARK: - Date helper

private enum MetricsDate {
    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static let display: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "dd/MM HH:mm"
        return f
    }()

    /// Parse a Postgres/ISO-8601 timestamp and render it as "dd/MM HH:mm".
    /// Falls back to the raw string if it can't be parsed.
    static func short(_ iso: String) -> String {
        guard let date = isoFrac.date(from: iso) ?? isoPlain.date(from: iso) else { return iso }
        return display.string(from: date)
    }
}
