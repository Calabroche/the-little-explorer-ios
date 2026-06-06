import SwiftUI

/// The full "what's new" archive, opened from the "i" button on the feed.
/// Lists every feature note grouped BY SPORT (all / cycling / running).
struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss

    private let sportOrder: [(key: String, label: String)] = [
        ("all", "Tous les sports"),
        ("cycling", "🚴 Vélo"),
        ("running", "🏃 Course"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    WhyBetterThanStrava()
                    ForEach(sportOrder, id: \.key) { group in
                        let notes = FeatureNotes.all.filter { $0.sport == group.key }
                        if !notes.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(group.label.uppercased())
                                    .font(.system(size: 11).weight(.bold)).tracking(0.8)
                                    .foregroundStyle(AppColors.terra)
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
