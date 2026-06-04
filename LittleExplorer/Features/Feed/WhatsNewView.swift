import SwiftUI

/// The full "what's new" archive, opened from the "i" button on the feed.
/// Lists every feature note grouped into today / this week / this month /
/// earlier, based on each note's `date`.
struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss

    private enum Bucket: Int, CaseIterable {
        case today, week, month, earlier
        var label: String {
            switch self {
            case .today:   return "Nouveauté du jour"
            case .week:    return "Nouveautés de la semaine"
            case .month:   return "Nouveautés du mois"
            case .earlier: return "Avant"
            }
        }
    }

    private static let parser: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()

    private func bucket(for dateStr: String) -> Bucket {
        guard let d = Self.parser.date(from: dateStr) else { return .earlier }
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: d), to: cal.startOfDay(for: Date())).day ?? 0
        if days <= 0 { return .today }
        if days <= 7 { return .week }
        if days <= 31 { return .month }
        return .earlier
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(Bucket.allCases, id: \.rawValue) { b in
                        let notes = FeatureNotes.all.filter { bucket(for: $0.date) == b }
                        if !notes.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(b.label.uppercased())
                                    .font(.system(size: 11).weight(.bold)).tracking(0.8)
                                    .foregroundStyle(AppColors.inkLight)
                                ForEach(notes) { n in noteRow(n) }
                            }
                        }
                    }
                    if FeatureNotes.all.isEmpty {
                        Text("Rien pour le moment.")
                            .font(.system(size: 13)).foregroundStyle(AppColors.inkLight)
                    }
                }
                .padding(18)
            }
            .background(AppColors.cream)
            .navigationTitle("Quoi de neuf")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                        .foregroundStyle(AppColors.terra)
                }
            }
        }
    }

    private func noteRow(_ n: FeatureNote) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(n.icon).font(.system(size: 22))
            VStack(alignment: .leading, spacing: 3) {
                Text(n.title)
                    .font(.system(size: 14).weight(.bold))
                    .foregroundStyle(AppColors.ink)
                Text(n.body)
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.inkMid)
                    .lineSpacing(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.creamBorder, lineWidth: 1))
    }
}
