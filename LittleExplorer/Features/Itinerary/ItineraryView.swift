import MapKit
import SwiftUI

/// Replaces the v0 PlannerView with the full Itinerary builder.
struct ItineraryView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var planner = PlannerState()
    @State private var library = ItineraryStore()
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 45.81, longitude: 4.75),
            span: MKCoordinateSpan(latitudeDelta: 0.35, longitudeDelta: 0.35),
        ),
    )
    @State private var showShareSheet = false
    @State private var gpxFileURL: URL?
    @State private var showLibrarySheet = false
    @State private var pendingDeleteId: String?
    @State private var navigatingItinerary: Itinerary?

    var body: some View {
        @Bindable var planner = planner
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VillageSearchView(placeholder: "Ajouter un village ou une adresse") { result in
                        planner.add(result.toWaypoint())
                        recenterMap()
                    }
                    .padding(.horizontal, 16)

                    map
                        .frame(height: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppColors.creamBorder, lineWidth: 1))
                        .padding(.horizontal, 16)

                    statsRow
                        .padding(.horizontal, 16)

                    controls(planner: planner)
                        .padding(.horizontal, 16)

                    if !planner.waypoints.isEmpty {
                        waypointsList(planner: planner)
                            .padding(.horizontal, 16)
                    }

                    if !planner.elevSeries.isEmpty || planner.elevationLoading {
                        ElevationChartView(
                            samples: planner.elevSeries,
                            ascent: planner.ascent,
                            descent: planner.descent,
                            loading: planner.elevationLoading,
                            selectedIndex: $planner.hoverIndex,
                        )
                        .padding(.horizontal, 16)
                    }

                    librarySection(planner: planner)
                        .padding(.horizontal, 16)
                }
                .padding(.vertical, 16)
            }
            .background(AppColors.cream)
            .navigationTitle("Itinéraire")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showLibrarySheet = true
                    } label: {
                        Label("Bibliothèque", systemImage: "books.vertical")
                    }
                }
            }
            .onAppear {
                library.load(user: environment.currentUser)
            }
            .onChange(of: environment.currentUser) { _, newUser in
                library.load(user: newUser)
                planner.clearAll()
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = gpxFileURL {
                    ShareSheet(items: [url])
                }
            }
            .sheet(isPresented: $showLibrarySheet) {
                librarySheet(planner: planner)
            }
            .navigationDestination(item: $navigatingItinerary) { itinerary in
                NavigateView(itinerary: itinerary)
            }
            .alert("Supprimer cet itinéraire ?", isPresented: Binding(
                get: { pendingDeleteId != nil },
                set: { if !$0 { pendingDeleteId = nil } },
            )) {
                Button("Supprimer", role: .destructive) {
                    if let id = pendingDeleteId {
                        library.remove(id: id, user: environment.currentUser)
                        if planner.activeId == id { planner.clearAll() }
                    }
                    pendingDeleteId = nil
                }
                Button("Annuler", role: .cancel) { pendingDeleteId = nil }
            }
        }
    }

    // MARK: - Map

    private var map: some View {
        Map(position: $cameraPosition) {
            if let geometry = planner.geometry, !geometry.isEmpty {
                MapPolyline(coordinates: geometry.map(\.clLocation))
                    .stroke(AppColors.terra, lineWidth: 4)
            }
            ForEach(Array(planner.waypoints.enumerated()), id: \.offset) { index, waypoint in
                Marker("\(index + 1)", coordinate: waypoint.coordinate.clLocation)
                    .tint(AppColors.terra)
            }
            // Synced marker from elevation chart drag.
            if let idx = planner.hoverIndex,
               let geometry = planner.geometry,
               let indices = planner.elevSampleIndices,
               indices.indices.contains(idx) {
                let geomIdx = indices[idx]
                if geometry.indices.contains(geomIdx) {
                    Annotation("", coordinate: geometry[geomIdx].clLocation) {
                        Circle()
                            .fill(AppColors.terra)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    }
                }
            }
        }
        .mapControls {
            MapCompass()
            MapScaleView()
        }
    }

    // MARK: - Stats row

    private var statsRow: some View {
        HStack(spacing: 16) {
            stat(label: "DISTANCE", value: planner.distanceMeters.map { String(format: "%.1f km", $0 / 1000) } ?? "—")
            stat(label: "DURÉE", value: planner.durationSeconds.map(formatDuration) ?? "—")
            stat(label: "D+", value: planner.ascent > 0 ? "\(planner.ascent) m" : "—", color: AppColors.terra)
            stat(label: "D−", value: planner.descent > 0 ? "\(planner.descent) m" : "—", color: AppColors.blue)
            if planner.routing { ProgressView().controlSize(.small) }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func stat(label: String, value: String, color: Color = AppColors.ink) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9).weight(.semibold))
                .tracking(1.0)
                .foregroundStyle(AppColors.inkLight)
            Text(value)
                .font(.system(.subheadline, design: .serif).weight(.bold))
                .foregroundStyle(color)
                .monospacedDigit()
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let h = Int(seconds / 3600)
        let m = Int((seconds.truncatingRemainder(dividingBy: 3600) / 60).rounded())
        return h > 0 ? "\(h)h\(String(format: "%02d", m))" : "\(m) min"
    }

    // MARK: - Controls (target km + loop + auto-extend + actions)

    @ViewBuilder
    private func controls(planner: PlannerState) -> some View {
        @Bindable var planner = planner
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("DISTANCE CIBLE")
                        .font(.system(size: 9).weight(.semibold))
                        .tracking(1.0)
                        .foregroundStyle(AppColors.inkLight)
                    HStack {
                        TextField("50", value: $planner.targetKm, format: .number)
                            .keyboardType(.numberPad)
                            .frame(width: 60)
                        Text("km").font(.caption).foregroundStyle(AppColors.inkLight)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppColors.cream, in: RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppColors.creamBorder, lineWidth: 1))
                }

                Toggle(isOn: Binding(
                    get: { planner.loop },
                    set: { planner.setLoop($0) },
                )) {
                    Text("Boucle (retour départ)")
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.inkMid)
                }
                .toggleStyle(.switch)
                .tint(AppColors.terra)
            }

            HStack(spacing: 8) {
                Button {
                    Task { await planner.autoExtend() }
                } label: {
                    Label(planner.extending ? "Allongement…" : "Auto-extend", systemImage: "arrow.up.right.and.arrow.down.left.rectangle")
                        .font(.system(size: 12).weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(AppColors.terra)
                .disabled(planner.extending || planner.distanceMeters == nil || planner.targetKm - (planner.distanceMeters ?? 0) / 1000 < 3)

                Button {
                    save(planner: planner)
                } label: {
                    Label("Sauver", systemImage: "square.and.arrow.down")
                        .font(.system(size: 12).weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColors.terra)
                .disabled(planner.waypoints.count < 2)

                Button {
                    exportGpx(planner: planner)
                } label: {
                    Label("GPX", systemImage: "square.and.arrow.up")
                        .font(.system(size: 12).weight(.semibold))
                }
                .buttonStyle(.bordered)
                .disabled(planner.geometry == nil || planner.waypoints.isEmpty)

                Button {
                    startNavigate(planner: planner)
                } label: {
                    Label("Naviguer", systemImage: "location.north.line.fill")
                        .font(.system(size: 12).weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(AppColors.green)
                .disabled(planner.waypoints.count < 2 || planner.geometry == nil)

                if !planner.waypoints.isEmpty {
                    Spacer()
                    Button(role: .destructive) {
                        planner.clearAll()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.bordered)
                }
            }

            if let error = planner.routeError {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            if let active = planner.activeId, !planner.name.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "bookmark.fill").font(.system(size: 10)).foregroundStyle(AppColors.terra)
                    Text("Actif : \(planner.name)").font(.system(size: 11)).foregroundStyle(AppColors.inkLight)
                    Text("· \(active.suffix(6))").font(.system(size: 9)).foregroundStyle(AppColors.inkLight.opacity(0.6))
                }
            }
        }
    }

    // MARK: - Waypoints list

    @ViewBuilder
    private func waypointsList(planner: PlannerState) -> some View {
        @Bindable var planner = planner
        VStack(alignment: .leading, spacing: 6) {
            Text("WAYPOINTS")
                .font(.system(size: 9).weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(AppColors.inkLight)
            ForEach(Array(planner.waypoints.enumerated()), id: \.element.id) { index, waypoint in
                HStack(spacing: 8) {
                    Text("\(index + 1)")
                        .font(.system(.caption, design: .serif).weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(AppColors.terra, in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(waypoint.name)
                            .font(.system(size: 13).weight(.semibold))
                            .foregroundStyle(AppColors.ink)
                            .lineLimit(1)
                        if let label = waypoint.label, label != waypoint.name {
                            Text(label).font(.system(size: 10)).foregroundStyle(AppColors.inkLight).lineLimit(1)
                        } else if let postal = waypoint.postal {
                            Text(postal).font(.system(size: 10)).foregroundStyle(AppColors.inkLight)
                        }
                    }
                    Spacer()
                    Button { planner.move(at: index, by: -1) } label: {
                        Image(systemName: "chevron.up").font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .disabled(index == 0)

                    Button { planner.move(at: index, by: 1) } label: {
                        Image(systemName: "chevron.down").font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .disabled(index == planner.waypoints.count - 1)

                    Button(role: .destructive) {
                        planner.remove(at: index)
                    } label: {
                        Image(systemName: "trash").font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppColors.creamBorder, lineWidth: 1))
            }
        }
    }

    // MARK: - Library section + sheet

    @ViewBuilder
    private func librarySection(planner: PlannerState) -> some View {
        if !library.items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("BIBLIOTHÈQUE")
                    .font(.system(size: 9).weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(AppColors.inkLight)
                ForEach(library.items.prefix(5)) { itinerary in
                    libraryRow(itinerary, planner: planner)
                }
                if library.items.count > 5 {
                    Button("Tout voir (\(library.items.count))") {
                        showLibrarySheet = true
                    }
                    .font(.caption)
                    .padding(.top, 4)
                }
            }
        }
    }

    @ViewBuilder
    private func librarySheet(planner: PlannerState) -> some View {
        NavigationStack {
            List {
                ForEach(library.items) { itinerary in
                    libraryRow(itinerary, planner: planner)
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Bibliothèque")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { showLibrarySheet = false }
                }
            }
        }
    }

    private func libraryRow(_ itinerary: Itinerary, planner: PlannerState) -> some View {
        Button {
            planner.load(itinerary)
            recenterMap()
            showLibrarySheet = false
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(itinerary.name)
                        .font(.system(size: 13).weight(.semibold))
                        .foregroundStyle(AppColors.ink)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        if let km = itinerary.distanceKm { Text("\(String(format: "%.1f", km)) km") }
                        if let asc = itinerary.totalAscent { Text("· D+ \(asc) m") }
                        Text("· \(itinerary.waypoints.count) stops")
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(AppColors.inkLight)
                }
                Spacer()
                if planner.activeId == itinerary.id {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(AppColors.terra)
                }
                Button(role: .destructive) {
                    pendingDeleteId = itinerary.id
                } label: {
                    Image(systemName: "trash").font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppColors.creamBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func recenterMap() {
        guard !planner.waypoints.isEmpty else { return }
        let lats = planner.waypoints.map(\.lat)
        let lngs = planner.waypoints.map(\.lng)
        let center = CLLocationCoordinate2D(
            latitude: (lats.min()! + lats.max()!) / 2,
            longitude: (lngs.min()! + lngs.max()!) / 2,
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.05, (lats.max()! - lats.min()!) * 1.4),
            longitudeDelta: max(0.05, (lngs.max()! - lngs.min()!) * 1.4),
        )
        cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
    }

    private func save(planner: PlannerState) {
        guard planner.waypoints.count >= 2 else { return }
        let snapshot = planner.snapshot()
        library.upsert(snapshot, user: environment.currentUser)
        planner.activeId = snapshot.id
        planner.name = snapshot.name
    }

    private func exportGpx(planner: PlannerState) {
        guard let geometry = planner.geometry, geometry.count >= 2, !planner.waypoints.isEmpty else { return }
        var perPointElev: [Double]?
        if let elevations = planner.elevations,
           let indices = planner.elevSampleIndices,
           elevations.count == indices.count {
            var per = Array(repeating: 0.0, count: geometry.count)
            for s in 0..<(indices.count - 1) {
                let i0 = indices[s]
                let i1 = indices[s + 1]
                let e0 = elevations[s]
                let e1 = elevations[s + 1]
                guard i1 > i0 else { continue }
                for i in i0...i1 where per.indices.contains(i) {
                    let t = Double(i - i0) / Double(i1 - i0)
                    per[i] = e0 + (e1 - e0) * t
                }
            }
            perPointElev = per
        }
        let routeName = planner.name.isEmpty ? planner.defaultName() : planner.name
        let gpx = GpxBuilder.build(
            name: routeName,
            waypoints: planner.waypoints,
            polyline: geometry,
            elevations: perPointElev,
        )
        let filename = "\(GpxBuilder.slugify(routeName)).gpx"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try gpx.write(to: url, atomically: true, encoding: .utf8)
            gpxFileURL = url
            showShareSheet = true
        } catch {
            Log.ui.error("Failed to write GPX: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func startNavigate(planner: PlannerState) {
        guard planner.waypoints.count >= 2, planner.geometry != nil else { return }
        if planner.activeId == nil {
            save(planner: planner)
        }
        let snapshot = planner.snapshot()
        navigatingItinerary = snapshot
    }
}
