import MapKit
import SwiftUI

struct RideTrackerView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var tracker: RideTracker?
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var showSportSheet = false
    @State private var showSaveSheet = false
    @State private var saveTitle = ""

    var body: some View {
        NavigationStack {
            ZStack {
                // Sport-conditional canvas: outdoor → live map, indoor
                // → flat cream + big metrics. We don't even show the
                // map for a yoga session because the GPS dot would
                // just sit there.
                if let tracker, tracker.phase != .idle {
                    if tracker.isIndoor {
                        indoorCanvas
                    } else {
                        map
                    }
                } else {
                    // Idle state — neither map nor indoor. Cream
                    // background with a "tap Start" prompt.
                    idleCanvas
                }

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
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showSaveSheet) {
                saveSheet
                    .presentationDetents([.height(380), .medium])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Canvases

    private var idleCanvas: some View {
        ZStack {
            AppColors.cream.ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "stopwatch")
                    .font(.system(size: 56))
                    .foregroundStyle(AppColors.terra.opacity(0.85))
                Text("Choisis un sport")
                    .font(.system(.title2, design: .serif).weight(.heavy))
                    .foregroundStyle(AppColors.ink)
                Text("Vélo, course, ski, salle… Tap Start pour ouvrir la liste.")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.inkMid)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
    }

    private var indoorCanvas: some View {
        let sub = tracker?.selectedSubtype
        return ZStack {
            (sub?.color ?? AppColors.terra).opacity(0.12).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: sub?.symbol ?? "dumbbell.fill")
                    .font(.system(size: 88))
                    .foregroundStyle(sub?.color ?? AppColors.terra)
                Text(sub?.displayName ?? "Séance en salle")
                    .font(.system(.largeTitle, design: .serif).weight(.heavy))
                    .foregroundStyle(AppColors.ink)
                Text("Séance indoor — pas de GPS. Tes métriques apparaissent en haut.")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.inkMid)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
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
                if let subtype = tracker.selectedSubtype {
                    HStack(spacing: 6) {
                        Image(systemName: subtype.symbol).font(.system(size: 11))
                        Text(subtype.displayName.uppercased())
                            .font(.system(size: 10).weight(.bold)).tracking(1.2)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(subtype.color, in: Capsule())
                    .foregroundStyle(.white)
                }
                if tracker.isIndoor {
                    // Indoor: time + calories estimate. No distance /
                    // speed (no GPS).
                    HStack(spacing: 12) {
                        metric("Time", value: RideFormatter.duration(tracker.elapsed))
                        metric("Kcal", value: indoorCalories(tracker: tracker))
                    }
                } else {
                    HStack(spacing: 12) {
                        metric("Time", value: RideFormatter.duration(tracker.elapsed))
                        metric("Distance", value: RideFormatter.distance(tracker.distanceMeters))
                        metric("Speed", value: RideFormatter.speed(tracker.currentSpeedKmh))
                    }
                }
            }
            .padding(12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    /// Live MET-based calorie estimate for indoor sessions. Updates
    /// once a second as `tracker.elapsed` ticks.
    private func indoorCalories(tracker: RideTracker) -> String {
        let met = tracker.selectedSubtype?.metEquivalent ?? 5
        let weight = environment.session.profile?.effective.riderKg ?? 70
        let hours = tracker.elapsed / 3600
        let kcal = met * weight * hours
        return "\(Int(kcal.rounded()))"
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

    // MARK: - Sport picker sheet — categorized

    private var sportPicker: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Quel sport ?")
                        .font(.system(.largeTitle, design: .serif).weight(.heavy))
                        .foregroundStyle(AppColors.ink)
                        .padding(.top, 4)

                    ForEach(SportCategory.allCases) { category in
                        categorySection(category)
                    }
                }
                .padding(20)
            }
            .background(AppColors.cream)
        }
    }

    private func categorySection(_ category: SportCategory) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: category.symbol)
                    .font(.system(size: 12).weight(.bold))
                    .foregroundStyle(AppColors.terra)
                Text(category.displayName.uppercased())
                    .font(.system(size: 11).weight(.bold))
                    .tracking(1.5)
                    .foregroundStyle(AppColors.terra)
                Rectangle().fill(AppColors.creamBorder).frame(height: 1)
            }
            ForEach(category.subtypes) { subtype in
                subtypeRow(subtype)
            }
        }
    }

    private func subtypeRow(_ subtype: SportSubtype) -> some View {
        Button {
            showSportSheet = false
            Task { await tracker?.start(subtype: subtype) }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(subtype.color.opacity(0.18))
                        .frame(width: 40, height: 40)
                    Image(systemName: subtype.symbol)
                        .foregroundStyle(subtype.color)
                        .font(.system(size: 17, weight: .semibold))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(subtype.displayName)
                        .font(.system(.body, design: .serif).weight(.bold))
                        .foregroundStyle(AppColors.ink)
                    Text(subtype.isOutdoor ? "GPS + carte" : "Indoor — métriques seules")
                        .font(.system(size: 10))
                        .foregroundStyle(AppColors.inkLight)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11).weight(.semibold))
                    .foregroundStyle(AppColors.inkLight)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColors.creamBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
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
