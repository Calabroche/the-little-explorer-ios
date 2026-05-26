import OSLog
import SwiftUI

/// In-app log viewer. Reads the unified log via `OSLogStore`, filtered
/// to the app's own subsystem, and lets the user filter by level +
/// category + free-text search. Tapping "Partager" exports the visible
/// entries so Florian can attach them to a bug report.
///
/// Reading the OSLogStore requires iOS 15+. The store is per-process so
/// we always pass `.currentProcessIdentifier` — that gives us our own
/// logs without needing the `com.apple.developer.os-log-direct`
/// entitlement (which only ships on internal Apple builds).
struct DiagnosticsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var entries: [LogEntry] = []
    @State private var isLoading: Bool = false
    @State private var loadError: String?
    @State private var range: TimeRange = .lastHour
    @State private var minLevel: LogLevel = .info
    @State private var search: String = ""
    @State private var selectedCategory: String? = nil
    @State private var shareItems: [Any]? = nil
    @State private var showShare: Bool = false
    @State private var showWipeConfirm: Bool = false

    enum TimeRange: String, CaseIterable, Hashable {
        case lastHour      = "1 h"
        case last4Hours    = "4 h"
        case lastDay       = "24 h"
        case last3Days     = "3 j"

        var seconds: TimeInterval {
            switch self {
            case .lastHour:   return 3600
            case .last4Hours: return 4 * 3600
            case .lastDay:    return 86400
            case .last3Days:  return 3 * 86400
            }
        }
    }

    enum LogLevel: String, CaseIterable, Hashable {
        case debug, info, notice, warning, error, fault

        var sortKey: Int {
            switch self {
            case .debug:   return 0
            case .info:    return 1
            case .notice:  return 2
            case .warning: return 3
            case .error:   return 4
            case .fault:   return 5
            }
        }

        var symbol: String {
            switch self {
            case .debug:   return "ant"
            case .info:    return "info.circle"
            case .notice:  return "bell"
            case .warning: return "exclamationmark.triangle"
            case .error:   return "xmark.octagon"
            case .fault:   return "flame"
            }
        }

        var color: Color {
            switch self {
            case .debug:   return AppColors.inkLight
            case .info:    return AppColors.inkMid
            case .notice:  return AppColors.blue
            case .warning: return Color.orange
            case .error:   return Color.red
            case .fault:   return Color.red
            }
        }
    }

    struct LogEntry: Identifiable, Hashable {
        let id: UUID = UUID()
        let timestamp: Date
        let level: LogLevel
        let category: String
        let message: String
    }

    var body: some View {
        VStack(spacing: 10) {
            filterBar
            entriesList
        }
        .padding(.top, 8)
        .background(AppColors.cream)
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        Task { await load() }
                    } label: {
                        Label("Recharger", systemImage: "arrow.clockwise")
                    }
                    Button {
                        emitTestEntries()
                        Task {
                            // Tiny pause so the new entries are flushed
                            // to the store before we re-fetch.
                            try? await Task.sleep(for: .milliseconds(200))
                            await load()
                        }
                    } label: {
                        Label("Émettre des logs de test", systemImage: "testtube.2")
                    }
                    Button {
                        share()
                    } label: {
                        Label("Partager (\(filteredEntries.count) lignes)", systemImage: "square.and.arrow.up")
                    }
                    .disabled(filteredEntries.isEmpty)
                    Divider()
                    Button(role: .destructive) {
                        showWipeConfirm = true
                    } label: {
                        Label("Effacer les rides locaux", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("Effacer tous les rides locaux ?", isPresented: $showWipeConfirm) {
            Button("Annuler", role: .cancel) {}
            Button("Effacer", role: .destructive) {
                wipeLocalRides()
            }
        } message: {
            Text("Supprime toutes les sorties enregistrées via Track ou Naviguer. Les sorties Strava restent. À utiliser si une sortie corrompue empêche le feed de s'ouvrir.")
        }
        .task {
            // Always emit a "view opened" entry so a fresh process
            // launching straight into Diagnostics still has something
            // to display — useful when reporting "I never see anything"
            // bugs.
            Log.ui.notice("Diagnostics opened")
            await load()
        }
        .sheet(isPresented: $showShare) {
            if let items = shareItems {
                ShareSheet(items: items)
            }
        }
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        VStack(spacing: 8) {
            TextField("Rechercher dans les messages…", text: $search)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 14)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(TimeRange.allCases, id: \.self) { range in
                        chip(label: range.rawValue, selected: self.range == range) {
                            self.range = range
                            Task { await load() }
                        }
                    }
                    Divider().frame(height: 16)
                    ForEach(LogLevel.allCases, id: \.self) { level in
                        chip(
                            label: level.rawValue.uppercased(),
                            selected: minLevel == level,
                            color: level.color,
                        ) {
                            minLevel = level
                        }
                    }
                }
                .padding(.horizontal, 14)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip(label: "Toutes catégories", selected: selectedCategory == nil) {
                        selectedCategory = nil
                    }
                    ForEach(Log.allCategories, id: \.self) { cat in
                        chip(label: cat, selected: selectedCategory == cat) {
                            selectedCategory = cat
                        }
                    }
                }
                .padding(.horizontal, 14)
            }
        }
    }

    private func chip(label: String, selected: Bool, color: Color = AppColors.terra, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11).weight(selected ? .bold : .medium))
                .foregroundStyle(selected ? .white : AppColors.inkMid)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(selected ? color : AppColors.creamDark),
                )
                .overlay(Capsule().stroke(AppColors.creamBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Entries list

    @ViewBuilder
    private var entriesList: some View {
        if isLoading {
            VStack {
                ProgressView()
                Text("Chargement des logs…").font(.caption).foregroundStyle(AppColors.inkLight).padding(.top, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError {
            ContentUnavailableView("Logs indisponibles", systemImage: "doc.text.magnifyingglass", description: Text(error))
        } else if filteredEntries.isEmpty {
            ContentUnavailableView("Aucun log", systemImage: "checkmark.shield", description: Text("Pas d'erreur enregistrée dans la fenêtre sélectionnée."))
        } else {
            List(filteredEntries.reversed()) { entry in
                row(entry: entry)
                    .listRowBackground(AppColors.surface)
                    .listRowInsets(EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14))
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func row(entry: LogEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: entry.level.symbol)
                    .font(.system(size: 11))
                    .foregroundStyle(entry.level.color)
                Text(entry.category.uppercased())
                    .font(.system(size: 10).weight(.bold)).tracking(0.8)
                    .foregroundStyle(AppColors.inkLight)
                Spacer()
                Text(timeFormatter.string(from: entry.timestamp))
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(AppColors.inkLight)
            }
            Text(entry.message)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(AppColors.ink)
                .textSelection(.enabled)
        }
    }

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }

    // MARK: - Filtering

    private var filteredEntries: [LogEntry] {
        entries.filter { e in
            guard e.level.sortKey >= minLevel.sortKey else { return false }
            if let cat = selectedCategory, e.category != cat { return false }
            if !search.isEmpty, !e.message.localizedCaseInsensitiveContains(search) { return false }
            return true
        }
    }

    // MARK: - Loading from OSLogStore

    private func load() async {
        isLoading = true
        loadError = nil
        let result = await Task.detached(priority: .userInitiated) {
            await Self.fetchEntries(seconds: range.seconds)
        }.value
        switch result {
        case .success(let list):
            entries = list
        case .failure(let error):
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    private static func fetchEntries(seconds: TimeInterval) async -> Result<[LogEntry], Error> {
        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let cutoff = store.position(date: Date().addingTimeInterval(-seconds))
            // We only want messages from THIS app's subsystem — anything
            // from CoreFoundation, networking, etc. is noise here.
            let predicate = NSPredicate(format: "subsystem == %@", Log.subsystem)
            let raw = try store.getEntries(at: cutoff, matching: predicate)
            var out: [LogEntry] = []
            for entry in raw {
                guard let e = entry as? OSLogEntryLog else { continue }
                out.append(LogEntry(
                    timestamp: e.date,
                    level: levelFromOSLog(e.level),
                    category: e.category,
                    message: e.composedMessage,
                ))
            }
            return .success(out)
        } catch {
            return .failure(error)
        }
    }

    private static func levelFromOSLog(_ level: OSLogEntryLog.Level) -> LogLevel {
        switch level {
        case .undefined: return .info
        case .debug:     return .debug
        case .info:      return .info
        case .notice:    return .notice
        case .error:     return .error
        case .fault:     return .fault
        @unknown default: return .info
        }
    }

    // MARK: - Emergency wipe of local rides

    private func wipeLocalRides() {
        let user = environment.currentUser
        let local = environment.localRides.rides(for: user)
        Log.app.notice("Diagnostics wipe: removing \(local.count) local rides")
        for ride in local {
            environment.localRides.remove(id: ride.id, for: user)
        }
        environment.activityStore.refreshLocal(user: user)
    }

    // MARK: - Test entries (sanity check the pipeline)

    private func emitTestEntries() {
        Log.app.debug("Test debug entry — \(Date().timeIntervalSince1970)")
        Log.app.info("Test info entry — \(Date().timeIntervalSince1970)")
        Log.app.notice("Test notice entry — \(Date().timeIntervalSince1970)")
        Log.app.warning("Test warning entry — \(Date().timeIntervalSince1970)")
        Log.app.error("Test error entry — \(Date().timeIntervalSince1970, privacy: .public)")
    }

    // MARK: - Share

    private func share() {
        let lines = filteredEntries.map { e -> String in
            let ts = timeFormatter.string(from: e.timestamp)
            return "[\(ts)] [\(e.level.rawValue.uppercased())] [\(e.category)] \(e.message)"
        }
        let text = lines.joined(separator: "\n")
        let header = "Little Explorer logs · \(Date().formatted())\n\n"
        shareItems = [header + text]
        showShare = true
    }
}

// ShareSheet is defined in LittleExplorer/UI/ShareSheet.swift — reused
// here for log export so we don't duplicate the UIActivityViewController
// bridge.
