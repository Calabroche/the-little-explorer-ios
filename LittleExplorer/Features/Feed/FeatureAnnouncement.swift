import SwiftUI

/// A "what's new" note. Add a new entry (NEWEST FIRST) with a fresh `id`
/// each time a feature ships — the home screen shows the most recent one the
/// rider hasn't dismissed yet. Keep ids stable: they're the dismissal key.
struct FeatureNote: Identifiable {
    let id: String
    let icon: String
    let date: String   // "YYYY-MM-DD" — drives the today/week/month grouping
    let title: String
    let body: String
}

enum FeatureNotes {
    static let all: [FeatureNote] = [
        FeatureNote(
            id: "ravito-2026-06",
            icon: "💧",
            date: "2026-06-04",
            title: "Points de ravitaillement sur ton parcours",
            body: "Sur la carte du planificateur, ouvre la carte en plein écran et active le bouton « Ravito » : l'app repère le long de ton trajet les points d'eau (fontaines, robinets, cimetières) et les commerces où manger ou acheter de l'eau (supermarchés, supérettes, boulangeries). Plus jamais à sec en pleine sortie.",
        ),
    ]
}

/// Home-screen popup that surfaces the latest undismissed feature note.
/// Mount it as an overlay on the default (feed) screen. Renders nothing once
/// there's no fresh note to show.
struct FeatureAnnouncementView: View {
    private static let seenKey = "tle_seen_features"
    @State private var note: FeatureNote?

    var body: some View {
        ZStack {
            if let note {
                Color.black.opacity(0.5).ignoresSafeArea()
                    .onTapGesture { dismiss(note) }
                card(note)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: note?.id)
        .onAppear(perform: pick)
    }

    private func pick() {
        let seen = Set(UserDefaults.standard.stringArray(forKey: Self.seenKey) ?? [])
        note = FeatureNotes.all.first { !seen.contains($0.id) }
    }

    private func dismiss(_ n: FeatureNote) {
        var seen = UserDefaults.standard.stringArray(forKey: Self.seenKey) ?? []
        if !seen.contains(n.id) {
            seen.append(n.id)
            UserDefaults.standard.set(seen, forKey: Self.seenKey)
        }
        note = nil
    }

    private func card(_ n: FeatureNote) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                Button { dismiss(n) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppColors.inkMid)
                        .padding(8)
                        .background(AppColors.creamDark, in: Circle())
                }
                .buttonStyle(.plain)
            }
            Text(n.icon).font(.system(size: 40))
            Text("✦ NOUVEAU")
                .font(.system(size: 10).weight(.bold)).tracking(1.2)
                .foregroundStyle(AppColors.terra)
                .padding(.top, 4)
            Text(n.title)
                .font(.system(.title3, design: .serif).weight(.bold))
                .foregroundStyle(AppColors.ink)
                .padding(.top, 6)
            Text(n.body)
                .font(.system(size: 14))
                .foregroundStyle(AppColors.inkMid)
                .lineSpacing(3)
                .padding(.top, 8)
            Button { dismiss(n) } label: {
                Text("OK, MERCI POUR L'INFO")
                    .font(.system(size: 13).weight(.bold)).tracking(0.8)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(AppColors.terra, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .padding(.top, 18)
        }
        .padding(22)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.creamBorder, lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
        .padding(28)
    }
}
