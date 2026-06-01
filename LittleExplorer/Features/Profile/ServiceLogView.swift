import SwiftUI

/// "Carnet d'entretien" — port of the web's ServiceLogPanel.
///
/// Two sections, mirroring the web layout:
///   1. **À FAIRE BIENTÔT** — kinds whose server-computed status is
///      `due` or `overdue`. Empty when nothing's flagged (the panel
///      hides the section header in that case).
///   2. **DERNIÈRES INTERVENTIONS** — chronological list of past
///      events. Swipe-to-delete on each row.
///
/// Bike picker at the top mirrors the web: the carnet is per-bike so
/// the user can compare Canyon vs e-bike maintenance independently.
/// Defaults to the primary bike if known.
struct ServiceLogView: View {
    @Environment(AppEnvironment.self) private var environment

    let bikes: [BikeGear]

    @State private var selectedGearId: String?
    @State private var events: [ServiceEvent] = []
    @State private var dueByKind: [NextDue] = []
    @State private var loading = false
    @State private var error: String?
    @State private var showAdd = false
    @State private var pendingDelete: ServiceEvent?

    private var selectedBike: BikeGear? {
        bikes.first { $0.id == selectedGearId }
    }

    /// "due" + "overdue" only, with overdue first so the rider sees
    /// the angry red cards before the friendly orange nudges.
    private var dueSoon: [NextDue] {
        dueByKind
            .filter { $0.status == .due || $0.status == .overdue }
            .sorted { (a, b) in
                if a.status == .overdue && b.status != .overdue { return true }
                if b.status == .overdue && a.status != .overdue { return false }
                return ServiceKind.displayOrder.firstIndex(of: a.kind) ?? Int.max
                    <  ServiceKind.displayOrder.firstIndex(of: b.kind) ?? Int.max
            }
    }

    var body: some View {
        Group {
            if bikes.isEmpty {
                noBikesHint
            } else {
                content
            }
        }
        .task { await ensureSelectionAndLoad() }
        .onChange(of: selectedGearId) { _, _ in Task { await load() } }
        .sheet(isPresented: $showAdd) {
            if let bike = selectedBike {
                AddServiceEventSheet(bike: bike, onSaved: {
                    showAdd = false
                    Task { await load() }
                })
            }
        }
        .alert("Supprimer cette intervention ?", isPresented: .init(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } },
        )) {
            Button("Supprimer", role: .destructive) { Task { await performDelete() } }
            Button("Annuler", role: .cancel) { pendingDelete = nil }
        }
    }

    // MARK: - Content

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let error {
                    errorBanner(error)
                }
                bikePickerCard
                addButton
                if !dueSoon.isEmpty {
                    sectionHeader("À FAIRE BIENTÔT", count: dueSoon.count)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: .infinity), spacing: 8)], spacing: 8) {
                        ForEach(dueSoon) { row in
                            dueCard(row)
                        }
                    }
                }
                if dueSoon.count != ServiceKind.allCases.count {
                    sectionHeader("AUTRES", count: nil)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: .infinity), spacing: 8)], spacing: 8) {
                        ForEach(otherKinds) { row in
                            dueCard(row)
                        }
                    }
                }
                sectionHeader("DERNIÈRES INTERVENTIONS", count: events.count)
                if events.isEmpty {
                    emptyEventsHint
                } else {
                    VStack(spacing: 8) {
                        ForEach(events) { ev in
                            eventRow(ev)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    /// Rows that aren't surfaced under "À FAIRE BIENTÔT" — shown
    /// in a quieter sub-section so the user can still see when
    /// they last did each task even when nothing is overdue.
    private var otherKinds: [NextDue] {
        let urgentSet = Set(dueSoon.map(\.kind))
        return dueByKind
            .filter { !urgentSet.contains($0.kind) }
            .sorted {
                ServiceKind.displayOrder.firstIndex(of: $0.kind) ?? Int.max
                <
                ServiceKind.displayOrder.firstIndex(of: $1.kind) ?? Int.max
            }
    }

    // MARK: - Pieces

    private var bikePickerCard: some View {
        HStack(spacing: 8) {
            Image(systemName: "bicycle")
                .foregroundStyle(AppColors.terra)
            VStack(alignment: .leading, spacing: 1) {
                Text("VÉLO")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AppColors.inkMid)
                    .tracking(0.5)
                Picker("Vélo", selection: $selectedGearId) {
                    ForEach(bikes) { bike in
                        Text("\(bike.name) · \(Int(bike.totalKm)) km")
                            .tag(Optional(bike.id))
                    }
                }
                .pickerStyle(.menu)
                .tint(AppColors.ink)
                .labelsHidden()
            }
            Spacer()
        }
        .padding(10)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppColors.creamBorder, lineWidth: 1))
    }

    private var addButton: some View {
        Button {
            showAdd = true
        } label: {
            Label("Ajouter une intervention", systemImage: "plus")
                .font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 36)
        }
        .buttonStyle(.borderedProminent)
        .tint(AppColors.terra)
        .disabled(selectedBike == nil)
    }

    private func sectionHeader(_ title: String, count: Int?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("§ \(title)")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(AppColors.inkMid)
            Spacer()
            if let count {
                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppColors.inkMid)
            }
        }
        .padding(.top, 4)
    }

    private func dueCard(_ row: NextDue) -> some View {
        let kind = row.kind
        let tint: Color = {
            switch row.status {
            case .overdue: return .red
            case .due:     return AppColors.terra
            case .fresh:   return .green
            case .unknown: return AppColors.inkMid
            }
        }()
        let statusLabel: String = {
            switch row.status {
            case .overdue: return "EN RETARD"
            case .due:     return "BIENTÔT"
            case .fresh:   return "OK"
            case .unknown: return "—"
            }
        }()

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: kind.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                Text(kind.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.ink)
                    .lineLimit(1)
                Spacer()
                Text(statusLabel)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.4)
                    .foregroundStyle(tint)
            }
            Text(dueSubtitle(for: row))
                .font(.system(size: 11))
                .foregroundStyle(AppColors.inkMid)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(tint.opacity(row.status == .fresh || row.status == .unknown ? 0.2 : 1), lineWidth: 2),
        )
    }

    private func dueSubtitle(for row: NextDue) -> String {
        if row.lastDate == nil {
            // Never logged. Show the recommended interval as a hint.
            let interval = row.kind.recommendedInterval
            if let km = interval.km {
                return "Jamais effectué. Intervalle recommandé : \(Int(km)) km."
            }
            if let days = interval.days {
                return "Jamais effectué. Intervalle recommandé : \(days) j."
            }
            return "Jamais effectué."
        }
        // Have at least one event — show what's elapsed.
        var parts: [String] = []
        if let km = row.kmSince {
            parts.append("\(Int(km)) km")
        }
        if let days = row.daysSince {
            parts.append("\(Int(days)) j")
        }
        let elapsed = parts.isEmpty ? "récemment" : "depuis \(parts.joined(separator: " · "))"
        if let kmInt = row.kmInterval {
            return "\(elapsed) · interval \(Int(kmInt)) km."
        }
        if let dInt = row.dayInterval {
            return "\(elapsed) · interval \(dInt) j."
        }
        return elapsed.capitalized + "."
    }

    private func eventRow(_ ev: ServiceEvent) -> some View {
        HStack(spacing: 10) {
            Image(systemName: ev.kind.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.terra)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(ev.kind.label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.ink)
                HStack(spacing: 6) {
                    Text(prettyDate(ev.date))
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.inkMid)
                    if let km = ev.kmAtEvent {
                        Text("·")
                            .foregroundStyle(AppColors.inkMid)
                        Text("\(Int(km)) km")
                            .font(.system(size: 11))
                            .foregroundStyle(AppColors.inkMid)
                    }
                }
                if let notes = ev.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.inkMid)
                        .lineLimit(2)
                }
            }
            Spacer()
            Button {
                pendingDelete = ev
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppColors.creamBorder, lineWidth: 1))
    }

    private var emptyEventsHint: some View {
        VStack(spacing: 6) {
            Text("Pas encore d'intervention loggée")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColors.ink)
            Text("Note chaque graissage de chaîne, purge de frein ou voilage pour suivre l'entretien dans le temps.")
                .font(.system(size: 11))
                .foregroundStyle(AppColors.inkMid)
                .multilineTextAlignment(.center)
            Button {
                showAdd = true
            } label: {
                Label("Logger ma première intervention", systemImage: "plus")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .tint(AppColors.terra)
            .padding(.top, 4)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppColors.creamBorder, lineWidth: 1))
    }

    private var noBikesHint: some View {
        VStack(spacing: 6) {
            Image(systemName: "bicycle.circle")
                .font(.system(size: 32))
                .foregroundStyle(AppColors.inkMid)
            Text("Aucun vélo synchronisé")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColors.ink)
            Text("Sync ton compte Strava pour faire apparaître tes vélos ici, puis log tes interventions.")
                .font(.system(size: 11))
                .foregroundStyle(AppColors.inkMid)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
    }

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 12))
            .foregroundStyle(.red)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Async

    @MainActor
    private func ensureSelectionAndLoad() async {
        if selectedGearId == nil {
            // Default to primary bike, else first.
            selectedGearId = bikes.first(where: { $0.primaryBike })?.id ?? bikes.first?.id
        }
        await load()
    }

    @MainActor
    private func load() async {
        guard let gearId = selectedGearId else { return }
        loading = true
        error = nil
        defer { loading = false }
        do {
            let resp = try await environment.api.fetchServiceEvents(gearId: gearId)
            events = resp.events
            dueByKind = resp.dueByKind
        } catch {
            self.error = error.localizedDescription
            Log.api.error("ServiceLog load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    @MainActor
    private func performDelete() async {
        guard let ev = pendingDelete else { return }
        pendingDelete = nil
        do {
            try await environment.api.deleteServiceEvent(id: ev.id)
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private func prettyDate(_ iso: String) -> String {
        // Server returns "yyyy-MM-dd" — format it as "30 mai 2026".
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withFullDate]
        if let date = parser.date(from: iso) {
            let f = DateFormatter()
            f.locale = Locale(identifier: "fr_FR")
            f.dateFormat = "d MMM yyyy"
            return f.string(from: date)
        }
        return iso
    }
}

/// "Ajouter une intervention" sheet. Defaults the date to today and
/// the km to the bike's current total. Kind picker uses
/// ServiceKind.displayOrder so the most common actions land at the
/// top of the list — same ergonomics as the web.
private struct AddServiceEventSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    let bike: BikeGear
    let onSaved: () -> Void

    @State private var kind: ServiceKind = .chainLube
    @State private var date: Date = .now
    @State private var km: Double
    @State private var notes: String = ""
    @State private var saving = false
    @State private var error: String?

    init(bike: BikeGear, onSaved: @escaping () -> Void) {
        self.bike = bike
        self.onSaved = onSaved
        _km = State(initialValue: bike.totalKm)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Vélo") {
                    HStack {
                        Image(systemName: "bicycle")
                            .foregroundStyle(AppColors.terra)
                        Text(bike.name)
                        Spacer()
                        Text("\(Int(bike.totalKm)) km")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Type d'intervention") {
                    Picker("Type", selection: $kind) {
                        ForEach(ServiceKind.displayOrder, id: \.self) { k in
                            Label(k.label, systemImage: k.systemImage).tag(k)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Détails") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "fr_FR"))
                    HStack {
                        Text("Km au compteur")
                        Spacer()
                        TextField("\(Int(bike.totalKm))", value: $km, format: .number.precision(.fractionLength(0)))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                    TextField("Notes (optionnel)", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }

                if let error {
                    Section { Text(error).foregroundStyle(.red).font(.caption) }
                }
            }
            .navigationTitle("Nouvelle intervention")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { Task { await save() } }
                        .disabled(saving)
                }
            }
        }
    }

    @MainActor
    private func save() async {
        saving = true
        error = nil
        defer { saving = false }
        do {
            try await environment.api.addServiceEvent(
                gearId:    bike.id,
                kind:      kind,
                date:      date,
                kmAtEvent: km,
                notes:     notes.isEmpty ? nil : notes,
            )
            onSaved()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
