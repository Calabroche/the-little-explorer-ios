import MapKit
import SwiftUI

struct RideTrackerView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var tracker: RideTracker?
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var showSportSheet = false
    @State private var showSaveSheet = false
    @State private var saveTitle = ""

    /// Sports surfaced in the picker on Start. Order matches the
    /// labels Florian asked for: vélo / run / ski / trek.
    private let pickableSports: [Sport] = [.cycling, .running, .ski, .hiking]

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
            .sheet(isPresented: $showSportSheet) {
                sportPicker
                    .presentationDetents([.height(380), .medium])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showSaveSheet) {
                saveSheet
                    .presentationDetents([.height(360), .medium])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Map

    private var map: some View {
        Map(position: $cameraPosition) {
            UserAnnotation()
            if let tracker, !tracker.path.isEmpty {
                MapPolyline(coordinates: tracker.path)
                    .stroke(tracker.selectedSport?.color ?? AppColors.terra, lineWidth: 5)
            }
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: - Metrics

    @ViewBuilder
    private var metricsHeader: some View {
        if let tracker, tracker.phase != .idle {
            VStack(spacing: 8) {
                if let sport = tracker.selectedSport {
                    HStack(spacing: 6) {
                        Image(systemName: sport.symbol).font(.system(size: 11))
                        Text(sport.displayName.uppercased())
                            .font(.system(size: 10).weight(.bold)).tracking(1.2)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(sport.color, in: Capsule())
                    .foregroundStyle(.white)
                }
                HStack(spacing: 12) {
                    metric("Time", value: RideFormatter.duration(tracker.elapsed))
                    metric("Distance", value: RideFormatter.distance(tracker.distanceMeters))
                    metric("Speed", value: RideFormatter.speed(tracker.currentSpeedKmh))
                }
            }
            .padding(12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - Controls

    @ViewBuilder
    private var controls: some View {
        if let tracker {
            HStack(spacing: 16) {
                switch tracker.phase {
                case .idle:
                    Button {
                        showSportSheet = true
                    } label: {
                        controlLabel("Start ride", systemImage: "record.circle.fill", tint: .red)
                    }
                case .recording:
                    Button { tracker.pause() } label: {
                        controlLabel("Pause", systemImage: "pause.fill", tint: .orange)
                    }
                    Button {
                        Task { await tracker.stop(); openSaveSheet() }
                    } label: {
                        controlLabel("Stop", systemImage: "stop.fill", tint: .gray)
                    }
                case .paused:
                    Button { tracker.resume() } label: {
                        controlLabel("Resume", systemImage: "play.fill", tint: .green)
                    }
                    Button {
                        Task { await tracker.stop(); openSaveSheet() }
                    } label: {
                        controlLabel("Stop", systemImage: "stop.fill", tint: .gray)
                    }
                case .finished:
                    // Finished phase is transient — sheet is open or
                    // about to open. Keep the bar empty.
                    EmptyView()
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

    // MARK: - Sport picker sheet

    private var sportPicker: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Quel sport ?")
                .font(.system(.title2, design: .serif).weight(.heavy))
                .foregroundStyle(AppColors.ink)
                .padding(.top, 6)

            VStack(spacing: 10) {
                ForEach(pickableSports) { sport in
                    Button {
                        showSportSheet = false
                        Task {
                            await tracker?.start(sport: sport)
                        }
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(sport.color.opacity(0.18))
                                    .frame(width: 42, height: 42)
                                Image(systemName: sport.symbol)
                                    .foregroundStyle(sport.color)
                                    .font(.system(size: 18, weight: .semibold))
                            }
                            Text(sport.displayName)
                                .font(.system(.title3, design: .serif).weight(.bold))
                                .foregroundStyle(AppColors.ink)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12).weight(.semibold))
                                .foregroundStyle(AppColors.inkLight)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.creamBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.cream)
    }

    // MARK: - Save sheet

    private var saveSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Enregistrer cette sortie ?")
                .font(.system(.title2, design: .serif).weight(.heavy))
                .foregroundStyle(AppColors.ink)
                .padding(.top, 6)

            if let tracker {
                summary(tracker: tracker)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("TITRE")
                    .font(.system(size: 9).weight(.semibold)).tracking(1.2)
                    .foregroundStyle(AppColors.inkLight)
                TextField("Sortie vélo · 8 mai 2026", text: $saveTitle)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.creamBorder, lineWidth: 1))
            }

            HStack(spacing: 12) {
                Button(role: .destructive) {
                    discardRide()
                } label: {
                    Text("Supprimer")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AppColors.creamDark, in: Capsule())
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)

                Button {
                    saveRide()
                } label: {
                    Text("Sauver")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AppColors.terra, in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.cream)
    }

    private func summary(tracker: RideTracker) -> some View {
        HStack(spacing: 16) {
            stat(label: "DURÉE", value: RideFormatter.duration(tracker.elapsed))
            stat(label: "DISTANCE", value: String(format: "%.2f km", tracker.distanceMeters / 1000))
            stat(label: "DÉNIVELÉ", value: "\(Int(tracker.elevationGainM)) m")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.creamBorder, lineWidth: 1))
    }

    private func stat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 9).weight(.semibold)).tracking(1.2).foregroundStyle(AppColors.inkLight)
            Text(value).font(.system(.title3, design: .serif).weight(.bold)).foregroundStyle(AppColors.ink).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Actions

    private func openSaveSheet() {
        guard let tracker, tracker.phase == .finished else { return }
        saveTitle = ""
        showSaveSheet = true
    }

    private func saveRide() {
        guard let tracker else { return }
        let trimmed = saveTitle.trimmingCharacters(in: .whitespaces)
        if let record = tracker.commitRecord(title: trimmed.isEmpty ? nil : trimmed) {
            environment.localRides.add(record, for: environment.currentUser)
            environment.activityStore.refreshLocal(user: environment.currentUser)
            environment.saveRideToHealthKitIfEnabled(record)
        }
        tracker.reset()
        showSaveSheet = false
        saveTitle = ""
    }

    private func discardRide() {
        tracker?.reset()
        showSaveSheet = false
        saveTitle = ""
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
