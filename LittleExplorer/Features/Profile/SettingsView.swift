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

    // Danger zone — "Supprimer mon compte". Two-step confirm in-row so a
    // misclick doesn't wipe months of training data. Same pattern as the
    // web /settings page.
    @State private var deleteArmed: Bool = false
    @State private var isDeleting: Bool = false
    @State private var deleteError: String?

    // "Déconnecter tous les appareils" — less destructive, no two-step
    // confirm needed (data stays put, user just has to sign back in).
    @State private var isLoggingOutAll: Bool = false
    @State private var logoutAllError: String?

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

            // Logout from all devices — bumps session_invalidated_at +
            // revokes every api_tokens row. Useful after a lost phone
            // or shared session. Data stays intact, user just has to
            // re-sign-in everywhere.
            Section("Sécurité de la session") {
                if let err = logoutAllError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(Color.red)
                }
                Button {
                    Task { await logoutAll() }
                } label: {
                    HStack {
                        if isLoggingOutAll { ProgressView().scaleEffect(0.8) }
                        Label(
                            isLoggingOutAll ? "Déconnexion…" : "Déconnecter tous les appareils",
                            systemImage: "iphone.slash",
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .disabled(isLoggingOutAll)
                Text("Invalide la session web et toutes les sessions iOS / Apple Watch. Tes données restent intactes — tu pourras te reconnecter.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // "Powered by Strava" attribution — required by the Strava
            // API Agreement on every surface that surfaces Strava data.
            // Discreet footer-style cell that links out to strava.com.
            Section {
                Link(destination: URL(string: "https://www.strava.com")!) {
                    HStack(spacing: 10) {
                        Image(systemName: "bolt.horizontal.fill")
                            .foregroundStyle(Color(red: 0.99, green: 0.32, blue: 0.0)) // Strava orange #FC5200
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Powered by Strava")
                                .font(.system(size: 11).weight(.semibold))
                                .tracking(0.6)
                                .foregroundStyle(AppColors.inkMid)
                            Text("Données d'activité fournies via l'API Strava")
                                .font(.system(size: 10))
                                .foregroundStyle(AppColors.inkLight)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption)
                            .foregroundStyle(AppColors.inkLight)
                    }
                }
            }

            // Danger zone — account deletion. RGPD art. 17 + Strava API
            // requirement (the user must have a way to revoke and delete).
            Section("Zone sensible") {
                if let err = deleteError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(Color.red)
                }
                if !deleteArmed {
                    Button(role: .destructive) {
                        deleteArmed = true
                        deleteError = nil
                    } label: {
                        Label("Supprimer mon compte", systemImage: "trash")
                    }
                    .disabled(isDeleting)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Cette action est irréversible. Tes activités, paramètres, et le lien Strava seront effacés. Tu seras déconnecté.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button(role: .destructive) {
                        Task { await deleteAccount() }
                    } label: {
                        HStack {
                            if isDeleting { ProgressView().scaleEffect(0.8) }
                            Text(isDeleting ? "Suppression…" : "Oui, supprime tout")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "exclamationmark.triangle.fill")
                        }
                    }
                    .disabled(isDeleting)
                    Button {
                        deleteArmed = false
                        deleteError = nil
                    } label: {
                        Text("Annuler")
                    }
                    .disabled(isDeleting)
                }
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

    /// Calls POST /api/me/logout-all then clears the local session.
    /// Same UI contract as `deleteAccount` (dismiss → root → LoginView
    /// via SessionStore observer), just non-destructive on the server.
    @MainActor
    private func logoutAll() async {
        isLoggingOutAll = true
        defer { isLoggingOutAll = false }
        logoutAllError = nil
        do {
            try await environment.api.logoutAllDevices()
            Log.auth.notice("Logout-all OK — clearing local session.")
            environment.session.clear()
            dismiss()
        } catch {
            Log.auth.error("Logout-all failed: \(error.localizedDescription, privacy: .public)")
            logoutAllError = "Échec : \(error.localizedDescription)"
        }
    }

    /// Calls DELETE /api/me, clears the local session on success, and
    /// the LoginView re-takes the root via the SessionStore observer.
    /// On failure leaves the session intact and surfaces the error so
    /// the user can retry.
    @MainActor
    private func deleteAccount() async {
        isDeleting = true
        defer { isDeleting = false }
        deleteError = nil
        do {
            try await environment.api.deleteAccount()
            Log.auth.notice("Account delete OK — clearing local session.")
            environment.session.clear()
            // dismiss() pops the SettingsView from the nav stack. The
            // session observer in RootView will then show LoginView
            // since session.token is now nil.
            dismiss()
        } catch {
            Log.auth.error("Account delete failed: \(error.localizedDescription, privacy: .public)")
            deleteError = "Échec : \(error.localizedDescription)"
            deleteArmed = false
        }
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
