import MapKit
import SwiftUI

/// Turn-by-turn cycling navigation. Receives a route (with steps) and
/// surfaces the next maneuver. Stub for v0 — wired up to the planner once
/// the planning UX produces a route with `steps:true`.
struct CyclingNavigationView: View {
    let route: BikeRoute
    @State private var currentStepIndex: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            map
            stepBanner
        }
    }

    private var map: some View {
        Map {
            MapPolyline(coordinates: route.geometry.map(\.clLocation))
                .stroke(Color.accentColor, lineWidth: 5)
            UserAnnotation()
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
    }

    @ViewBuilder
    private var stepBanner: some View {
        if let steps = route.steps, currentStepIndex < steps.count {
            let step = steps[currentStepIndex]
            HStack(spacing: 14) {
                Image(systemName: step.maneuverSymbol)
                    .font(.title)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(step.name.isEmpty ? "Continue" : step.name)
                        .font(.headline)
                    Text(RideFormatter.distance(step.distance))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
            .background(.thinMaterial)
        }
    }
}
