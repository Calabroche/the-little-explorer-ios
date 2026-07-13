import SwiftUI

/// Native mirror of the web /admin/perf dashboard. Admin-only. Ranks API
/// routes by p95 and shows page-load / LCP timings collected from real users
/// (web + iOS), so loading speed can be tracked from the phone too.
struct PerfDashboardView: View {
    @State private var data: AdminPerf?
    @State private var loading = true
    @State private var error: String?
    @State private var window = "24h"

    var body: some View {
        List {
            Section {
                Picker("Fenêtre", selection: $window) {
                    Text("1 h").tag("1h"); Text("24 h").tag("24h"); Text("7 j").tag("7d")
                }
                .pickerStyle(.segmented)
            }

            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            if loading && data == nil {
                HStack { Spacer(); ProgressView(); Spacer() }
            }

            if let d = data {
                Section("Chargement de page") {
                    navRow("TTFB", stat(d.nav, "ttfb"))
                    navRow("DOM prêt", stat(d.nav, "dcl"))
                    navRow("Chargement", stat(d.nav, "load"))
                    navRow("LCP", stat(d.vital, "lcp"))
                }
                Section("Routes API — p95 (\(d.totalSamples) mesures)") {
                    if d.api.isEmpty {
                        Text("Pas encore de données.").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(d.api) { s in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.label).font(.system(size: 13, design: .monospaced)).foregroundStyle(AppColors.ink)
                                Text("\(s.count) appels · p50 \(s.p50) ms\(s.errorRate > 0 ? " · \(s.errorRate)% err" : "")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(s.p95) ms").font(.system(size: 15, weight: .bold)).foregroundStyle(Self.color(s.p95))
                        }
                    }
                }
            }
        }
        .navigationTitle("Performance")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: window) { await load() }
    }

    private func stat(_ arr: [PerfStat], _ label: String) -> PerfStat? { arr.first { $0.label == label } }

    private func navRow(_ title: String, _ s: PerfStat?) -> some View {
        HStack {
            Text(title)
            Spacer()
            if let s {
                Text("\(s.p95) ms").fontWeight(.semibold).foregroundStyle(Self.color(s.p95))
            } else {
                Text("—").foregroundStyle(.secondary)
            }
        }
    }

    private static func color(_ ms: Int) -> Color {
        ms < 800 ? AppColors.green : ms < 2500 ? Color(red: 0.79, green: 0.54, blue: 0.17) : Color(red: 0.71, green: 0.25, blue: 0.18)
    }

    private func load() async {
        loading = true; error = nil
        do { data = try await APIClient.shared.adminPerf(window: window) }
        catch { self.error = "Accès refusé (admin) ou erreur réseau." }
        loading = false
    }
}
