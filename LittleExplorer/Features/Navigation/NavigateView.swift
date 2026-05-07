import MapKit
import SwiftUI

/// Full-screen turn-by-turn navigation. Locks the screen on, projects
/// GPS onto the route polyline, surfaces the next maneuver banner, and
/// fires voice prompts via AVSpeechSynthesizer at distance thresholds.
struct NavigateView: View {
    let itinerary: Itinerary
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var state: NavigateState?
    @State private var cameraPosition: MapCameraPosition = .userLocation(
        followsHeading: true,
        fallback: .automatic,
    )

    var body: some View {
        ZStack {
            map.ignoresSafeArea()
            VStack(spacing: 0) {
                topBanner
                Spacer()
                bottomBar
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    state?.stop()
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .background(Color.black.opacity(0.3), in: Circle())
                }
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            let manager = NavigateState(api: environment.api, location: environment.location)
            state = manager
            await manager.start(itinerary: itinerary)
        }
        .onDisappear { state?.stop() }
    }

    private var map: some View {
        Map(position: $cameraPosition) {
            UserAnnotation()
            if let route = state?.route, !route.geometry.isEmpty {
                MapPolyline(coordinates: route.geometry.map(\.clLocation))
                    .stroke(AppColors.terra, lineWidth: 6)
            }
            ForEach(Array(itinerary.waypoints.enumerated()), id: \.offset) { index, waypoint in
                Marker("\(index + 1)", coordinate: waypoint.coordinate.clLocation)
                    .tint(AppColors.green)
            }
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
    }

    @ViewBuilder
    private var topBanner: some View {
        if let state, let route = state.route, let steps = route.steps,
           steps.indices.contains(state.currentStepIndex) {
            let step = steps[state.currentStepIndex]
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    Circle().fill(AppColors.terra)
                        .frame(width: 56, height: 56)
                    Text(ManeuverFormatter.arrow(for: step))
                        .font(.system(size: 28))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(ManeuverFormatter.distanceText(state.distanceToNextStep))
                        .font(.system(.title3, design: .serif).weight(.heavy))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                    Text(ManeuverFormatter.core(step))
                        .font(.system(size: 15).weight(.semibold))
                        .foregroundStyle(.white)
                    if !step.name.isEmpty {
                        Text("sur \(step.name)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.black.opacity(0.7))
            .background(.ultraThinMaterial.opacity(0.9))
        } else if case .loading = state?.phase ?? .loading {
            HStack {
                ProgressView().tint(.white)
                Text("Chargement de l'itinéraire…")
                    .foregroundStyle(.white)
                    .font(.caption)
                Spacer()
            }
            .padding()
            .background(Color.black.opacity(0.6))
        } else if case .failed(let message) = state?.phase ?? .loading {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.white)
                Text(message).foregroundStyle(.white).font(.caption)
                Spacer()
            }
            .padding()
            .background(Color.red.opacity(0.7))
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        if let state {
            HStack(spacing: 16) {
                stat(label: "RESTANT", value: formatDistance(state.distanceRemaining), color: AppColors.terra)
                Spacer()
                if state.offRoute {
                    Label("Hors route", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                        .padding(8)
                        .background(.white.opacity(0.85), in: Capsule())
                }
                Spacer()
                if case .finished = state.phase {
                    Button("Terminer") {
                        state.stop()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.black.opacity(0.7))
        }
    }

    private func stat(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9).weight(.semibold))
                .tracking(1.0)
                .foregroundStyle(.white.opacity(0.7))
            Text(value)
                .font(.system(.title3, design: .serif).weight(.bold))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
    }

    private func formatDistance(_ meters: Double) -> String {
        meters >= 1000 ? String(format: "%.1f km", meters / 1000) : "\(Int(meters)) m"
    }
}
