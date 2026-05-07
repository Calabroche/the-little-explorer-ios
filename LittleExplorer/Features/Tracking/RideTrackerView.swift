import MapKit
import SwiftUI

struct RideTrackerView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var tracker: RideTracker?
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)

    var body: some View {
        NavigationStack {
            ZStack {
                map
                VStack {
                    metricsHeader
                    Spacer()
                    controls
                }
                .padding()
            }
            .navigationTitle("Track")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { ensureTracker() }
        }
    }

    private var map: some View {
        Map(position: $cameraPosition) {
            UserAnnotation()
            if let tracker, !tracker.path.isEmpty {
                MapPolyline(coordinates: tracker.path)
                    .stroke(Color.accentColor, lineWidth: 5)
            }
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .ignoresSafeArea(edges: .bottom)
    }

    @ViewBuilder
    private var metricsHeader: some View {
        if let tracker, tracker.phase != .idle {
            HStack(spacing: 12) {
                metric("Time", value: RideFormatter.duration(tracker.elapsed))
                metric("Distance", value: RideFormatter.distance(tracker.distanceMeters))
                metric("Speed", value: RideFormatter.speed(tracker.currentSpeedKmh))
            }
            .padding(12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    @ViewBuilder
    private var controls: some View {
        if let tracker {
            HStack(spacing: 16) {
                switch tracker.phase {
                case .idle:
                    Button {
                        Task { await tracker.start() }
                    } label: {
                        controlLabel("Start ride", systemImage: "record.circle.fill", tint: .red)
                    }
                case .recording:
                    Button { tracker.pause() } label: {
                        controlLabel("Pause", systemImage: "pause.fill", tint: .orange)
                    }
                    Button {
                        Task { await tracker.stop() }
                    } label: {
                        controlLabel("Stop", systemImage: "stop.fill", tint: .gray)
                    }
                case .paused:
                    Button { tracker.resume() } label: {
                        controlLabel("Resume", systemImage: "play.fill", tint: .green)
                    }
                    Button {
                        Task { await tracker.stop() }
                    } label: {
                        controlLabel("Stop", systemImage: "stop.fill", tint: .gray)
                    }
                }
            }
        }
    }

    private func metric(_ label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label.uppercased()).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }

    private func controlLabel(_ title: String, systemImage: String, tint: Color) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(tint, in: Capsule())
            .foregroundStyle(.white)
    }

    private func ensureTracker() {
        guard tracker == nil else { return }
        tracker = RideTracker(
            location: environment.location,
            activityManager: environment.activityManager,
            watch: environment.watch,
        )
    }
}
