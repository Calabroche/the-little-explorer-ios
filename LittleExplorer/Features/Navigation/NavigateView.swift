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
    /// Start framed on the whole route. As soon as the first GPS fix
    /// arrives we switch to a tilted follow-camera (see .onChange below).
    @State private var cameraPosition: MapCameraPosition = .automatic
    /// Cached heading — used so the camera stays oriented even when
    /// CLLocation.course briefly returns -1 (invalid) between fixes.
    @State private var lastValidHeading: CLLocationDirection = 0
    /// True when the user has tapped X — we keep the view alive to
    /// show the save dialog.
    @State private var showSaveDialog: Bool = false

    var body: some View {
        ZStack {
            map.ignoresSafeArea()
            VStack(spacing: 0) {
                topBanner
                Spacer()
                bottomBar
            }
            // Close button anchored inside the view (no nav bar — we
            // run as a fullScreenCover with all chrome hidden).
            VStack {
                HStack {
                    Button {
                        attemptDismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white, Color.black.opacity(0.6))
                    }
                    .padding(.leading, 16)
                    .padding(.top, 6)
                    Spacer()
                }
                Spacer()
            }
        }
        .statusBarHidden(false)
        .task {
            let manager = NavigateState(
                api: environment.api,
                location: environment.location,
                activityManager: environment.activityManager,
            )
            state = manager
            await manager.start(itinerary: itinerary)
        }
        .onChange(of: state?.userLocation?.timestamp) { _, _ in
            guard let loc = state?.userLocation else { return }
            recenterCamera(on: loc)
        }
        .onDisappear { state?.stop() }
        .confirmationDialog(
            "Enregistrer cette sortie ?",
            isPresented: $showSaveDialog,
            titleVisibility: .visible,
        ) {
            Button("Sauvegarder dans Petit Explorer") {
                saveAndDismiss()
            }
            Button("Sauvegarder + envoyer sur Strava (bientôt)") {
                saveAndDismiss()
            }
            .disabled(true)
            Button("Ignorer cette sortie", role: .destructive) {
                state?.stop()
                dismiss()
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            if let state {
                Text("\(String(format: "%.2f", state.distanceTraveledM / 1000)) km · \(Int(state.elapsedSec / 60)) min · \(Int(state.elevationGainM)) m D+")
            } else {
                Text("")
            }
        }
    }

    private func attemptDismiss() {
        // Always show the dialog when the user exits — even if they
        // barely moved. The "Ignorer cette sortie" option is there
        // exactly for that case, and forcing the prompt removes the
        // "where's my save dialog?" surprise the user reported.
        showSaveDialog = true
    }

    private func saveAndDismiss() {
        guard let state else { dismiss(); return }
        let sport = environment.selectedSport
        if let record = state.commitRecord(sport: sport, title: itinerary.name) {
            environment.localRides.add(record, for: environment.currentUser)
            environment.activityStore.refreshLocal(user: environment.currentUser)
            Log.nav.notice("ride saved: \(String(format: "%.2f", record.distance ?? 0), privacy: .public) km")
        }
        state.stop()
        dismiss()
    }

    private var map: some View {
        Map(position: $cameraPosition) {
            UserAnnotation()
            if let route = state?.route, !route.geometry.isEmpty {
                // Apple-Maps-style polyline: bold systemBlue stroke
                // with a slightly darker outline for contrast on
                // light terrain. Drawing twice (stroke then thinner
                // overlay) gives the layered look Apple uses.
                MapPolyline(coordinates: route.geometry.map(\.clLocation))
                    .stroke(Color.black.opacity(0.35), lineWidth: 11)
                MapPolyline(coordinates: route.geometry.map(\.clLocation))
                    .stroke(Color.blue, lineWidth: 8)
            }
            ForEach(Array(itinerary.waypoints.enumerated()), id: \.offset) { index, waypoint in
                Marker("\(index + 1)", coordinate: waypoint.coordinate.clLocation)
                    .tint(AppColors.green)
            }
        }
        // Realistic 3D buildings + clean POI rendering to match the
        // Apple Maps navigation experience the user pointed to. POIs
        // are excluded so the route stays the visual focus.
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapPitchToggle()
        }
    }

    /// Reposition the camera as a tilted follow-cam. Uses the user's
    /// current course as the camera heading (so the route ahead is
    /// always pointing "up"). Distance 250 m + pitch 55° matches
    /// Apple Maps' default driving camera.
    private func recenterCamera(on loc: CLLocation) {
        let heading: CLLocationDirection
        if loc.course >= 0 {
            heading = loc.course
            lastValidHeading = loc.course
        } else {
            heading = lastValidHeading
        }
        withAnimation(.linear(duration: 0.8)) {
            cameraPosition = .camera(MapCamera(
                centerCoordinate: loc.coordinate,
                distance: 250,
                heading: heading,
                pitch: 55,
            ))
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
            VStack(spacing: 10) {
                HStack(spacing: 0) {
                    stat(label: "DISTANCE", value: formatKm(state.distanceTraveledM), color: AppColors.terra)
                    stat(label: "VITESSE", value: String(format: "%.1f", state.currentSpeedKmh), unit: "km/h", color: .white)
                    stat(label: "MOYENNE", value: String(format: "%.1f", state.avgSpeedKmh), unit: "km/h", color: .white)
                    stat(label: "D+", value: "\(Int(state.elevationGainM))", unit: "m", color: AppColors.green)
                }

                HStack(spacing: 12) {
                    Label(formatDistance(state.distanceRemaining), systemImage: "flag.checkered")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                    if state.offRoute {
                        Label("Hors route", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 8).padding(.vertical, 4)
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
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.black.opacity(0.75))
        }
    }

    private func formatKm(_ meters: Double) -> String {
        String(format: "%.2f km", meters / 1000)
    }

    private func stat(label: String, value: String, unit: String = "", color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8).weight(.bold))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.7))
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(.title3, design: .serif).weight(.bold))
                    .foregroundStyle(color)
                    .monospacedDigit()
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formatDistance(_ meters: Double) -> String {
        meters >= 1000 ? String(format: "%.1f km", meters / 1000) : "\(Int(meters)) m"
    }
}
