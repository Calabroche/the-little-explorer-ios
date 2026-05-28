import SwiftUI

/// "Matériel" — read-only view of the user's bike piece inventory
/// with wear bars per part. Mirrors the web's /equipement page but
/// scoped to *reading* on iOS:
///
///   * Add / edit / replace lifetime → web (form-heavy, infrequent)
///   * Mark replaced               → iOS (swipe action, fast)
///   * Delete                      → iOS (swipe action, fast)
///
/// Groups pieces by category (Cadre / Transmission / Freins / Roues /
/// Autre) so a long inventory stays scannable.
struct BikeEquipmentView: View {
    @Environment(AppEnvironment.self) private var environment

    @State private var items: [BikeEquipment] = []
    @State private var totalKm: Double = 0
    @State private var loading: Bool = true
    @State private var error: String?
    @State private var pendingAction: BikeEquipment?
    @State private var pendingActionType: PendingAction = .replace

    enum PendingAction { case replace, delete }

    var body: some View {
        Group {
            if loading && items.isEmpty {
                ProgressView("Chargement…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppColors.cream)
            } else if items.isEmpty {
                emptyState
            } else {
                listView
            }
        }
        .background(AppColors.cream.ignoresSafeArea())
        .navigationTitle("Matériel")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .alert("Marquer remplacé ?", isPresented: .init(
            get: { pendingAction != nil && pendingActionType == .replace },
            set: { if !$0 { pendingAction = nil } },
        )) {
            Button("Confirmer", role: .destructive) { Task { await performReplace() } }
            Button("Annuler", role: .cancel) { pendingAction = nil }
        } message: {
            if let p = pendingAction {
                Text("La pièce « \(p.name) » sera retirée du tableau et ses km figés à la valeur actuelle.")
            }
        }
        .alert("Supprimer définitivement ?", isPresented: .init(
            get: { pendingAction != nil && pendingActionType == .delete },
            set: { if !$0 { pendingAction = nil } },
        )) {
            Button("Supprimer", role: .destructive) { Task { await performDelete() } }
            Button("Annuler", role: .cancel) { pendingAction = nil }
        } message: {
            if let p = pendingAction {
                Text("« \(p.name) » sera effacée. Action irréversible.")
            }
        }
    }

    // MARK: - List

    private var listView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let error {
                    errorBanner(error)
                }
                headerCard
                ForEach(BikeEquipmentKind.Category.allCases, id: \.self) { cat in
                    let inCat = items.filter { BikeEquipmentKind.category(for: $0.kind) == cat }
                    if !inCat.isEmpty {
                        section(category: cat, items: inCat)
                    }
                }
                footerHint
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
    }

    private var headerCard: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("§ TOTAL").font(.system(size: 10).weight(.bold)).tracking(1.2).foregroundStyle(AppColors.terra)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(Int(totalKm.rounded()))")
                        .font(.system(.title, design: .serif).weight(.heavy))
                        .foregroundStyle(AppColors.ink)
                    Text("km parcourus")
                        .font(.system(size: 12)).foregroundStyle(AppColors.inkLight)
                }
            }
            Spacer()
            Text("\(items.count) pièce\(items.count > 1 ? "s" : "") suivie\(items.count > 1 ? "s" : "")")
                .font(.system(size: 11)).foregroundStyle(AppColors.inkLight)
        }
        .padding(14)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppColors.creamBorder, lineWidth: 1))
    }

    private func section(category: BikeEquipmentKind.Category, items: [BikeEquipment]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("§ \(category.label.uppercased())")
                    .font(.system(size: 10).weight(.bold)).tracking(1.2).foregroundStyle(AppColors.terra)
                Rectangle().fill(AppColors.creamBorder).frame(width: 20, height: 1)
                Text("\(items.count) pièce\(items.count > 1 ? "s" : "")")
                    .font(.system(size: 10)).foregroundStyle(AppColors.inkLight)
            }
            VStack(spacing: 10) {
                ForEach(items) { item in
                    // Note: SwiftUI's `.swipeActions` only works inside
                    // List/Form. We're rendering custom cards inside a
                    // VStack here, so `.contextMenu` (long-press) is the
                    // right primitive for inline actions.
                    EquipmentCard(item: item)
                        .contextMenu {
                            Button {
                                pendingAction = item
                                pendingActionType = .replace
                            } label: {
                                Label("Marquer remplacé", systemImage: "arrow.uturn.backward.circle")
                            }
                            Button(role: .destructive) {
                                pendingAction = item
                                pendingActionType = .delete
                            } label: {
                                Label("Supprimer", systemImage: "trash")
                            }
                        }
                }
            }
        }
    }

    private var footerHint: some View {
        Text("Appui long sur une carte pour la marquer remplacée ou la supprimer. Ajouter / éditer une pièce → ouvre /equipement sur le web.")
            .font(.caption)
            .foregroundStyle(AppColors.inkLight)
            .lineSpacing(2)
            .padding(.horizontal, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "wrench.adjustable")
                .font(.system(size: 36))
                .foregroundStyle(AppColors.inkLight)
            Text("Aucune pièce suivie")
                .font(.system(.title3, design: .serif).weight(.bold))
                .foregroundStyle(AppColors.ink)
            Text("Ajoute tes pièces depuis la web app (/equipement) — elles apparaîtront ici avec leur usure calculée à chaque sortie vélo.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(AppColors.inkLight)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 40)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.red)
            Text(message).font(.caption).foregroundStyle(AppColors.inkMid)
            Spacer()
        }
        .padding(10)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Data

    @MainActor
    private func load() async {
        loading = true
        defer { loading = false }
        error = nil
        do {
            let response = try await environment.api.fetchEquipment()
            totalKm = response.totalKm
            items = response.items
        } catch {
            self.error = "Erreur : \(error.localizedDescription)"
            Log.api.error("equipment fetch failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    @MainActor
    private func performReplace() async {
        guard let item = pendingAction else { return }
        pendingAction = nil
        do {
            try await environment.api.markEquipmentReplaced(id: item.id)
            await load()
        } catch {
            self.error = "Échec du remplacement : \(error.localizedDescription)"
        }
    }

    @MainActor
    private func performDelete() async {
        guard let item = pendingAction else { return }
        pendingAction = nil
        do {
            try await environment.api.deleteEquipment(id: item.id)
            await load()
        } catch {
            self.error = "Échec de la suppression : \(error.localizedDescription)"
        }
    }
}

// MARK: - Card

private struct EquipmentCard: View {
    let item: BikeEquipment

    private var color: Color {
        if item.wearRatio > 1   { return Color(red: 0.64, green: 0.22, blue: 0.22) } // red
        if item.wearRatio > 0.75 { return AppColors.terra }
        return AppColors.green
    }

    private var overdue: Bool { item.wearRatio > 1 }
    private var wearPct: Double { min(1, item.wearRatio) }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Colored stripe — wear bucket indicator.
            Rectangle()
                .fill(color)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: BikeEquipmentKind.symbol(for: item.kind))
                        .foregroundStyle(AppColors.terra)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.name)
                            .font(.system(.body, design: .serif).weight(.bold))
                            .foregroundStyle(AppColors.ink)
                            .lineLimit(2)
                        Text(BikeEquipmentKind.label(for: item.kind).uppercased())
                            .font(.system(size: 9).weight(.bold)).tracking(0.8)
                            .foregroundStyle(AppColors.inkLight)
                    }
                    Spacer()
                }
                // Wear bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(AppColors.creamDark)
                            .frame(width: geo.size.width, height: 6)
                            .cornerRadius(2)
                        Rectangle()
                            .fill(color)
                            .frame(width: geo.size.width * wearPct, height: 6)
                            .cornerRadius(2)
                    }
                }
                .frame(height: 6)

                HStack(alignment: .firstTextBaseline) {
                    Text("\(Int(item.kmSinceInstall.rounded())) km").font(.system(size: 12).weight(.bold))
                        .foregroundStyle(AppColors.ink)
                        + Text(" depuis la pose").font(.system(size: 11)).foregroundStyle(AppColors.inkLight)
                    Spacer()
                    Text(overdue
                         ? "+\(Int(((item.wearRatio - 1) * 100).rounded())) % dépassement"
                         : "\(Int((item.wearRatio * 100).rounded())) % d'usure")
                        .font(.system(size: 11).weight(.bold))
                        .foregroundStyle(color)
                }
                HStack {
                    Text("durée de vie \(item.lifetimeKm) km")
                        .font(.system(size: 10))
                        .foregroundStyle(AppColors.inkLight)
                    Spacer()
                }
                if let notes = item.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.system(size: 11).italic())
                        .foregroundStyle(AppColors.inkLight)
                        .padding(.top, 2)
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 14)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppColors.creamBorder, lineWidth: 1))
    }
}
