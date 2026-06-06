import SwiftUI

/// A "what's new" note. Add a new entry (NEWEST FIRST) with a fresh `id`
/// each time a feature ships — the home screen shows the most recent one the
/// rider hasn't dismissed yet. Keep ids stable: they're the dismissal key.
struct FeatureNote: Identifiable {
    let id: String
    let icon: String
    let date: String        // "YYYY-MM-DD"
    let sport: String       // "all" | "cycling" | "running" — drives the "i" grouping
    let title: String
    let body: String
}

enum FeatureNotes {
    // Newest first. The launch popup only announces the FIRST entry; the
    // "i" panel lists them all, grouped by recency.
    static let all: [FeatureNote] = [
        FeatureNote(id: "ravito-2026-06", icon: "💧", date: "2026-06-04", sport: "all",
            title: "Points de ravitaillement sur ton parcours",
            body: "Sur la carte plein écran du planificateur, active le bouton « Ravito » : l'app repère le long de ton trajet les points d'eau (fontaines, robinets, cimetières) et les commerces où manger ou acheter de l'eau (supermarchés, supérettes, boulangeries)."),
        FeatureNote(id: "onboarding-favsport-2026-06", icon: "🚦", date: "2026-06-04", sport: "all",
            title: "Onboarding : choisis ton sport de prédilection",
            body: "Plus de choix de sports à l'inscription, ton sport favori s'affiche en premier, et l'étape poids/vélo est sautée si tu ne fais pas de vélo."),
        FeatureNote(id: "power-charge-2026-06", icon: "⚡", date: "2026-06-04", sport: "cycling",
            title: "Section « Puissance & Charge »",
            body: "Tes records de puissance, ton estimation de FTP et l'analyse de charge (TSS) sont réunis sur une page dédiée."),
        FeatureNote(id: "fireworks-2026-06", icon: "🎆", date: "2026-06-04", sport: "all",
            title: "Un feu d'artifice au lancement",
            body: "Pour le plaisir : une animation festive accueille l'ouverture de l'app, et un cycliste qui pédale sur l'écran d'accueil de la Watch."),
        FeatureNote(id: "planner-clickmap-2026-06", icon: "📍", date: "2026-06-03", sport: "all",
            title: "Ajoute un point en touchant la carte",
            body: "Touche la carte du planificateur : une confirmation s'affiche et le point exact s'ajoute à ton itinéraire."),
        FeatureNote(id: "planner-speed-stats-2026-06", icon: "⏱️", date: "2026-06-03", sport: "all",
            title: "Vitesse modifiable + stats du parcours",
            body: "Change ta vitesse de croisière et le temps estimé se recalcule. Distance, temps, D+/D− et difficulté en un coup d'œil."),
        FeatureNote(id: "elevation-grade-2026-06", icon: "⛰️", date: "2026-06-03", sport: "all",
            title: "Profil d'altitude coloré par pente",
            body: "Le profil est coloré selon la pente (vert/jaune/orange/rouge) avec une résolution de 100 m."),
        FeatureNote(id: "save-routes-2026-05", icon: "💾", date: "2026-05-29", sport: "all",
            title: "Sauvegarde & synchro de tes itinéraires",
            body: "Tes parcours sont sauvegardés sur ton compte et synchronisés entre le web, l'iPhone et l'Apple Watch."),
        FeatureNote(id: "strava-resync-2026-06", icon: "🔄", date: "2026-06-02", sport: "all",
            title: "Re-synchro Strava en un bouton",
            body: "Un seul bouton importe tes activités et les tracés GPS / graphes (FC, vitesse, puissance, altitude)."),
        FeatureNote(id: "sports-coverage-2026-06", icon: "🏅", date: "2026-06-02", sport: "all",
            title: "Tous tes sports Strava couverts",
            body: "Vélo, course, rando, marche, nage, ski, renfo… 25 types d'activité gérés, avec un sélecteur adapté à ce que tu pratiques."),
        FeatureNote(id: "service-log-2026-05", icon: "🔧", date: "2026-05-28", sport: "cycling",
            title: "Carnet d'entretien du matériel",
            body: "Suis l'entretien de ton vélo et l'usure des pièces dans la section Matériel."),
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
        // Only the NEWEST note can pop up — older/backfilled entries live in
        // the "i" panel and must never resurface as launch popups.
        let seen = Set(UserDefaults.standard.stringArray(forKey: Self.seenKey) ?? [])
        if let newest = FeatureNotes.all.first, !seen.contains(newest.id) { note = newest }
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
