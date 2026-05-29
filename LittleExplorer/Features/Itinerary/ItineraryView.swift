import MapKit
import SwiftUI

/// Replaces the v0 PlannerView with the full Itinerary builder.
struct ItineraryView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var planner = PlannerState()
    /// Read the shared library from the environment so saves push to
    /// the backend (Phase A) and become visible to the Watch (Phase B)
    /// — the local-only @State copy was bypassing both layers.
    private var library: ItineraryStore { environment.itineraries }
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
                        .frame(height: 460)
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
                // Phase A: reconcile with the backend on every appear
                // so a save made on the web (or on another device)
                // shows up here without a manual refresh.
                Task { await library.syncFromServer(user: environment.currentUser) }
            }
            .onChange(of: environment.currentUser) { _, newUser in
                library.load(user: newUser)
                planner.clearAll()
                Task { await library.syncFromServer(user: newUser) }
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = gpxFileURL {
                    ShareSheet(items: [url])
                }
            }
            .sheet(isPresented: $showLibrarySheet) {
                librarySheet(planner: planner)
            }
            // fullScreenCover (vs navigationDestination) so navigation
            // takes over the WHOLE screen — covers the TabView's tab bar
            // AND the PlannerHubView's tab bar above. User explicitly
            // asked for "rien d'autre que le gps" during navigation.
            .fullScreenCover(item: $navigatingItinerary) { itinerary in
                NavigateView(itinerary: itinerary)
            }
            .alert("Supprimer cet itinéraire ?", isPresented: Binding(
                get: { pendingDeleteId != nil },
                set: { if !$0 { pendingDeleteId = nil } },
            )) {
                Button("Supprimer", role: .destructive) {
                    if let id = pendingDeleteId {
                        library.deleteAndUpload(id: id, user: environment.currentUser)
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

            // Action bar — compact icon+label pills on a single row so
            // the buttons don't word-wrap. "Naviguer" is the primary
            // action (filled terra), the rest are bordered.
            HStack(spacing: 8) {
                actionPill(
                    symbol: planner.extending ? "hourglass" : "arrow.up.left.and.arrow.down.right",
                    label: planner.extending ? "Auto…" : "Auto",
                    role: .secondary,
                    disabled: planner.extending || planner.distanceMeters == nil || planner.targetKm - (planner.distanceMeters ?? 0) / 1000 < 3,
                ) {
                    Task { await planner.autoExtend() }
                }

                actionPill(
                    symbol: "square.and.arrow.down",
                    label: "Sauver",
                    role: .secondary,
                    disabled: planner.waypoints.count < 2,
                ) {
                    save(planner: planner)
                }

                actionPill(
                    symbol: "square.and.arrow.up",
                    label: "GPX",
                    role: .secondary,
                    disabled: planner.geometry == nil || planner.waypoints.isEmpty,
                ) {
                    exportGpx(planner: planner)
                }

                actionPill(
                    symbol: "location.north.line.fill",
                    label: "Naviguer",
                    role: .primary,
                    disabled: planner.waypoints.count < 2 || planner.geometry == nil,
                ) {
                    startNavigate(planner: planner)
                }

                if !planner.waypoints.isEmpty {
                    Button(role: .destructive) {
                        planner.clearAll()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13))
                            .foregroundStyle(.red.opacity(0.75))
                            .frame(width: 38, height: 38)
                            .background(Color.red.opacity(0.10), in: Circle())
                    }
                    .buttonStyle(.plain)
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
        // Save locally + push to /api/itineraries so the Watch picks
        // it up via WCSession on next reachability.
        library.saveAndUpload(snapshot, user: environment.currentUser)
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

    /// Compact icon+label pill used by the action bar. Keeps all five
    /// actions on one row by sizing each button uniformly and using a
    /// small font; primary (Naviguer) is filled terra, the rest are
    /// bordered cream.
    private enum ActionRole { case primary, secondary }

    @ViewBuilder
    private func actionPill(symbol: String, label: String, role: ActionRole, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 11))
                Text(label).font(.system(size: 11).weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(role == .primary ? AppColors.terra : AppColors.creamDark, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(role == .primary ? Color.clear : AppColors.creamBorder, lineWidth: 1),
            )
            .foregroundStyle(role == .primary ? Color.white : AppColors.inkMid)
            .opacity(disabled ? 0.4 : 1)
        }
        .disabled(disabled)
        .buttonStyle(.plain)
    }
}
