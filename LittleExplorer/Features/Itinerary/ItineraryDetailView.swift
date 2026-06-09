import MapKit
import SwiftUI

/// Komoot-style detail view for a saved itinerary, shown when you open a
/// route from the library. Map banner, title + difficulty, the full-width
/// elevation profile, a stats grid, and the list of points de passage —
/// with "Naviguer" / "Charger dans le planificateur" actions.
///
/// (Phase 1. Montées et descentes needs a finer elevation stream than the
/// 80-point profile we persist; Types de voies / Surfaces needs an OSM
/// enrichment pipeline — both are follow-ups.)
struct ItineraryDetailView: View {
    let itinerary: Itinerary
    /// Load this route into the planner/builder.
    let onLoad: () -> Void
    /// Start turn-by-turn navigation for this route.
    let onNavigate: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var environment
    @State private var selectedIndex: Int?
    @State private var analysis: APIClient.RouteAnalysis?
    @State private var analysisLoading = false
    @State private var analysisFailed = false
    /// Tapping the banner opens a full-screen, pan/zoomable map of the route.
    @State private var showFullMap = false
    /// Collapses the (often long) points-de-passage list by default.
    @State private var waypointsCollapsed = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    banner
                    title
                    elevationSection
                    statsSection
                    waysSection
                    waypointsSection
                }
                .padding(.bottom, 24)
            }
            .background(AppColors.cream)
            .navigationTitle("Itinéraire")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) { actionBar }
            .task { await loadAnalysis() }
            .fullScreenCover(isPresented: $showFullMap) { fullMapView }
        }
    }

    // MARK: Banner

    private var banner: some View {
        RouteThumbnail(geometry: itinerary.geometry ?? [], waypoints: itinerary.waypoints)
            .frame(height: 200)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay(alignment: .topLeading) {
                Text(diff.label.uppercased())
                    .font(.system(size: 11).weight(.bold)).tracking(0.6)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(diff.color, in: Capsule())
                    .padding(14)
            }
            // Tap-to-expand affordance, mirroring the web's clickable map.
            .overlay(alignment: .bottomTrailing) {
                Label("Agrandir", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11).weight(.semibold))
                    .foregroundStyle(AppColors.ink)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                    .padding(12)
            }
            .contentShape(Rectangle())
            .onTapGesture { showFullMap = true }
    }

    // MARK: Full-screen interactive map

    private var fullMapView: some View {
        ZStack(alignment: .topTrailing) {
            Map(initialPosition: .region(routeRegion)) {
                if let geom = itinerary.geometry, geom.count >= 2 {
                    MapPolyline(coordinates: geom.map(\.clLocation))
                        .stroke(AppColors.terra, lineWidth: 4)
                }
                ForEach(Array(itinerary.waypoints.enumerated()), id: \.offset) { _, wp in
                    Annotation("", coordinate: wp.coordinate.clLocation) {
                        Circle()
                            .fill(AppColors.terra)
                            .frame(width: 11, height: 11)
                            .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                    }
                    .annotationTitles(.hidden)
                }
            }
            .ignoresSafeArea()

            Button { showFullMap = false } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AppColors.ink)
                    .padding(12)
                    .background(.regularMaterial, in: Circle())
            }
            .padding(16)
        }
    }

    /// Map region fitted to the route (geometry, else waypoints).
    private var routeRegion: MKCoordinateRegion {
        let coords: [CLLocationCoordinate2D] = (itinerary.geometry?.isEmpty == false)
            ? (itinerary.geometry ?? []).map(\.clLocation)
            : itinerary.waypoints.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
        guard
            let minLat = coords.map(\.latitude).min(), let maxLat = coords.map(\.latitude).max(),
            let minLng = coords.map(\.longitude).min(), let maxLng = coords.map(\.longitude).max()
        else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 45.81, longitude: 4.75),
                span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1))
        }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2),
            span: MKCoordinateSpan(
                latitudeDelta: max(0.01, (maxLat - minLat) * 1.4),
                longitudeDelta: max(0.01, (maxLng - minLng) * 1.4)))
    }

    // MARK: Title

    private var title: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(itinerary.name)
                .font(.system(size: 26, design: .serif).weight(.heavy))
                .foregroundStyle(AppColors.ink)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(AppColors.inkLight)
        }
        .padding(.horizontal, 16)
    }

    // MARK: Elevation

    @ViewBuilder
    private var elevationSection: some View {
        if !samples.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("Élévation")
                ElevationChartView(
                    samples: samples,
                    ascent: ascent,
                    descent: descent,
                    loading: false,
                    selectedIndex: $selectedIndex,
                )
            }
        }
    }

    // MARK: Stats grid

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Statistiques").padding(.horizontal, 16)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                if let km = itinerary.distanceKm { stat("Distance", String(format: "%.1f km", km)) }
                if let min = itinerary.durationMin { stat("Durée", formatDur(min)) }
                if let v = avgSpeed { stat("Vitesse moy.", String(format: "%.1f km/h", v)) }
                stat("Dénivelé +", "\(ascent) m", color: AppColors.terra)
                stat("Dénivelé −", "\(descent) m", color: AppColors.blue)
                if let pts = itinerary.waypoints.count as Int? { stat("Points", "\(pts)") }
                if let hi = highest { stat("Point haut", "\(hi) m") }
                if let lo = lowest { stat("Point bas", "\(lo) m") }
            }
            .padding(.horizontal, 16)
        }
    }

    private func stat(_ label: String, _ value: String, color: Color = AppColors.ink) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 9).weight(.bold)).tracking(0.5)
                .foregroundStyle(AppColors.inkLight)
            Text(value)
                .font(.system(size: 17, design: .serif).weight(.bold))
                .foregroundStyle(color)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.creamBorder, lineWidth: 1))
    }

    // MARK: Waypoints

    @ViewBuilder
    private var waypointsSection: some View {
        if !itinerary.waypoints.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    sectionHeader("Points de passage")
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { waypointsCollapsed.toggle() }
                    } label: {
                        HStack(spacing: 4) {
                            Text("\(itinerary.waypoints.count)").foregroundStyle(AppColors.terra)
                            Text(waypointsCollapsed ? "Afficher" : "Réduire")
                            Image(systemName: waypointsCollapsed ? "chevron.down" : "chevron.up").font(.system(size: 9))
                        }
                        .font(.system(size: 11).weight(.semibold))
                        .foregroundStyle(AppColors.inkMid)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)

                if waypointsCollapsed {
                    Text("\(itinerary.waypoints.first?.name ?? "")  →  \(itinerary.waypoints.last?.name ?? "")\(itinerary.loop ? "  ↺" : "")")
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.inkMid)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColors.creamBorder, lineWidth: 1))
                        .padding(.horizontal, 16)
                } else {
                VStack(spacing: 0) {
                    ForEach(Array(itinerary.waypoints.enumerated()), id: \.element.id) { index, wp in
                        HStack(spacing: 10) {
                            Text("\(index + 1)")
                                .font(.system(.caption, design: .serif).weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 24, height: 24)
                                .background(AppColors.terra, in: Circle())
                            VStack(alignment: .leading, spacing: 1) {
                                Text(wp.name)
                                    .font(.system(size: 14).weight(.semibold))
                                    .foregroundStyle(AppColors.ink)
                                    .lineLimit(1)
                                if let label = wp.label, label != wp.name {
                                    Text(label).font(.system(size: 11)).foregroundStyle(AppColors.inkLight).lineLimit(1)
                                } else if let postal = wp.postal {
                                    Text(postal).font(.system(size: 11)).foregroundStyle(AppColors.inkLight)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 9)
                        if index < itinerary.waypoints.count - 1 {
                            Divider().overlay(AppColors.creamBorder)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColors.creamBorder, lineWidth: 1))
                .padding(.horizontal, 16)
                }
            }
        }
    }

    // MARK: Way types + surfaces

    @ViewBuilder
    private var waysSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let a = analysis, !a.wayTypes.isEmpty {
                breakdown(title: "Types de voies", buckets: a.wayTypes)
            }
            if let a = analysis, !a.surfaces.isEmpty {
                breakdown(title: "Surfaces", buckets: a.surfaces)
            }
            if analysisLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Analyse des voies et surfaces…")
                        .font(.system(size: 12)).foregroundStyle(AppColors.inkLight)
                }
                .padding(.horizontal, 16)
            } else if analysisFailed || (analysis != nil && analysis!.wayTypes.isEmpty && analysis!.surfaces.isEmpty) {
                Text("Analyse des voies indisponible.")
                    .font(.system(size: 12)).foregroundStyle(AppColors.inkLight)
                    .padding(.horizontal, 16)
            }
        }
    }

    private func breakdown(title: String, buckets: [APIClient.RouteAnalysis.Bucket]) -> some View {
        let total = max(1, buckets.reduce(0) { $0 + $1.meters })
        return VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title).padding(.horizontal, 16)

            // Stacked proportional bar.
            GeometryReader { geo in
                HStack(spacing: 1) {
                    ForEach(buckets) { b in
                        Rectangle()
                            .fill(bucketColor(b.key))
                            .frame(width: max(2, geo.size.width * CGFloat(b.meters) / CGFloat(total)))
                    }
                }
            }
            .frame(height: 12)
            .clipShape(Capsule())
            .padding(.horizontal, 16)

            // Legend.
            VStack(spacing: 0) {
                ForEach(Array(buckets.enumerated()), id: \.element.id) { index, b in
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(bucketColor(b.key))
                            .frame(width: 16, height: 16)
                        Text(b.label)
                            .font(.system(size: 14).weight(.medium))
                            .foregroundStyle(AppColors.ink)
                        Spacer(minLength: 8)
                        Text(formatMeters(b.meters))
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(AppColors.inkMid)
                    }
                    .padding(.vertical, 9)
                    if index < buckets.count - 1 {
                        Divider().overlay(AppColors.creamBorder)
                    }
                }
            }
            .padding(.horizontal, 14)
            .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColors.creamBorder, lineWidth: 1))
            .padding(.horizontal, 16)
        }
    }

    private func bucketColor(_ key: String) -> Color {
        switch key {
        case "route":           return Color(red: 0.60, green: 0.67, blue: 0.74)
        case "rue":             return Color(red: 0.77, green: 0.81, blue: 0.85)
        case "piste_cyclable":  return Color(red: 0.31, green: 0.64, blue: 0.58)
        case "route_nationale": return Color(red: 0.89, green: 0.70, blue: 0.24)
        case "chemin":          return Color(red: 0.84, green: 0.86, blue: 0.89)
        case "asphalte":        return Color(red: 0.60, green: 0.67, blue: 0.74)
        case "revetu":          return Color(red: 0.91, green: 0.91, blue: 0.91)
        case "non_pave":        return Color(red: 0.81, green: 0.77, blue: 0.66)
        default:                return Color(red: 0.20, green: 0.20, blue: 0.20)  // inconnu
        }
    }

    private func formatMeters(_ m: Int) -> String {
        if m >= 1000 {
            let km = Double(m) / 1000
            return String(format: "%.1f km", km).replacingOccurrences(of: ".", with: ",")
        }
        return "\(m) m"
    }

    private func loadAnalysis() async {
        guard analysis == nil, !analysisLoading else { return }
        let haveGeom = (itinerary.geometry?.count ?? 0) >= 2
        guard haveGeom || itinerary.waypoints.count >= 2 else { return }
        analysisLoading = true
        analysisFailed = false
        defer { analysisLoading = false }
        do {
            // Sample waypoints ALONG the stored geometry (capped at OSRM's
            // 25-point limit) so route-ways re-routes a path that follows the
            // actual route — essential for imported GPX and loops, where the
            // stored waypoints are only start/end (or a single point). Fall
            // back to the raw waypoints when there's no geometry.
            let pts: [Coordinate]
            if let geom = itinerary.geometry, geom.count >= 2 {
                pts = GeoMath.downsampleByDistance(geom, n: min(24, geom.count)).points
            } else {
                var wp = itinerary.waypoints.map(\.coordinate)
                if itinerary.loop, wp.count >= 2 { wp.append(wp[0]) }
                pts = wp
            }
            guard pts.count >= 2 else { return }
            let result = try await environment.api.routeWays(waypoints: pts)
            await MainActor.run { analysis = result }
        } catch {
            await MainActor.run { analysisFailed = true }
        }
    }

    // MARK: Action bar

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button {
                onLoad()
                dismiss()
            } label: {
                Label("Charger", systemImage: "square.and.pencil")
                    .font(.system(size: 14).weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(AppColors.creamDark, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColors.creamBorder, lineWidth: 1))
                    .foregroundStyle(AppColors.inkMid)
            }
            .buttonStyle(.plain)

            Button {
                onNavigate()
                dismiss()
            } label: {
                Label("Naviguer", systemImage: "location.north.line.fill")
                    .font(.system(size: 14).weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(AppColors.terra, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled((itinerary.geometry?.count ?? 0) < 2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    // MARK: Helpers

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10).weight(.bold)).tracking(1.2)
            .foregroundStyle(AppColors.terra)
    }

    private func formatDur(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        return h > 0 ? "\(h)h\(String(format: "%02d", m))" : "\(m) min"
    }

    // MARK: Derived data

    private var cleanElevations: [Double] {
        GeoMath.sanitizeElevations(itinerary.elevations ?? [])
    }

    private var samples: [ElevationSample] {
        guard
            let geometry = itinerary.geometry,
            let indices = itinerary.elevSampleIndices,
            !cleanElevations.isEmpty
        else { return [] }
        let base = GeoMath.elevationSeries(polyline: geometry, sampleIndices: indices, elevations: cleanElevations)
            .map { ElevationSample(km: $0.km, elevation: $0.ele) }
        return resampleEvery100m(base)
    }

    /// Linear-interpolate the profile onto a 100 m grid so scrubbing reads a
    /// value roughly every 100 m, regardless of how densely the route was
    /// stored. Capped so very long routes stay light.
    private func resampleEvery100m(_ base: [ElevationSample]) -> [ElevationSample] {
        guard base.count >= 2, let total = base.last?.km, total > 0.1 else { return base }
        let step = 0.1
        let count = min(1200, Int(total / step) + 1)
        var out: [ElevationSample] = []
        out.reserveCapacity(count)
        var j = 0
        for i in 0..<count {
            let k = min(total, Double(i) * step)
            while j < base.count - 2 && base[j + 1].km < k { j += 1 }
            let a = base[j]
            let b = base[min(j + 1, base.count - 1)]
            let t = b.km > a.km ? (k - a.km) / (b.km - a.km) : 0
            out.append(ElevationSample(km: k, elevation: a.elevation + (b.elevation - a.elevation) * t))
        }
        return out
    }

    private var ascent: Int { GeoMath.ascentDescent(cleanElevations).ascent }
    private var descent: Int { GeoMath.ascentDescent(cleanElevations).descent }
    private var highest: Int? { cleanElevations.max().map { Int($0.rounded()) } }
    private var lowest: Int? { cleanElevations.min().map { Int($0.rounded()) } }

    private var avgSpeed: Double? {
        guard let km = itinerary.distanceKm, let min = itinerary.durationMin, min > 0 else { return nil }
        return km / (Double(min) / 60)
    }

    private var subtitle: String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "fr_FR")
        fmt.dateFormat = "d MMMM yyyy"
        let date = fmt.string(from: itinerary.createdAt)
        if let place = itinerary.waypoints.first?.city ?? itinerary.waypoints.first?.name {
            return "\(date) · \(place)"
        }
        return date
    }

    private struct DifficultyTag { let label: String; let color: Color }
    private var diff: DifficultyTag {
        let dist = itinerary.distanceKm ?? 0
        let asc = Double(itinerary.totalAscent ?? ascent)
        let effort = dist + asc / 8
        if effort < 50 { return DifficultyTag(label: "Facile", color: AppColors.green) }
        if effort < 150 { return DifficultyTag(label: "Modéré", color: AppColors.terra) }
        return DifficultyTag(label: "Difficile", color: Color(red: 0.61, green: 0.23, blue: 0.10))
    }
}
