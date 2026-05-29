import SwiftUI
import MapKit
import CoreLocation

/// Active-ride map view on the Apple Watch.
///
/// Shows the planned itinerary as a terra polyline + the rider's
/// current position as the system UserAnnotation. Camera follows the
/// user automatically; if no GPS fix has arrived yet, we fall back to
/// fitting the planned route's bounding box so the user at least sees
/// where they're heading.
///
/// Rendered as the second page of the in-ride TabView when an
/// itinerary is attached to the workout. The first page stays the
/// scrollable metrics + Pause/End controls.
struct ItineraryMapView: View {
    let itinerary: Itinerary
    let currentCoordinate: CLLocationCoordinate2D?

    @State private var cameraPosition: MapCameraPosition

    init(itinerary: Itinerary, currentCoordinate: CLLocationCoordinate2D?) {
        self.itinerary = itinerary
        self.currentCoordinate = currentCoordinate
        // Initial framing: prefer rider location if we already have a
        // fix; otherwise fit the planned route bounds so the user
        // sees the whole journey before GPS warms up.
        if let here = currentCoordinate {
            _cameraPosition = State(initialValue: .region(
                MKCoordinateRegion(
                    center: here,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01),
                ),
            ))
        } else if let region = Self.regionFitting(itinerary.geometry ?? []) {
            _cameraPosition = State(initialValue: .region(region))
        } else {
            _cameraPosition = State(initialValue: .automatic)
        }
    }

    var body: some View {
        Map(position: $cameraPosition) {
            // Planned route in terra (matches the iOS feed colour for
            // cycling). Drawn first so the user dot overlays on top.
            if let geometry = itinerary.geometry, geometry.count > 1 {
                MapPolyline(coordinates: geometry.map {
                    CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng)
                })
                .stroke(.orange, lineWidth: 4)
            }

            // System-rendered "you are here" pulse.
            UserAnnotation()
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .onChange(of: currentCoordinate?.latitude) { _, _ in
            // Re-center on the rider every time a new fix lands.
            // Smooth animation via SwiftUI's implicit Map transitions.
            if let here = currentCoordinate {
                withAnimation(.easeInOut(duration: 0.6)) {
                    cameraPosition = .region(MKCoordinateRegion(
                        center: here,
                        span: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006),
                    ))
                }
            }
        }
    }

    /// Build a MapKit region that contains every coordinate in the
    /// itinerary geometry, padded out by 25 % so the polyline doesn't
    /// hug the screen edge.
    private static func regionFitting(_ coords: [Coordinate]) -> MKCoordinateRegion? {
        guard !coords.isEmpty else { return nil }
        let lats = coords.map(\.lat)
        let lngs = coords.map(\.lng)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLng = lngs.min(), let maxLng = lngs.max() else { return nil }
        let center = CLLocationCoordinate2D(
            latitude:  (minLat + maxLat) / 2,
            longitude: (minLng + maxLng) / 2,
        )
        let span = MKCoordinateSpan(
            latitudeDelta:  max(0.005, (maxLat - minLat) * 1.25),
            longitudeDelta: max(0.005, (maxLng - minLng) * 1.25),
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}
