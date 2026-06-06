import SwiftUI

/// Comprehensive user guide for The Little Explorer.
///
/// Reference doc that mirrors the web's /guide page. Lists every TLE
/// feature so a new user knows what the app does without trial-and-error.
/// Sections are kept in sync with `src/app/guide/page.tsx` — update both
/// in lockstep when adding / renaming features.
struct GuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                WhyBetterThanStrava()
                ForEach(GuideContent.sections) { section in
                    SectionCard(section: section)
                }
                footer
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .background(AppColors.cream.ignoresSafeArea())
        .navigationTitle("Guide")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("§ DOCUMENTATION")
                .font(.system(size: 10).weight(.bold))
                .tracking(1.4)
                .foregroundStyle(AppColors.terra)
            Text("Guide d'utilisation")
                .font(.system(size: 32, design: .serif).weight(.heavy))
                .foregroundStyle(AppColors.ink)
            Text("Toutes les fonctionnalités de The Little Explorer — version web, app iOS et Apple Watch.")
                .font(.system(size: 13))
                .foregroundStyle(AppColors.inkMid)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
    }

    private var footer: some View {
        VStack(spacing: 6) {
            Text("Un truc qui manque ou qui n'est pas clair ?")
                .font(.system(size: 12))
                .foregroundStyle(AppColors.inkLight)
            Link("florian.calabrese@gmail.com", destination: URL(string: "mailto:florian.calabrese@gmail.com")!)
                .font(.system(size: 12).weight(.semibold))
                .foregroundStyle(AppColors.terra)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
    }
}

// MARK: - Section card

private struct SectionCard: View {
    let section: GuideSection

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(section.emoji)
                    .font(.system(size: 22))
                    .foregroundStyle(AppColors.terra)
                Text(section.title)
                    .font(.system(size: 22, design: .serif).weight(.heavy))
                    .foregroundStyle(AppColors.ink)
            }

            Text(section.intro)
                .font(.system(size: 14))
                .foregroundStyle(AppColors.inkMid)
                .lineSpacing(4)

            bulletList(title: "CE QUE TU Y TROUVES", items: section.contains)
            bulletList(title: "CE QUE TU PEUX Y FAIRE", items: section.actions)

            if let note = section.note {
                HStack(alignment: .top, spacing: 8) {
                    Text("💡")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ASTUCE")
                            .font(.system(size: 10).weight(.bold))
                            .tracking(1)
                            .foregroundStyle(Color(red: 0.54, green: 0.29, blue: 0))
                        Text(highlight(note))
                            .font(.system(size: 12))
                            .foregroundStyle(Color(red: 0.54, green: 0.29, blue: 0))
                            .lineSpacing(3)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 1, green: 0.96, blue: 0.9), in: RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color(red: 1, green: 0.85, blue: 0.65), lineWidth: 1),
                )
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(AppColors.creamBorder, lineWidth: 1),
        )
    }

    private func bulletList(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 10).weight(.bold))
                .tracking(1)
                .foregroundStyle(AppColors.terra)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .foregroundStyle(AppColors.inkLight)
                        Text(highlight(item))
                            .font(.system(size: 13))
                            .foregroundStyle(AppColors.inkMid)
                            .lineSpacing(3)
                    }
                }
            }
        }
    }

    /// Lightweight ** → bold translator so the FR copy can emphasise
    /// sub-headers ("**Itinéraire** — …") without a full markdown
    /// engine. Same convention as the web's highlightMarkdown helper.
    private func highlight(_ s: String) -> AttributedString {
        var result = AttributedString()
        let parts = s.components(separatedBy: "**")
        for (i, part) in parts.enumerated() {
            var chunk = AttributedString(part)
            if i % 2 == 1 {
                chunk.font = .system(size: 13, weight: .bold)
                chunk.foregroundColor = AppColors.ink
            }
            result.append(chunk)
        }
        return result
    }
}

// MARK: - Content

private struct GuideSection: Identifiable {
    let id:       String
    let title:    String
    let emoji:    String
    let intro:    String
    let contains: [String]
    let actions:  [String]
    var note:     String? = nil
}

private enum GuideContent {
    static let sections: [GuideSection] = [
        GuideSection(
            id: "activites",
            title: "Activités",
            emoji: "◎",
            intro: "La page d'accueil — le fil de toutes tes sorties Strava synchronisées, avec récap chiffré, graphes annuels et cartes des derniers parcours.",
            contains: [
                "Le titre + récap chiffré du nombre total de sorties.",
                "Bandeau filtre sport (Vélo, Course, Rando, Nage, Yoga, etc.) — n'affiche que les sports que tu pratiques vraiment.",
                "Filtre vélo (uniquement si tu en as 2+) pour scoper les widgets à un vélo précis.",
                "Calendrier annuel d'activités (style GitHub) — un carré par jour, intensité = volume.",
                "« Last 5 stats » — moyennes des 5 dernières sorties.",
                "Objectifs en cours avec barre de progression.",
                "Records personnels par distance + vitesse.",
                "Zones FC ou zones d'allure — temps passé dans chaque zone.",
                "Programme d'entraînement (cyclisme uniquement) — chart TSS + reco prochaine sortie.",
                "Liste chronologique des sorties avec miniature carte, durée, distance.",
            ],
            actions: [
                "Filtrer par sport via le bandeau du haut.",
                "Filtrer par vélo si plusieurs vélos bindés sur Strava.",
                "Tap sur une sortie → ouvre la page de détail.",
                "Tap « ↻ RE-SYNCER STRAVA » dans Profil pour forcer une re-synchronisation.",
            ],
        ),
        GuideSection(
            id: "activite-detail",
            title: "Détail d'une sortie",
            emoji: "✦",
            intro: "Analyse complète d'une sortie : carte, courbes, zones, montées détectées, records battus.",
            contains: [
                "En-tête : titre, sport, lieu, date.",
                "Récap chiffré : durée, distance, allure ou vitesse moy., D+, FC max, calories.",
                "Carte du trajet avec polyline colorée selon la vitesse ou la FC.",
                "Courbe vitesse au fil de la sortie.",
                "Profil d'altitude détaillé.",
                "Zones FC — répartition du temps passé en Z1/Z2/Z3/Z4/Z5.",
                "Montées détectées (climbs) avec longueur, dénivelé, pente.",
                "Records personnels battus sur cette sortie.",
                "Métriques avancées : puissance estimée, IF, NP, TSS (cyclisme).",
                "Pour les sorties indoor : seul le récap chiffré s'affiche.",
            ],
            actions: [
                "Tap sur une montée dans la liste → la surligne sur la carte.",
                "Pincer pour zoomer sur la carte.",
                "Bouton « ← Retour » pour revenir au fil.",
            ],
            note: "Si une sortie n'a ni carte ni graphes, c'est probablement une session indoor (muscu / yoga) — par nature Strava ne stocke pas le tracé GPS de ces séances."
        ),
        GuideSection(
            id: "planificateur",
            title: "Planificateur",
            emoji: "✦",
            intro: "Hub de planification 4 onglets : créer un itinéraire, générer un plan d'entraînement, découvrir des parcours, ou proposer des sorties auto.",
            contains: [
                "**Itinéraire** — carte interactive, profil d'altitude, surface, type de voie.",
                "**Plan d'entraînement** (cyclisme) — plan périodisé selon ta FTP.",
                "**Auto-route** — itinéraires aléatoires selon distance + D+ ciblés.",
                "**Parcours** — segments Strava populaires dans ta zone.",
            ],
            actions: [
                "Créer un itinéraire en tapant des waypoints sur la carte.",
                "Sauvegarder un itinéraire — il apparaît sur ta bibliothèque + se sync sur ta Watch.",
                "Exporter un itinéraire en GPX pour ton GPS Garmin/Wahoo.",
                "Générer un plan d'entraînement (4-12 semaines) calibré FTP.",
                "Demander des suggestions d'auto-route.",
            ],
            note: "Les itinéraires sauvés ici sont **immédiatement** dispos sur ta Watch via la sync iPhone ↔ Watch."
        ),
        GuideSection(
            id: "comparer",
            title: "Comparer",
            emoji: "⇄",
            intro: "Mets deux sorties côte à côte pour voir tes progrès — utile pour comparer le même parcours à 2 mois d'écart.",
            contains: [
                "Sélecteur de 2 activités.",
                "Comparaison chiffrée : durée, distance, allure, FC moy., D+.",
                "Calcul de l'écart en % et valeurs absolues.",
                "Cartes superposées (si même parcours).",
            ],
            actions: [
                "Comparer 2 sorties identiques pour mesurer un gain.",
                "Comparer 2 sorties similaires sur différents vélos.",
            ],
        ),
        GuideSection(
            id: "ftp-charge",
            title: "FTP & Charge",
            emoji: "⚡",
            intro: "Suivi de ta FTP estimée + courbe de charge (TSS) sur 7 / 30 / 90 / 365 jours. Cyclisme uniquement.",
            contains: [
                "FTP estimée — best effort de 20 min × 0.95 (Coggan).",
                "Évolution de la FTP dans le temps.",
                "TSS hebdomadaire / mensuel / annuel.",
                "CTL (charge chronique), ATL (fatigue), TSB (équilibre).",
                "Détection des semaines de surcharge.",
            ],
            actions: [
                "Modifier ta FTP manuellement (test 20 min ou test rampes).",
                "Voir les reco basées sur ton TSB.",
            ],
            note: "La FTP par défaut est estimée auto. Si tu as une valeur précise (test labo), surcharge-la dans Réglages."
        ),
        GuideSection(
            id: "materiel",
            title: "Matériel",
            emoji: "⚙",
            intro: "Suivi de tes vélos + de chaque composant : pièces d'usure d'un côté, carnet d'entretien de l'autre.",
            contains: [
                "Liste des vélos synchronisés Strava (avec km totaux + reset).",
                "**Pièces d'usure** — chaîne, plaquettes, câbles, etc. avec barre d'usure.",
                "**Carnet d'entretien** — « À faire bientôt » et « Dernières interventions ».",
                "Intervalles recommandés : chain lube 200 km, brake pads 1000 km, etc.",
            ],
            actions: [
                "Ajouter une pièce d'usure (date / km d'installation).",
                "Marquer une pièce comme remplacée — usure repart à zéro.",
                "Logger une intervention (lub chaîne, purge freins, etc.) avec date + km.",
                "Switcher entre tes vélos via le sélecteur en haut.",
            ],
            note: "Les km par vélo sont calculés depuis tes sorties Strava taggées avec le bon vélo."
        ),
        GuideSection(
            id: "bilan",
            title: "Bilan",
            emoji: "✺",
            intro: "Rétrospective annuelle façon Spotify Wrapped — chiffres clés de l'année, top sport, records.",
            contains: [
                "Distance totale, dénivelé cumulé, heures de l'année.",
                "Sport principal pratiqué.",
                "Mois le plus actif, jour de la semaine préféré.",
                "Top 3 plus longues sorties, top 3 plus grosses montées.",
                "Évolution de la FC moy. / VO2 max estimé.",
                "Comparatif vs l'année précédente.",
            ],
            actions: [
                "Changer l'année affichée.",
                "Partager le bilan en capture d'écran.",
            ],
        ),
        GuideSection(
            id: "profil-settings",
            title: "Profil & Réglages",
            emoji: "◐",
            intro: "Ton compte, ta connexion Strava et tes réglages physiologiques.",
            contains: [
                "Avatar + nom + email.",
                "Statut Strava (athleteId, scope).",
                "Bouton « ↻ RE-SYNCER STRAVA » — re-pull complet.",
                "Réglages : poids cycliste, poids vélo, FTP custom, langue, mode sombre.",
                "Toggle HealthKit pour remonter tes sorties dans Apple Santé.",
                "Pairing Bluetooth d'une ceinture cardio (Polar H10, Wahoo TICKR).",
                "Export GPX/CSV/JSON.",
                "Suppression de compte (cascade).",
            ],
            actions: [
                "Modifier ton poids → calculs de puissance et TSS s'ajustent.",
                "Override ta FTP avec une valeur testée précisément.",
                "Exporter tes données (GDPR / backup).",
                "Supprimer ton compte — irréversible.",
            ],
        ),
        GuideSection(
            id: "apple-watch",
            title: "Apple Watch",
            emoji: "◎",
            intro: "Recording GPS standalone — pas besoin de l'iPhone pendant le ride. Sync auto au retour.",
            contains: [
                "Page d'accueil avec « Start ride » + bouton « Itinéraires » si planifiés.",
                "Countdown 5 secondes avant le démarrage.",
                "Page Métriques : TIME / DIST / SPEED / AVG / HR / CLIMB + zones FC.",
                "Page Carte (itinéraire) : trace planifiée + position en temps réel.",
                "Page Contrôles : Pause / End ride.",
                "Always-On Display : la grille reste lisible en mode dim.",
                "Crash recovery : snapshot toutes les 30s.",
                "Complication sur le cadran : tap → ouvre direct l'app.",
            ],
            actions: [
                "Lancer un ride freeform (sans itinéraire).",
                "Lancer un ride avec itinéraire — guidage vocal turn-by-turn en français.",
                "Pause / Resume / End via la page Contrôles.",
                "Annonces vocales aux carrefours (200 m avant + au virage).",
            ],
            note: "Pendant un ride avec itinéraire, ton iPhone affiche une Live Activity sur le lock screen avec carte + métriques mises à jour toutes les 3 secondes."
        ),
        GuideSection(
            id: "auto-features",
            title: "Fonctionnalités automatiques",
            emoji: "✦",
            intro: "Ce qui se passe sans que tu cliques sur rien.",
            contains: [
                "**Sync auto** à la connexion : import activités + streams.",
                "**Webhooks Strava** : chaque sortie publiée syncée en temps réel.",
                "**Backfill streams** : GPS/altitude récupérés auto.",
                "**Détection des montées** : algo qui identifie les climbs (≥500 m, ≥30 m, ≥3%).",
                "**Calcul de TSS** : pour chaque sortie cyclisme depuis puissance + FTP.",
                "**Km par vélo** : incrémenté à chaque ride.",
                "**Watch ↔ iPhone** : itinéraires sync en temps réel.",
            ],
            actions: [
                "Pas d'action requise — tout tourne en arrière-plan.",
            ],
            note: "Si une sync semble bloquée, le bouton « ↻ RE-SYNCER STRAVA » dans Profil force une re-synchronisation complète."
        ),
    ]
}
