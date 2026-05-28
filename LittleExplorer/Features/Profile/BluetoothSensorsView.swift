import SwiftUI

/// Pairing UI for Bluetooth Smart heart-rate sensors. Triggered from
/// Settings → "Capteurs Bluetooth". Workflow:
///
///   1. Open → permission prompt fires if not granted
///   2. Scan starts automatically — list populates as sensors are
///      discovered, sorted by RSSI (strongest first)
///   3. Tap a row → connect → state moves to .connected
///   4. Live BPM displayed at the bottom once subscribed
///   5. Optional Battery row if the sensor exposes it
///
/// The shared HeartRateMonitor lives on AppEnvironment so the live
/// BPM stream survives view dismissal — the RideTracker reads from
/// the same instance during a recording.
struct BluetoothSensorsView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        let hr = environment.heartRate

        Form {
            Section {
                statusRow(hr: hr)
                if case .connected = hr.state {
                    liveBpmRow(hr: hr)
                    if let battery = hr.batteryPct {
                        HStack {
                            Text("Batterie")
                            Spacer()
                            Text("\(battery)%")
                                .foregroundStyle(battery < 20 ? .red : .secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }

            // Action row — start/stop scan or disconnect.
            Section {
                actionButton(hr: hr)
            }

            // Discovered sensors — populated while scanning.
            if hr.state == .scanning || !hr.discoveredPeripherals.isEmpty {
                Section("Capteurs détectés") {
                    if hr.discoveredPeripherals.isEmpty {
                        HStack {
                            ProgressView().scaleEffect(0.8)
                            Text("Recherche…").foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(hr.discoveredPeripherals) { sensor in
                            Button {
                                hr.connect(sensor)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(sensor.name)
                                            .foregroundStyle(AppColors.ink)
                                        Text("Signal \(sensor.rssi) dBm")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }

            // Notes — explain the audio session / activity flow.
            Section {
                Text("Le capteur reste connecté pendant tes sorties Track et alimente la fréquence cardiaque en temps réel. Les sangles compatibles (Polar H10, Wahoo TICKR, Garmin HRM-Dual, Decathlon Geonaute) implémentent toutes le profil Bluetooth Heart Rate Service (0x180D).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Capteurs Bluetooth")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Auto-scan on enter if not already connected.
            if !isConnected(hr.state) {
                hr.startScan()
            }
        }
        .onDisappear {
            // Stop scanning when leaving the screen — keep the
            // existing connection alive though, so we don't drop
            // a sensor the user just paired.
            if hr.state == .scanning {
                hr.stopScan()
            }
        }
    }

    // MARK: - Row builders

    private func statusRow(hr: HeartRateMonitor) -> some View {
        HStack {
            Image(systemName: stateIcon(hr.state))
                .foregroundStyle(stateColor(hr.state))
            VStack(alignment: .leading, spacing: 2) {
                Text(stateLabel(hr.state))
                    .font(.system(.body).weight(.semibold))
                if let detail = stateDetail(hr.state) {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func liveBpmRow(hr: HeartRateMonitor) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "heart.fill")
                .foregroundStyle(.red)
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text("Fréquence cardiaque")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let bpm = hr.currentBpm {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(bpm)")
                            .font(.system(.title, design: .serif).weight(.heavy))
                            .monospacedDigit()
                            .foregroundStyle(AppColors.ink)
                        Text("bpm")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("En attente…").foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func actionButton(hr: HeartRateMonitor) -> some View {
        switch hr.state {
        case .poweredOff:
            Link(destination: URL(string: UIApplication.openSettingsURLString)!) {
                Label("Activer Bluetooth dans Réglages", systemImage: "arrow.up.right.square")
            }
        case .unauthorized:
            Link(destination: URL(string: UIApplication.openSettingsURLString)!) {
                Label("Autoriser Bluetooth dans Réglages", systemImage: "arrow.up.right.square")
            }
        case .idle:
            Button {
                hr.startScan()
            } label: {
                Label("Rechercher un capteur", systemImage: "magnifyingglass")
            }
        case .scanning:
            Button(role: .cancel) {
                hr.stopScan()
            } label: {
                Label("Arrêter la recherche", systemImage: "stop.fill")
            }
        case .connecting:
            HStack {
                ProgressView().scaleEffect(0.8)
                Text("Connexion en cours…").foregroundStyle(.secondary)
            }
        case .connected:
            Button(role: .destructive) {
                hr.disconnect()
            } label: {
                Label("Déconnecter le capteur", systemImage: "antenna.radiowaves.left.and.right.slash")
            }
        }
    }

    // MARK: - State helpers

    private func isConnected(_ state: HeartRateMonitor.State) -> Bool {
        if case .connected = state { return true }
        return false
    }

    private func stateLabel(_ state: HeartRateMonitor.State) -> String {
        switch state {
        case .poweredOff:    return "Bluetooth désactivé"
        case .unauthorized:  return "Bluetooth non autorisé"
        case .idle:          return "Aucun capteur connecté"
        case .scanning:      return "Recherche en cours"
        case .connecting:    return "Connexion…"
        case .connected(let name): return "Connecté : \(name)"
        }
    }

    private func stateDetail(_ state: HeartRateMonitor.State) -> String? {
        switch state {
        case .poweredOff:    return "Active Bluetooth pour scanner les capteurs"
        case .unauthorized:  return "Autorise l'app dans Réglages → Confidentialité → Bluetooth"
        case .idle:          return nil
        case .scanning:      return "Place ton capteur à proximité"
        case .connecting:    return nil
        case .connected:     return "Le BPM remplace la mesure Apple Watch pendant la sortie"
        }
    }

    private func stateIcon(_ state: HeartRateMonitor.State) -> String {
        switch state {
        case .poweredOff, .unauthorized: return "antenna.radiowaves.left.and.right.slash"
        case .idle:                       return "antenna.radiowaves.left.and.right"
        case .scanning:                   return "wifi.exclamationmark"
        case .connecting:                 return "wifi"
        case .connected:                  return "heart.fill"
        }
    }

    private func stateColor(_ state: HeartRateMonitor.State) -> Color {
        switch state {
        case .poweredOff, .unauthorized: return AppColors.inkLight
        case .idle:                       return AppColors.inkMid
        case .scanning, .connecting:      return AppColors.terra
        case .connected:                  return .red
        }
    }
}
