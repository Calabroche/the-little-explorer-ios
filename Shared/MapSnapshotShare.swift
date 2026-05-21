import Foundation
#if os(iOS)
import UIKit
import MapKit
#endif

/// Shared filesystem location for the lock-screen Live Activity map
/// snapshot. The main app generates a JPEG of the navigation route via
/// `MKMapSnapshotter` and drops it here; the widget extension reads it
/// back as a `UIImage` and renders it as the background of the lock
/// screen banner.
///
/// We use App Groups because the Live Activity ContentState payload is
/// capped at ~4 KB by the system, which is far too small to ship a
/// real map image. The shared container has no such limit.
enum MapSnapshotShare {
    static let appGroup = "group.com.calabrese.little-explorer-ios"
    static let filename = "nav-route-snapshot.jpg"

    /// URL to the snapshot file inside the App Group container.
    /// Nil when the entitlement isn't configured (e.g., unsigned
    /// simulator build without the App Group capability).
    static var snapshotURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(filename)
    }

    #if os(iOS)
    /// Render a static map image covering the given route polyline +
    /// padding around it, and save it to the shared container so the
    /// widget can pick it up. Returns true if the snapshot was written.
    @MainActor
    static func generate(polyline coords: [CLLocationCoordinate2D], size: CGSize = CGSize(width: 600, height: 600)) async -> Bool {
        guard !coords.isEmpty, let url = snapshotURL else { return false }

        let lats = coords.map(\.latitude)
        let lngs = coords.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLng = lngs.min(), let maxLng = lngs.max() else {
            return false
        }
        let center = CLLocationCoordinate2D(
            latitude:  (minLat + maxLat) / 2,
            longitude: (minLng + maxLng) / 2,
        )
        // 30% padding around the polyline bounds so the route isn't
        // glued to the edges of the image.
        let span = MKCoordinateSpan(
            latitudeDelta:  max(0.001, (maxLat - minLat) * 1.3),
            longitudeDelta: max(0.001, (maxLng - minLng) * 1.3),
        )

        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: center, span: span)
        options.size = size
        options.scale = UIScreen.main.scale
        options.mapType = .standard
        options.showsBuildings = false

        let snapshotter = MKMapSnapshotter(options: options)
        do {
            let snapshot = try await snapshotter.start()
            // Draw the route polyline on top of the base map snapshot.
            let renderer = UIGraphicsImageRenderer(size: snapshot.image.size)
            let final = renderer.image { ctx in
                snapshot.image.draw(at: .zero)
                ctx.cgContext.setStrokeColor(UIColor.systemBlue.cgColor)
                ctx.cgContext.setLineWidth(6)
                ctx.cgContext.setLineCap(.round)
                ctx.cgContext.setLineJoin(.round)
                var started = false
                for coord in coords {
                    let p = snapshot.point(for: coord)
                    if !started { ctx.cgContext.move(to: p); started = true }
                    else { ctx.cgContext.addLine(to: p) }
                }
                ctx.cgContext.strokePath()
            }
            if let data = final.jpegData(compressionQuality: 0.55) {
                try data.write(to: url, options: .atomic)
                return true
            }
        } catch {
            return false
        }
        return false
    }
    #endif
}
