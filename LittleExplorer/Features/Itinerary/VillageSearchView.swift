import SwiftUI

/// Debounced BAN address typeahead. Returns CommuneResults the parent
/// converts into Waypoints. Shows precise / locality / municipality
/// hierarchy with kind-specific glyphs (◉ ◦ ═ ⌂).
struct VillageSearchView: View {
    var placeholder: String = "Chercher un village ou une adresse"
    var onPick: (CommuneResult) -> Void

    @Environment(AppEnvironment.self) private var environment
    @State private var query: String = ""
    @State private var results: [CommuneResult] = []
    @State private var loading = false
    @State private var isFocused = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField(placeholder, text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: query) { _, newValue in
                        scheduleSearch(newValue)
                    }
                    .onSubmit { scheduleSearch(query) }
                if loading {
                    ProgressView().controlSize(.mini)
                } else if !query.isEmpty {
                    Button {
                        query = ""
                        results = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(AppColors.inkLight)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(AppColors.cream, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppColors.creamBorder, lineWidth: 1))

            if !results.isEmpty {
                resultsList
            }
        }
    }

    private var resultsList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(results.enumerated()), id: \.offset) { _, result in
                    Button {
                        onPick(result)
                        query = ""
                        results = []
                    } label: {
                        row(result)
                    }
                    .buttonStyle(.plain)
                    Divider().background(AppColors.creamBorder)
                }
            }
        }
        .frame(maxHeight: 240)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppColors.creamBorder, lineWidth: 1))
    }

    private func row(_ result: CommuneResult) -> some View {
        let kind = Waypoint.PlaceKind(rawValue: result.kind ?? "")
        let isPrecise = kind == .housenumber || kind == .street
        let glyph: String = {
            switch kind {
            case .housenumber: return "house.fill"
            case .street:      return "road.lanes"
            case .locality:    return "mappin"
            case .municipality, nil, .some(.municipality): return "mappin.circle.fill"
            }
        }()
        return HStack(alignment: .center, spacing: 10) {
            Image(systemName: glyph)
                .foregroundStyle(isPrecise ? AppColors.terra : AppColors.inkLight)
                .font(.system(size: 13))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(result.name)
                    .font(.system(size: 13).weight(isPrecise ? .semibold : .medium))
                    .foregroundStyle(AppColors.ink)
                    .lineLimit(1)
                if isPrecise {
                    let secondary = [result.label, result.postal]
                        .compactMap { $0 }
                        .filter { !$0.isEmpty }
                        .joined(separator: " · ")
                    if !secondary.isEmpty {
                        Text(secondary)
                            .font(.system(size: 10))
                            .foregroundStyle(AppColors.inkLight)
                            .lineLimit(1)
                    }
                }
            }
            Spacer()
            if !isPrecise, let postal = result.postal {
                Text(postal).font(.system(size: 10)).foregroundStyle(AppColors.inkLight)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func scheduleSearch(_ text: String) {
        searchTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            results = []
            loading = false
            return
        }
        loading = true
        searchTask = Task { [api = environment.api] in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            do {
                let response = try await api.searchPlaces(query: trimmed)
                guard !Task.isCancelled else { return }
                results = response
            } catch {
                results = []
            }
            loading = false
        }
    }
}
