import SwiftUI

/// Mirror of the web's `/settings` page. Edits rider_kg, bike_kg, and
/// custom_ftp on the signed-in user via PATCH /api/me. Empty FTP →
/// clears the override (falls back to the default ladder).
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var riderKgText: String = ""
    @State private var bikeKgText: String = ""
    @State private var customFtpText: String = ""

    @State private var isSaving: Bool = false
    @State private var saveMessage: String?
    @State private var saveIsError: Bool = false

    @State private var hkProbeState: HealthKitService.AuthorizationProbe?
    @State private var hkProbing: Bool = false

    var body: some View {
        @Bindable var env = environment
        Form {
            Section("Profil cycliste") {
                LabeledField(label: "Poids du coureur (kg)", placeholder: "ex. 66", text: $riderKgText, keyboard: .decimalPad)
                LabeledField(label: "Poids du vélo (kg)", placeholder: "ex. 8.2", text: $bikeKgText, keyboard: .decimalPad)
                LabeledField(label: "FTP custom (W)", placeholder: "vide = défaut", text: $customFtpText, keyboard: .numberPad)
                Text("Laisse un champ vide pour revenir à la valeur par défaut.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Apple Santé") {
                Toggle(isOn: $env.healthKitEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sync vers Apple Santé")
                        Text("Chaque ride enregistré dans l'app est aussi écrit comme HKWorkout dans l'app Santé. Les anneaux d'activité Apple Watch sont crédités.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(AppColors.terra)
                .disabled(!HealthKitService.isAvailable)
                if !HealthKitService.isAvailable {
                    Text("Apple Santé n'est pas disponible sur cet appareil.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Probe button — Apple's privacy means we CAN'T tell
                // from authorizationStatus whether the user granted or
                // denied write access. We attempt a 1-second placeholder
                // workout and immediately delete it; the outcome tells
                // us the truth. If denied, surface a deep-link to the
                // Réglages app's Health permissions screen so the user
                // can fix it in one tap.
                if HealthKitService.isAvailable {
                    Button {
                        Task { await probeHealthKit() }
                    } label: {
                        HStack {
                            if hkProbing { ProgressView().scaleEffect(0.8) }
                            Text(hkProbing ? "Test en cours…" : "Tester l'accès à Apple Santé")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if let state = hkProbeState {
                                Image(systemName: probeIcon(state))
                                    .foregroundStyle(probeColor(state))
                            }
                        }
                    }
                    .disabled(hkProbing)

                    if let state = hkProbeState {
                        Text(state.displayLabel)
                            .font(.caption)
                            .foregroundStyle(probeColor(state))
                        if state == .denied {
                            Button {
                                openHealthSettings()
                            } label: {
                                Label("Ouvrir Réglages → Santé", systemImage: "arrow.up.right.square")
                            }
                        }
                    }
                }
            }

            if let msg = saveMessage {
                Section {
                    Text(msg)
                        .font(.callout)
                        .foregroundStyle(saveIsError ? Color.red : AppColors.green)
                }
            }

            Section {
                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        if isSaving { ProgressView().scaleEffect(0.8) }
                        Text(isSaving ? "Enregistrement…" : "Enregistrer")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(isSaving)
            }
        }
        .navigationTitle("Paramètres")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { hydrateFromProfile() }
        .onChange(of: environment.session.profile?.id) { _, _ in hydrateFromProfile() }
    }

    @MainActor
    private func probeHealthKit() async {
        hkProbing = true
        defer { hkProbing = false }
        let result = await environment.healthKit.verifyAuthorizationByProbe()
        hkProbeState = result
        Log.tracking.notice("HealthKit probe result: \(result.rawValue, privacy: .public)")
    }

    private func probeIcon(_ state: HealthKitService.AuthorizationProbe) -> String {
        switch state {
        case .granted:     return "checkmark.circle.fill"
        case .denied:      return "xmark.octagon.fill"
        case .unavailable: return "minus.circle"
        }
    }

    private func probeColor(_ state: HealthKitService.AuthorizationProbe) -> Color {
        switch state {
        case .granted:     return AppColors.green
        case .denied:      return Color.red
        case .unavailable: return AppColors.inkLight
        }
    }

    /// Deep-link to iOS Settings. There's no public scheme for "→ Santé
    /// → Sources de données" specifically, but the generic settings
    /// open is one tap closer than the user navigating from scratch.
    private func openHealthSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func hydrateFromProfile() {
        guard let profile = environment.session.profile else { return }
        let stored = profile.settings
        let effective = profile.effective
        riderKgText = stored?.riderKg.map { trimmed($0) } ?? trimmed(effective.riderKg)
        bikeKgText = stored?.bikeKg.map { trimmed($0) } ?? trimmed(effective.bikeKg)
        customFtpText = stored?.customFtp.map { String($0) } ?? (effective.customFtp.map { String($0) } ?? "")
    }

    private func trimmed(_ v: Double) -> String {
        // 8.18 → "8.18", 66.0 → "66"
        if v.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(v))
        }
        return String(format: "%g", v)
    }

    private func parseDouble(_ s: String) -> Double? {
        let normalized = s.replacingOccurrences(of: ",", with: ".")
        return Double(normalized.trimmingCharacters(in: .whitespaces))
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        saveMessage = nil

        let rider: APIClient.SettingsField<Double> = riderKgText.trimmingCharacters(in: .whitespaces).isEmpty
            ? .clear
            : (parseDouble(riderKgText).map { .set($0) } ?? .unchanged)
        let bike: APIClient.SettingsField<Double> = bikeKgText.trimmingCharacters(in: .whitespaces).isEmpty
            ? .clear
            : (parseDouble(bikeKgText).map { .set($0) } ?? .unchanged)
        let ftp: APIClient.SettingsField<Int> = customFtpText.trimmingCharacters(in: .whitespaces).isEmpty
            ? .clear
            : (Int(customFtpText.trimmingCharacters(in: .whitespaces)).map { .set($0) } ?? .unchanged)

        do {
            let updated = try await environment.api.updateSettings(riderKg: rider, bikeKg: bike, customFtp: ftp)
            await MainActor.run {
                environment.session.profile = updated
                saveMessage = "Paramètres enregistrés."
                saveIsError = false
            }
        } catch {
            await MainActor.run {
                saveMessage = "Échec : \(error.localizedDescription)"
                saveIsError = true
            }
        }
    }
}

private struct LabeledField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    let keyboard: UIKeyboardType

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField(placeholder, text: $text)
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 140)
        }
    }
}
