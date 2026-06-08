import SwiftUI

/// The "what's new" panel, opened from the "i" button. Tabbed: Vélo / Course
/// (each shows that sport's notes + the cross-sport ones) and a "vs Strava"
/// tab with the comparison pitch.
struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss
    var initialRunning: Bool = false

    private enum Tab: String, CaseIterable, Identifiable {
        case cycling, running, strava
        var id: String { rawValue }
        var label: String {
            switch self {
            case .cycling: return "🚴 Vélo"
            case .running: return "🏃 Course"
            case .strava:  return "vs Strava"
            }
        }
    }
    @State private var tab: Tab = .cycling

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if tab == .strava {
                            WhyBetterThanStrava()
                        } else {
                            let key = tab == .cycling ? "cycling" : "running"
                            let notes = FeatureNotes.all.filter { $0.sport == key || $0.sport == "all" }
                            if notes.isEmpty {
                                Text("Rien pour le moment pour ce sport.")
                                    .font(.system(size: 13)).foregroundStyle(AppColors.inkLight)
                            } else {
                                ForEach(notes) { noteRow($0) }
                            }
                        }
                    }
                    .padding(18)
                }
            }
            .background(AppColors.cream)
            .navigationTitle("Quoi de neuf")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }.foregroundStyle(AppColors.terra)
                }
            }
            .onAppear { tab = initialRunning ? .running : .cycling }
        }
    }

    private func relDate(_ dateStr: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        guard let d = f.date(from: dateStr) else { return "" }
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: d), to: cal.startOfDay(for: Date())).day ?? 0
        if days <= 0 { return "auj." }
        if days == 1 { return "hier" }
        if days <= 30 { return "il y a \(days) j" }
        let out = DateFormatter(); out.locale = Locale(identifier: "fr_FR"); out.dateFormat = "d MMM"
        return out.string(from: d)
    }

    private func noteRow(_ n: FeatureNote) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(n.icon).font(.system(size: 22))
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(n.title).font(.system(size: 14).weight(.bold)).foregroundStyle(AppColors.ink)
                    Spacer(minLength: 8)
                    Text(relDate(n.date)).font(.system(size: 10)).foregroundStyle(AppColors.inkLight)
                }
                Text(n.body).font(.system(size: 13)).foregroundStyle(AppColors.inkMid).lineSpacing(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.creamBorder, lineWidth: 1))
    }
}
