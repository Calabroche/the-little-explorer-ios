import MapKit
import SwiftUI

/// All activity polylines overlaid on a single map. Colour-coded by
/// sport. Tap a route to surface its summary; the legend in the corner
/// counts activities per sport. Mirrors the web's MapPage but shows
/// every ride at once instead of one selected.
struct AllRoutesMapView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var selected: RideRecord?
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 45.75, longitude: 4.85),
            span: MKCoordinateSpan(latitudeDelta: 0.6, longitudeDelta: 0.6),
        ),
    )

    var body: some View {
        let activities = environment.activityStore.activities.filter { !$0.gps.isEmpty }
        ZStack(alignment: .topTrailing) {
            map(activities: activities)
            legend(activities: activities)
                .padding(12)
        }
        .background(AppColors.cream)
        .navigationTitle("Carte des parcours")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { recenter(activities: activities) }
        .sheet(item: $selected) { activity in
            NavigationStack { ActivityDetailView(activity: activity) }
        }
    }

    private func map(activities: [RideRecord]) -> some View {
        Map(position: $cameraPosition) {
            ForEach(activities) { activity in
                let sport = Sport(backendType: activity.type) ?? .cycling
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

    private func legend(activities: [RideRecord]) -> some View {
        let counts: [Sport: Int] = activities.reduce(into: [:]) { acc, a in
            if let s = Sport(backendType: a.type) { acc[s, default: 0] += 1 }
        }
        let sorted = counts.sorted(by: { $0.value > $1.value })
        return VStack(alignment: .leading, spacing: 8) {
            Text("LÉGENDE")
                .font(.system(size: 9).weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(AppColors.inkLight)
            ForEach(sorted, id: \.key) { sport, count in
                HStack(spacing: 8) {
                    Rectangle().fill(sport.color).frame(width: 18, height: 3)
                    Text(sport.displayName)
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.inkMid)
                    Spacer(minLength: 8)
                    Text("\(count)")
                        .font(.system(.caption, design: .serif).weight(.bold))
                        .foregroundStyle(AppColors.ink)
                        .monospacedDigit()
                }
            }
        }
        .padding(12)
        .frame(maxWidth: 200, alignment: .leading)
        .background(AppColors.surface.opacity(0.95), in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppColors.creamBorder, lineWidth: 1))
    }

    private func recenter(activities: [RideRecord]) {
        let coords = activities.flatMap(\.gps)
        guard !coords.isEmpty else { return }
        let lats = coords.map(\.lat)
        let lngs = coords.map(\.lng)
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
}
