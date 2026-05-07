import MapKit
import SwiftUI

struct PlannerView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var query: String = ""
    @State private var results: [CommuneResult] = []
    @State private var selectedWaypoints: [CommuneResult] = []
    @State private var route: BikeRoute?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                if !selectedWaypoints.isEmpty {
                    waypointsRow
                }
                if !results.isEmpty {
                    resultsList
                } else {
                    map
                }
            }
            .navigationTitle("Plan")
            .toolbar {
                if !selectedWaypoints.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Route") {
                            Task { await computeRoute() }
                        }
                        .disabled(selectedWaypoints.count < 2)
                    }
                }
            }
            .alert("Routing failed", isPresented: .constant(error != nil)) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
        }
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search a place", text: $query)
                .textInputAutocapitalization(.never)
                .onChange(of: query) { _, newValue in
                    Task { await search(newValue) }
                }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding()
    }

    private var waypointsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(Array(selectedWaypoints.enumerated()), id: \.offset) { index, waypoint in
                    chip(text: "\(index + 1). \(waypoint.name)") {
                        selectedWaypoints.remove(at: index)
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private var resultsList: some View {
        List(results) { result in
            Button {
                selectedWaypoints.append(result)
                results = []
                query = ""
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.label ?? result.name).foregroundStyle(.primary)
                    if let postal = result.postal {
                        Text(postal).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var map: some View {
        Map {
            if let route, !route.geometry.isEmpty {
                MapPolyline(coordinates: route.geometry.map(\.clLocation))
                    .stroke(Color.accentColor, lineWidth: 4)
            }
            ForEach(Array(selectedWaypoints.enumerated()), id: \.offset) { index, waypoint in
                Marker("\(index + 1)", coordinate: waypoint.coordinate.clLocation)
            }
        }
    }

    private func chip(text: String, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text(text)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: Capsule())
    }

    private func search(_ text: String) async {
        guard text.count >= 2 else {
            results = []
            return
        }
        do {
            results = try await environment.api.searchPlaces(query: text)
        } catch {
            // Silent — autocomplete is best-effort.
        }
    }

    private func computeRoute() async {
        do {
            route = try await environment.api.bikeRoute(
                waypoints: selectedWaypoints.map(\.coordinate),
                steps: false,
            )
        } catch {
            self.error = error.localizedDescription
        }
    }
}
