import MapKit
import SwiftUI
import UniformTypeIdentifiers

/// Replaces the v0 PlannerView with the full Itinerary builder.
struct ItineraryView: View {
    @Environment(AppEnvironment.self) private var environment
    /// OSRM routing profile: "bike" (default) or "foot" (running).
    var routingProfile: String = "bike"
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
    @State private var showFullMap = false
    @State private var detailItinerary: Itinerary?
    /// Set when the user taps "Naviguer" inside the detail sheet — we kick
    /// off navigation in the sheet's onDismiss so the full-screen cover
    /// doesn't fight the dismissing sheet for presentation.
    @State private var pendingNavigateAfterDetail: Itinerary?
    /// Set when a route is tapped from inside the "Bibliothèque" sheet — we
    /// can't present the detail sheet over another sheet, so we close the
    /// library sheet first and open the detail in its onDismiss.
    @State private var pendingDetailAfterLibrary: Itinerary?
    @State private var showImporter = false
    @State private var importError: String?
    // Click-to-add: tapping the full-screen map drops a pending point and
    // opens a confirmation card. `pendingResult` is the reverse-geocoded
    // name shown while the user decides; confirming appends it to the route.
    @State private var pendingTap: CLLocationCoordinate2D?
    @State private var pendingResult: CommuneResult?
    @State private var pendingLoading = false
    // Resupply points (water / food) along the route — lazily fetched when
    // the rider enables the "Ravito" toggle on the full-screen map.
    @State private var showPois = false
    @State private var pois: [APIClient.RoutePoi] = []
    @State private var poisLoading = false
    @State private var poiFetchedKey = ""
    /// Collapses the stops list (mirrors the web's "Réduire" button) so a
    /// long route doesn't push the rest of the form down.
    @State private var stopsCollapsed = false

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

                    mapPreview(planner: planner)
                        .frame(height: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColors.creamBorder, lineWidth: 1))
                        .padding(.horizontal, 16)

                    statsRow
                        .padding(.horizontal, 16)

                    controls(planner: planner)
                        .padding(.horizontal, 16)

                    if !planner.waypoints.isEmpty {
                        waypointsList(planner: planner)
                            .padding(.horizontal, 16)
                    }

                    colsSection(planner: planner)
                        .padding(.horizontal, 16)

                    if !planner.elevSeries.isEmpty || planner.elevationLoading {
                        // Full-bleed (no horizontal padding) so the profile
                        // always spans the screen width — it was randomly
                        // shrinking when the parent didn't hand it the full
                        // width; ElevationChartView now also pins maxWidth.
                        ElevationChartView(
                            samples: planner.elevSeries,
                            ascent: planner.ascent,
                            descent: planner.descent,
                            loading: planner.elevationLoading,
                            selectedIndex: $planner.hoverIndex,
                        )
                    }
                }
                .padding(.vertical, 16)
            }
            .background(AppColors.cream)
            .navigationTitle("Itinéraire")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showImporter = true
                    } label: {
                        Label("Importer un GPX", systemImage: "square.and.arrow.down")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showLibrarySheet = true
                    } label: {
                        Label("Bibliothèque", systemImage: "books.vertical")
                    }
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [UTType(filenameExtension: "gpx") ?? .xml, .xml],
                allowsMultipleSelection: false,
            ) { result in
                handleImport(result, planner: planner)
            }
            .alert("Import GPX", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } },
            )) {
                Button("OK", role: .cancel) { importError = nil }
            } message: {
                Text(importError ?? "")
            }
            .onAppear {
                planner.routingProfile = routingProfile
                planner.scheduleColsRefresh()
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
            .sheet(isPresented: $showLibrarySheet, onDismiss: {
                if let it = pendingDetailAfterLibrary {
                    pendingDetailAfterLibrary = nil
                    detailItinerary = it
                }
            }) {
                librarySheet(planner: planner)
            }
            // fullScreenCover (vs navigationDestination) so navigation
            // takes over the WHOLE screen — covers the TabView's tab bar
            // AND the PlannerHubView's tab bar above. User explicitly
            // asked for "rien d'autre que le gps" during navigation.
            .fullScreenCover(item: $navigatingItinerary) { itinerary in
                NavigateView(itinerary: itinerary)
            }
            .fullScreenCover(isPresented: $showFullMap, onDismiss: { clearPendingTap() }) {
                fullMapView(planner: planner)
            }
            .sheet(item: $detailItinerary, onDismiss: {
                if let it = pendingNavigateAfterDetail {
                    pendingNavigateAfterDetail = nil
                    navigatingItinerary = it
                }
            }) { it in
                ItineraryDetailView(
                    itinerary: it,
                    onLoad: {
                        planner.load(it)
                        recenterMap()
                        showLibrarySheet = false
                    },
                    onNavigate: {
                        planner.load(it)
                        pendingNavigateAfterDetail = it
                    },
                )
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

    // MARK: - Cols à proximité

    /// Nearby cols / summits around the departure (cycling only). Mirrors the
    /// web: radius selector + a tappable list, in sync with the map pins.
    @ViewBuilder
    private func colsSection(planner: PlannerState) -> some View {
        if planner.routingProfile == "bike", !planner.waypoints.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("COLS À PROXIMITÉ")
                        .font(.system(size: 12, weight: .semibold)).tracking(1)
                        .foregroundStyle(AppColors.inkMid)
                    if planner.colsLoading {
                        ProgressView().scaleEffect(0.7)
                    }
                    Spacer()
                    HStack(spacing: 5) {
                        ForEach([10.0, 15, 25, 50], id: \.self) { r in
                            Button {
                                planner.setColRadius(r)
                            } label: {
                                Text("\(Int(r))")
                                    .font(.system(size: 12, weight: .semibold))
                                    .padding(.vertical, 4).padding(.horizontal, 9)
                                    .background(
                                        planner.colRadiusKm == r ? AnyShapeStyle(AppColors.terra) : AnyShapeStyle(AppColors.creamDark),
                                        in: Capsule())
                                    .foregroundStyle(planner.colRadiusKm == r ? .white : AppColors.inkMid)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if planner.cols.isEmpty {
                    Text(planner.colsLoading ? "Recherche des cols…" : "Aucun col trouvé dans ce rayon.")
                        .font(.system(size: 12)).foregroundStyle(AppColors.inkLight)
                        .padding(.vertical, 4)
                } else {
                    Text("Aussi sur la carte. Touche pour ajouter ou retirer.")
                        .font(.system(size: 11)).foregroundStyle(AppColors.inkLight)
                    VStack(spacing: 6) {
                        ForEach(planner.cols.prefix(40)) { col in
                            colRow(col, planner: planner)
                        }
                    }
                }
            }
            .padding(14)
            .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColors.creamBorder, lineWidth: 1))
        }
    }

    private func colRow(_ col: APIClient.Col, planner: PlannerState) -> some View {
        let selected = planner.isColSelected(col)
        return Button {
            planner.toggleCol(col)
        } label: {
            HStack(spacing: 10) {
                Text(col.isSummit ? "🗻" : "⛰️").font(.system(size: 16))
                VStack(alignment: .leading, spacing: 2) {
                    Text(col.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.ink).lineLimit(1)
                    Text(colSubtitle(col))
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.inkLight).lineLimit(1)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(selected ? AppColors.terra : AppColors.inkLight)
            }
            .padding(.vertical, 7).padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? AppColors.terraLight : AppColors.cream, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? AppColors.terra : AppColors.creamBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func colSubtitle(_ col: APIClient.Col) -> String {
        var parts: [String] = []
        if let city = col.city { parts.append(city) }
        if let ele = col.ele { parts.append("\(ele) m") }
        parts.append(String(format: "%.1f km", col.distKm))
        return parts.joined(separator: " · ")
    }

    // MARK: - Map

    /// Polyline + waypoint markers, shared by the inline preview and the
    /// full-screen interactive map.
    @MapContentBuilder
    private func routeMapContent(_ planner: PlannerState) -> some MapContent {
        if let geometry = planner.geometry, !geometry.isEmpty {
            MapPolyline(coordinates: geometry.map(\.clLocation))
                .stroke(AppColors.terra, lineWidth: 4)
        }
        // Minimalist stop markers — small dots instead of big labelled pins
        // so a route with many points stays readable. The ordered list below
        // the map carries the names.
        ForEach(Array(planner.waypoints.enumerated()), id: \.offset) { index, waypoint in
            Annotation("", coordinate: waypoint.coordinate.clLocation) {
                Circle()
                    .fill(AppColors.terra)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
            }
            .annotationTitles(.hidden)
        }
        // Cols & summits near the departure (cycling only). Small ⛰/🗻 pins;
        // tap to add the col to the route, or remove it (orange when in).
        if planner.routingProfile == "bike" {
            ForEach(planner.cols) { col in
                let selected = planner.isColSelected(col)
                Annotation("", coordinate: col.coordinate.clLocation) {
                    ZStack {
                        Circle()
                            .fill(selected ? AppColors.terra : Color.white)
                            .frame(width: 18, height: 18)
                            .overlay(Circle().stroke(selected ? Color.white : AppColors.inkMid.opacity(0.5), lineWidth: 1.5))
                        Text(col.isSummit ? "🗻" : "⛰️").font(.system(size: 10))
                    }
                    .onTapGesture { planner.toggleCol(col) }
                }
                .annotationTitles(.hidden)
            }
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

    /// Inline map *preview*. `interactionModes: []` makes it non-
    /// interactive, so a vertical drag passes straight through to the
    /// surrounding ScrollView — the page scrolls even with a finger on
    /// the map, instead of the map trapping the gesture. Tap "Agrandir"
    /// (or the map) for a full-screen interactive map to pan / zoom.
    private func mapPreview(planner: PlannerState) -> some View {
        Map(position: $cameraPosition, interactionModes: []) {
            routeMapContent(planner)
        }
        .overlay(alignment: .topTrailing) {
            Button {
                showFullMap = true
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.ink)
                    .padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .padding(8)
        }
        .overlay(alignment: .bottomLeading) {
            if planner.waypoints.isEmpty {
                Text("Cherche un village ou une adresse pour commencer")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.inkMid)
                    .padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                    .padding(8)
            }
        }
        // A plain tap (not a drag) opens the full-screen map; drags still
        // scroll the page since the map itself ignores gestures.
        .onTapGesture { showFullMap = true }
    }

    /// Full-screen interactive map (pan / zoom / rotate), opened from the
    /// preview. Tap anywhere to drop a precise point and add it to the route.
    private func fullMapView(planner: PlannerState) -> some View {
        ZStack {
            MapReader { proxy in
                Map(position: $cameraPosition) {
                    routeMapContent(planner)
                    // Resupply points (water / food) along the route.
                    if showPois {
                        ForEach(pois) { poi in
                            Annotation("", coordinate: poi.coordinate.clLocation) {
                                ZStack {
                                    Circle().fill(poiColor(poi.cat)).frame(width: 14, height: 14)
                                        .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                                    Text(poiIcon(poi.cat)).font(.system(size: 9))
                                }
                            }
                            .annotationTitles(.hidden)
                        }
                    }
                    // Pending tapped point — a green halo so the user sees
                    // exactly where the new stop will land.
                    if let tap = pendingTap {
                        Annotation("", coordinate: tap) {
                            ZStack {
                                Circle().fill(AppColors.green.opacity(0.25)).frame(width: 30, height: 30)
                                Circle().fill(AppColors.green).frame(width: 14, height: 14)
                                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                            }
                        }
                        .annotationTitles(.hidden)
                    }
                }
                .mapControls {
                    MapCompass()
                    MapScaleView()
                }
                .ignoresSafeArea()
                .onTapGesture { location in
                    guard let coord = proxy.convert(location, from: .local) else { return }
                    pendingTap = coord
                    pendingResult = nil
                    pendingLoading = true
                    Task {
                        let hit = await planner.reverseLookup(lat: coord.latitude, lng: coord.longitude)
                        pendingResult = hit
                        pendingLoading = false
                    }
                }
            }

            // Close button (top-trailing).
            Button {
                showFullMap = false
                clearPendingTap()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AppColors.ink)
                    .padding(12)
                    .background(.regularMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            // Ravito toggle (top-leading) — water + food points along the route.
            if let geom = planner.geometry, geom.count > 1 {
                Button {
                    showPois.toggle()
                    if showPois { Task { await loadPois(geom) } }
                } label: {
                    HStack(spacing: 5) {
                        Text("💧").font(.system(size: 13))
                        Text("Ravito").font(.system(size: 13, weight: .semibold))
                        if showPois {
                            if poisLoading { Text("…") } else { Text("· \(pois.count)") }
                        }
                    }
                    .foregroundStyle(showPois ? .white : AppColors.ink)
                    .padding(.horizontal, 11).padding(.vertical, 8)
                    .background(showPois ? AnyShapeStyle(AppColors.terra) : AnyShapeStyle(.regularMaterial),
                                in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

            // Hint when nothing is pending, or the confirmation card.
            if let tap = pendingTap {
                addPointCard(planner: planner, coord: tap)
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                Text("Touche la carte pour ajouter un point")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        .animation(.easeOut(duration: 0.18), value: pendingTap == nil)
    }

    /// Confirmation card for a tapped point — pinned to the bottom of the
    /// full-screen map. Plain SwiftUI, so its buttons never interfere with
    /// the map's own tap handling.
    private func addPointCard(planner: PlannerState, coord: CLLocationCoordinate2D) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("AJOUTER CE POINT ?")
                        .font(.system(size: 9).weight(.bold)).tracking(1.2)
                        .foregroundStyle(AppColors.inkLight)
                    if pendingLoading {
                        Text("Localisation…")
                            .font(.system(size: 15).weight(.semibold)).foregroundStyle(AppColors.ink)
                    } else {
                        Text(pendingResult?.name ?? String(format: "%.4f, %.4f", coord.latitude, coord.longitude))
                            .font(.system(size: 15).weight(.semibold)).foregroundStyle(AppColors.ink)
                            .lineLimit(2)
                        if let postal = pendingResult?.postal, !postal.isEmpty {
                            Text(postal).font(.system(size: 11)).foregroundStyle(AppColors.inkLight)
                        }
                    }
                }
                Spacer(minLength: 8)
                Button { clearPendingTap() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(AppColors.inkMid)
                        .padding(8).background(AppColors.creamDark, in: Circle())
                }
                .buttonStyle(.plain)
            }
            Button {
                planner.addPrecisePoint(lat: coord.latitude, lng: coord.longitude, from: pendingResult)
                clearPendingTap()
            } label: {
                Text("+ AJOUTER AU PARCOURS")
                    .font(.system(size: 12).weight(.bold)).tracking(1.0)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(AppColors.green, in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.creamBorder, lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 4)
    }

    private func clearPendingTap() {
        pendingTap = nil
        pendingResult = nil
        pendingLoading = false
    }

    // MARK: - Resupply points

    private func poiColor(_ cat: String) -> Color {
        switch cat {
        case "water":       return Color(red: 0.24, green: 0.65, blue: 0.85)
        case "supermarket": return Color(red: 0.31, green: 0.60, blue: 0.33)
        case "convenience": return Color(red: 0.18, green: 0.64, blue: 0.60)
        case "bakery":      return Color(red: 0.85, green: 0.56, blue: 0.24)
        default:            return AppColors.inkMid
        }
    }

    private func poiIcon(_ cat: String) -> String {
        switch cat {
        case "water":       return "💧"
        case "supermarket": return "🛒"
        case "convenience": return "🏪"
        case "bakery":      return "🥐"
        default:            return "📍"
        }
    }

    /// Fetch resupply points for the given geometry, keyed so we don't
    /// re-hit Overpass for a route we've already loaded.
    private func loadPois(_ geometry: [Coordinate]) async {
        let key = "\(geometry.count):\(geometry.first?.lat ?? 0),\(geometry.last?.lat ?? 0)"
        if poiFetchedKey == key, !pois.isEmpty { return }
        poiFetchedKey = key
        poisLoading = true
        defer { poisLoading = false }
        let fetched = (try? await environment.api.routePois(geometry: geometry)) ?? []
        pois = fetched
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
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("POINTS DE PASSAGE")
                    .font(.system(size: 9).weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(AppColors.inkLight)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { stopsCollapsed.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Text("\(planner.waypoints.count)").foregroundStyle(AppColors.terra)
                        Text(stopsCollapsed ? "Afficher" : "Réduire")
                        Image(systemName: stopsCollapsed ? "chevron.down" : "chevron.up").font(.system(size: 9))
                    }
                    .font(.system(size: 10).weight(.semibold))
                    .foregroundStyle(AppColors.inkMid)
                }
                .buttonStyle(.plain)
            }
            if stopsCollapsed {
                Text("\(planner.waypoints.first?.name ?? "")  →  \(planner.waypoints.last?.name ?? "")\(planner.loop ? "  ↺" : "")")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.inkMid)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(AppColors.creamDark, in: RoundedRectangle(cornerRadius: 4))
            } else {
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
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(library.items.count) itinéraire\(library.items.count > 1 ? "s" : "") enregistré\(library.items.count > 1 ? "s" : "")")
                        .font(.system(size: 12).weight(.semibold))
                        .foregroundStyle(AppColors.inkLight)
                    if library.items.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "map").font(.system(size: 20)).foregroundStyle(AppColors.inkLight)
                            Text("Aucun itinéraire enregistré.").font(.system(size: 13)).foregroundStyle(AppColors.inkLight)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 40)
                    } else {
                        ForEach(library.items) { itinerary in
                            libraryRow(itinerary, planner: planner)
                        }
                    }
                }
                .padding(16)
            }
            .background(AppColors.cream)
            .navigationTitle("Itinéraires enregistrés")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { showLibrarySheet = false }
                }
            }
        }
    }

    /// Komoot-style saved-route card: a large map banner with the
    /// difficulty badge overlaid, then title, duration / distance / D+
    /// metrics, and date + start place below.
    private func libraryRow(_ itinerary: Itinerary, planner: PlannerState) -> some View {
        let isActive = planner.activeId == itinerary.id
        let diff = difficulty(for: itinerary)
        return Button {
            // Can't stack a sheet on a sheet: if we're inside the library
            // sheet, close it and open the detail once it's dismissed.
            if showLibrarySheet {
                pendingDetailAfterLibrary = itinerary
                showLibrarySheet = false
            } else {
                detailItinerary = itinerary
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                // Map banner
                RouteThumbnail(geometry: itinerary.geometry ?? [], waypoints: itinerary.waypoints)
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .overlay(alignment: .topLeading) {
                        Text(diff.label.uppercased())
                            .font(.system(size: 10).weight(.bold)).tracking(0.6)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(diff.color, in: Capsule())
                            .padding(10)
                    }
                    .overlay(alignment: .topTrailing) {
                        if isActive {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(AppColors.terra)
                                .padding(5)
                                .background(.regularMaterial, in: Circle())
                                .padding(10)
                        }
                    }

                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(itinerary.name)
                            .font(.system(size: 19, design: .serif).weight(.bold))
                            .foregroundStyle(AppColors.ink)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Button(role: .destructive) {
                            pendingDeleteId = itinerary.id
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 15))
                                .foregroundStyle(.red.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }

                    HStack(spacing: 16) {
                        if let min = itinerary.durationMin { metric("clock", formatDur(min)) }
                        if let km = itinerary.distanceKm { metric("ruler", String(format: "%.1f km", km)) }
                        if let asc = itinerary.totalAscent { metric("arrow.up.right", "\(asc) m") }
                        Spacer(minLength: 0)
                    }

                    Text(subtitle(for: itinerary))
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.inkLight)
                        .lineLimit(1)
                }
                .padding(14)
            }
            .background(AppColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isActive ? AppColors.terra : AppColors.creamBorder, lineWidth: isActive ? 1.5 : 1),
            )
        }
        .buttonStyle(.plain)
    }

    private func metric(_ symbol: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(AppColors.inkLight)
            Text(value).font(.system(size: 13).weight(.medium)).foregroundStyle(AppColors.inkMid)
        }
    }

    private func formatDur(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        return h > 0 ? "\(h)h\(String(format: "%02d", m))" : "\(m) min"
    }

    private struct DifficultyTag { let label: String; let color: Color }

    /// Derive a Komoot-style difficulty from distance + climbing, since we
    /// don't store an explicit rating. effort = km + D+/8 → Facile / Modéré
    /// / Difficile (tuned so 26 km/360 m = Modéré, 71 km/1050 m = Difficile).
    private func difficulty(for it: Itinerary) -> DifficultyTag {
        let dist = it.distanceKm ?? 0
        let asc = Double(it.totalAscent ?? 0)
        let effort = dist + asc / 8
        if effort < 50 { return DifficultyTag(label: "Facile", color: AppColors.green) }
        if effort < 150 { return DifficultyTag(label: "Modéré", color: AppColors.terra) }
        return DifficultyTag(label: "Difficile", color: Color(red: 0.61, green: 0.23, blue: 0.10))
    }

    private func subtitle(for it: Itinerary) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "fr_FR")
        fmt.dateFormat = "d MMM yyyy"
        let date = fmt.string(from: it.createdAt)
        if let place = it.waypoints.first?.city ?? it.waypoints.first?.name {
            return "\(date) · \(place)"
        }
        return date
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

    /// Read a picked GPX file, build an itinerary from it, save it to the
    /// library, and load it onto the map.
    private func handleImport(_ result: Result<[URL], Error>, planner: PlannerState) {
        switch result {
        case .failure(let error):
            importError = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                guard let itinerary = GPXImport.itinerary(from: data) else {
                    importError = "Ce fichier GPX ne contient pas de tracé exploitable."
                    return
                }
                library.saveAndUpload(itinerary, user: environment.currentUser)
                planner.load(itinerary)
                recenterMap()
                detailItinerary = itinerary
            } catch {
                importError = "Lecture du fichier impossible : \(error.localizedDescription)"
            }
        }
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

// MARK: - Route thumbnail

/// Small static map showing a saved route's polyline, used by the
/// library cards. `interactionModes: []` keeps it non-interactive so it
/// never steals taps/scrolls from the enclosing card button or list.
struct RouteThumbnail: View {
    let geometry: [Coordinate]
    let waypoints: [Waypoint]

    var body: some View {
        if geometry.count >= 2 || !waypoints.isEmpty {
            Map(initialPosition: .region(region), interactionModes: []) {
                if geometry.count >= 2 {
                    MapPolyline(coordinates: geometry.map(\.clLocation))
                        .stroke(AppColors.terra, lineWidth: 3)
                }
            }
            .allowsHitTesting(false)
        } else {
            ZStack {
                AppColors.creamDark
                Image(systemName: "map").font(.system(size: 18)).foregroundStyle(AppColors.inkLight)
            }
        }
    }

    private var region: MKCoordinateRegion {
        let coords: [CLLocationCoordinate2D] = geometry.isEmpty
            ? waypoints.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
            : geometry.map(\.clLocation)
        guard
            let minLat = coords.map(\.latitude).min(),
            let maxLat = coords.map(\.latitude).max(),
            let minLng = coords.map(\.longitude).min(),
            let maxLng = coords.map(\.longitude).max()
        else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 45.81, longitude: 4.75),
                span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1),
            )
        }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2),
            span: MKCoordinateSpan(
                latitudeDelta: max(0.01, (maxLat - minLat) * 1.5),
                longitudeDelta: max(0.01, (maxLng - minLng) * 1.5),
            ),
        )
    }
}
