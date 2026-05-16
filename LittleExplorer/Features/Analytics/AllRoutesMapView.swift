import MapKit
import SwiftUI

/// All activity polylines overlaid on a single map. Colour-coded per
/// sport, with a sport picker at the top to filter to one discipline
/// at a time. Camera auto-centres on the centroid of each filtered
/// activity's *start* point — so when you pick "Vélo", you land on
/// the neighbourhood where you actually leave from (e.g. Dardilly)
/// instead of zoomed out to fit every kilometre ever ridden.
struct AllRoutesMapView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var selectedSport: Sport = .cycling
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 45.81, longitude: 4.75), // Dardilly fallback
            span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12),
        ),
    )

    var body: some View {
        let withGps = environment.activityStore.activities.filter { !$0.gps.isEmpty }
        let availableSports = withGps.availableSports
        let filtered = withGps.filter { Sport(backendType: $0.type) == selectedSport }

        ZStack(alignment: .topTrailing) {
            map(activities: filtered)
            VStack(alignment: .leading, spacing: 10) {
                if availableSports.count > 1 {
                    SportFilterBar(sport: $selectedSport, available: availableSports)
                }
                legend(activities: filtered)
            }
            .padding(12)
        }
        .background(AppColors.cream)
        .navigationTitle("Carte des parcours")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !availableSports.contains(selectedSport), let first = availableSports.first {
                selectedSport = first
            }
            recenter(activities: filtered)
        }
        .onChange(of: selectedSport) { _, _ in
            let nextFiltered = withGps.filter { Sport(backendType: $0.type) == selectedSport }
            recenter(activities: nextFiltered)
        }
    }

    // MARK: - Map

    private func map(activities: [RideRecord]) -> some View {
        Map(position: $cameraPosition) {
            ForEach(activities) { activity in
                let sport = Sport(backendType: activity.type) ?? selectedSport
                MapPolyline(coordinates: activity.gps.map(\.clLocation))
                    .stroke(sport.color.opacity(0.55), lineWidth: 2.5)
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
    }

    // MARK: - Legend

    private func legend(activities: [RideRecord]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Rectangle().fill(selectedSport.color).frame(width: 18, height: 3)
                Text(selectedSport.displayName)
                    .font(.system(size: 11).weight(.semibold))
                    .foregroundStyle(AppColors.inkMid)
                Spacer(minLength: 8)
                Text("\(activities.count)")
                    .font(.system(.caption, design: .serif).weight(.bold))
                    .foregroundStyle(AppColors.ink)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: 180, alignment: .leading)
        .background(AppColors.surface.opacity(0.95), in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppColors.creamBorder, lineWidth: 1))
    }

    // MARK: - Camera centering

    /// Centre on the centroid of each ride's first GPS point — i.e.
    /// "where I usually leave from" for the selected sport. Falls back
    /// to a Dardilly-anchored region when there's no data, since
    /// that's Florian's primary departure point for cycling.
    private func recenter(activities: [RideRecord]) {
        let startPoints = activities.compactMap(\.gps.first)
        guard !startPoints.isEmpty else {
            cameraPosition = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 45.81, longitude: 4.75),
                span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12),
            ))
            return
        }
        let lats = startPoints.map(\.lat)
        let lngs = startPoints.map(\.lng)
        let centerLat = lats.reduce(0, +) / Double(lats.count)
        let centerLng = lngs.reduce(0, +) / Double(lngs.count)

        // Span scales to how spread out the start points are, but with
        // a sensible floor (≈ 13 km diameter) so we always show enough
        // context around the start neighbourhood.
        let latSpread = (lats.max()! - lats.min()!) * 1.5
        let lngSpread = (lngs.max()! - lngs.min()!) * 1.5
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.08, latSpread),
            longitudeDelta: max(0.08, lngSpread),
        )
        cameraPosition = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLng),
            span: span,
        ))
    }
}

/// Horizontal sport picker chip bar used on the Carte des parcours
/// page. Reuses the same visual language as the Feed's picker so
/// the two screens feel consistent.
private struct SportFilterBar: View {
    @Binding var sport: Sport
    let available: [Sport]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(available) { option in
                    let isActive = sport == option
                    Button {
                        sport = option
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: option.symbol).font(.system(size: 11))
                            Text(option.displayName)
                                .font(.system(size: 11).weight(isActive ? .bold : .medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(isActive ? option.color : Color.clear),
                        )
                        .foregroundStyle(isActive ? Color.white : AppColors.inkMid)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
        }
        .background(AppColors.surface.opacity(0.95), in: RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(AppColors.creamBorder, lineWidth: 1))
    }
}
