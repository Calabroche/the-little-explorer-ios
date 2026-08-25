import AVFoundation
import PhotosUI
import SwiftUI

/// Mirror of the web's `/settings` page. Edits rider_kg, bike_kg, and
/// custom_ftp on the signed-in user via PATCH /api/me. Empty FTP →
/// clears the override (falls back to the default ladder).
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var nameText: String = ""
    @State private var bioText: String = ""
    // Custom profile photo — picked via PhotosPicker, resized, and saved
    // straight to PATCH /api/me (independent of the Google/Strava avatar).
    @State private var photoItem: PhotosPickerItem?
    @State private var photoBusy: Bool = false
    @State private var photoError: String?
    @State private var riderKgText: String = ""
    @State private var bikeKgText: String = ""
    @State private var customFtpText: String = ""

    // "Exporter mes données" + "Déconnecter Strava" — RGPD art. 20 +
    // granular control over the Strava link.
    @State private var isExporting: Bool = false
    @State private var isDisconnectingStrava: Bool = false
    @State private var reimporting: Bool = false
    @State private var reimportDone: Bool = false
    @State private var dataActionError: String?
    @State private var exportSheetItem: ExportSheetItem?

    // Voice prompts during turn-by-turn navigation. Persisted in
    // UserDefaults so the NavigateState (which lives in a separate
    // module) can read the same key.
    @AppStorage("tle_voice_prompts_enabled") private var voicePromptsEnabled: Bool = true
    @State private var testVoiceState: VoiceTestState = .idle
    enum VoiceTestState { case idle, playing }

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
            Section("Identité") {
                HStack(spacing: 14) {
                    AvatarView(url: environment.session.profile?.image, name: environment.session.profile?.name, size: 56)
                    VStack(alignment: .leading, spacing: 6) {
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Text(photoBusy ? "Envoi…" : (environment.session.profile?.image == nil ? "Ajouter une photo" : "Changer la photo"))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppColors.terra)
                        }
                        .disabled(photoBusy)
                        if environment.session.profile?.image != nil {
                            Button("Retirer la photo") { Task { await saveAvatar(nil) } }
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .disabled(photoBusy)
                        }
                    }
                    Spacer()
                    if photoBusy { ProgressView() }
                }
                if let photoError { Text(photoError).font(.caption).foregroundStyle(.red) }
                LabeledField(label: "Nom affiché", placeholder: environment.session.profile?.name ?? "auto", text: $nameText, keyboard: .default)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Description").font(.subheadline).foregroundStyle(.secondary)
                    TextField("Décris-toi en quelques mots…", text: $bioText, axis: .vertical)
                        .lineLimit(2...5)
                        .textInputAutocapitalization(.sentences)
                    Text("\(bioText.count)/280").font(.caption2).foregroundStyle(.tertiary)
                }
                Text("Ta photo et ta description sont visibles sur ton profil. Laisse le nom vide pour reprendre celui de ton compte.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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

                    // Force a full re-import — recovers workouts whose map/route
                    // was lost by re-reading them from Apple Health.
                    Button {
                        reimporting = true
                        Task {
                            await env.healthKitSync.forceFullResync()
                            await MainActor.run { reimporting = false; reimportDone = true }
                        }
                    } label: {
                        HStack {
                            if reimporting { ProgressView().scaleEffect(0.8) }
                            Text(reimporting ? "Ré-import en cours…" : "Ré-importer tout depuis Apple Santé")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if reimportDone && !reimporting {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(AppColors.green)
                            }
                        }
                    }
                    .disabled(reimporting || !env.healthKitEnabled)
                    Text("Re-lit toutes tes séances Apple Santé et récupère les tracés/cartes manquants. À faire si des sorties s'affichent sans carte.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

            // Turn-by-turn voice prompts during navigation. Toggle
            // here flips the UserDefaults key the NavigateState reads
            // on every speak() call. Audio plays through the phone
            // speaker (or paired Bluetooth headphones) and ducks
            // background music — same UX as Apple Maps.
            Section("Navigation vocale") {
                Toggle(isOn: $voicePromptsEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Annonces vocales pendant la nav")
                        Text("Lit les virages à voix haute à 1.2 km / 500 m / 150 m / 30 m de chaque maneuver. Bypass le bouton silence (catégorie .playback) et duck Spotify pendant l'annonce.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(AppColors.terra)

                if voicePromptsEnabled {
                    Button {
                        Task { await testVoice() }
                    } label: {
                        HStack {
                            if testVoiceState == .playing { ProgressView().scaleEffect(0.8) }
                            Label(
                                testVoiceState == .playing ? "Lecture en cours…" : "Tester la voix",
                                systemImage: "speaker.wave.2.fill",
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .disabled(testVoiceState == .playing)
                    Text("Le test joue une annonce type. Vérifie que le bouton silence n'est pas activé et le volume monté.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // RGPD art. 20 portability + granular Strava unlink. Both
            // are non-destructive — Export just downloads a JSON dump,
            // Disconnect Strava preserves activities and lets the user
            // re-link later.
            Section("Mes données") {
                if let err = dataActionError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(Color.red)
                }
                Button {
                    Task { await exportData() }
                } label: {
                    HStack {
                        if isExporting { ProgressView().scaleEffect(0.8) }
                        Label(
                            isExporting ? "Préparation…" : "Exporter mes données",
                            systemImage: "square.and.arrow.up",
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .disabled(isExporting)
                if environment.session.profile?.athleteId != nil {
                    Button {
                        Task { await disconnectStrava() }
                    } label: {
                        HStack {
                            if isDisconnectingStrava { ProgressView().scaleEffect(0.8) }
                            Label(
                                isDisconnectingStrava ? "Déconnexion…" : "Déconnecter Strava",
                                systemImage: "link.badge.plus",
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .disabled(isDisconnectingStrava)
                }
                Text("L'export contient profil + paramètres + toutes tes activités (JSON, RGPD art. 20). Déconnecter Strava arrête la sync mais conserve l'historique.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await handlePickedPhoto(item) }
        }
        .sheet(item: $exportSheetItem) { item in
            ShareSheet(items: [item.fileURL])
        }
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
        // nameText starts empty (= clear override). If the user has a
        // stored override different from the OAuth name, we'd want to
        // surface it pre-filled. The API doesn't currently distinguish
        // between "OAuth name" and "user-set name" in the response, so
        // we just show the current name as placeholder text and let
        // the user start typing to override.
        nameText = ""
        bioText = profile.bio ?? ""
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

    /// Plays a sample turn-by-turn prompt so the user can confirm the
    /// toggle + system volume + audio routing all work before relying
    /// on the prompts during a real navigation. Mirrors the audio
    /// session config NavigateState uses (.playback + .duckOthers).
    @MainActor
    private func testVoice() async {
        testVoiceState = .playing
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .voicePrompt,
                options: [.duckOthers, .mixWithOthers],
            )
            try AVAudioSession.sharedInstance().setActive(true, options: [])
        } catch {
            Log.tracking.error("test voice: audio session activate failed: \(error.localizedDescription, privacy: .public)")
        }
        let synth = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string:
            "Dans 300 mètres, tournez à droite sur Rue de la République.")
        utterance.voice = AVSpeechSynthesisVoice(language: "fr-FR")
        utterance.rate = 0.5
        utterance.preUtteranceDelay = 0.15
        utterance.postUtteranceDelay = 0.1
        synth.speak(utterance)
        // Wait for the synth to finish — utterance is ~4s; we wait
        // a bit longer to cover the duck-restore transition before
        // flipping the button back to "Tester la voix".
        try? await Task.sleep(for: .seconds(5))
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        testVoiceState = .idle
    }

    /// Fetches the user's export from /api/me/export, writes it to a
    /// temp file, and presents a UIActivityViewController so the user
    /// can save it to Files / mail / AirDrop / iCloud. Errors stay
    /// inline in the section.
    @MainActor
    private func exportData() async {
        isExporting = true
        defer { isExporting = false }
        dataActionError = nil
        do {
            let data = try await environment.api.exportMyData()
            let today = ISO8601DateFormatter.localDate.string(from: Date())
            let filename = "the-little-explorer-export-\(today).json"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try data.write(to: url, options: .atomic)
            exportSheetItem = ExportSheetItem(fileURL: url)
            Log.api.notice("Export OK — \(data.count) bytes written to \(url.lastPathComponent, privacy: .public)")
        } catch {
            Log.api.error("Export failed: \(error.localizedDescription, privacy: .public)")
            dataActionError = "Export échoué : \(error.localizedDescription)"
        }
    }

    /// Calls POST /api/me/disconnect-strava and refreshes the local
    /// profile so the Strava-gated UI (Disconnect button itself, the
    /// "Connecter Strava" button on Login etc.) re-renders without
    /// needing a sign-out.
    @MainActor
    private func disconnectStrava() async {
        isDisconnectingStrava = true
        defer { isDisconnectingStrava = false }
        dataActionError = nil
        do {
            try await environment.api.disconnectStrava()
            // Refresh the profile so athleteId is now nil locally.
            if let refreshed = try? await environment.api.me() {
                environment.session.profile = refreshed
            }
            Log.auth.notice("Strava disconnected via settings.")
        } catch {
            Log.auth.error("Disconnect Strava failed: \(error.localizedDescription, privacy: .public)")
            dataActionError = "Déconnexion Strava échouée : \(error.localizedDescription)"
        }
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

    /// Loads the picked photo, downsizes it to a small square JPEG data URL,
    /// and saves it via PATCH /api/me.
    @MainActor
    private func handlePickedPhoto(_ item: PhotosPickerItem) async {
        photoBusy = true
        photoError = nil
        defer { photoBusy = false; photoItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data),
              let dataUrl = Self.squareJpegDataUrl(image, side: 256) else {
            photoError = "Image illisible."
            return
        }
        await saveAvatar(dataUrl)
    }

    @MainActor
    private func saveAvatar(_ dataUrl: String?) async {
        photoBusy = true
        photoError = nil
        defer { photoBusy = false }
        do {
            let updated = try await environment.api.updateAvatar(dataUrl)
            environment.session.profile = updated
        } catch {
            photoError = "Échec de l'envoi. Réessaie."
        }
    }

    /// Center-crops to a square, scales to `side`px, returns a
    /// `data:image/jpeg;base64,…` URL (~20–40 KB) small enough for users.image.
    private static func squareJpegDataUrl(_ image: UIImage, side: CGFloat) -> String? {
        let minEdge = min(image.size.width, image.size.height)
        let cropRect = CGRect(
            x: (image.size.width - minEdge) / 2,
            y: (image.size.height - minEdge) / 2,
            width: minEdge, height: minEdge,
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        let square = renderer.image { _ in
            if let cg = image.cgImage?.cropping(to: cropRect.applying(CGAffineTransform(scaleX: image.scale, y: image.scale))) {
                UIImage(cgImage: cg, scale: 1, orientation: image.imageOrientation)
                    .draw(in: CGRect(x: 0, y: 0, width: side, height: side))
            } else {
                image.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
            }
        }
        guard let jpeg = square.jpegData(compressionQuality: 0.85) else { return nil }
        return "data:image/jpeg;base64," + jpeg.base64EncodedString()
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
        // Name: empty → unchanged (the field starts empty and we don't
        // want to wipe the existing name just because the user opened
        // settings without typing). Non-empty → set the new value.
        let nameTrimmed = nameText.trimmingCharacters(in: .whitespaces)
        let nameField: APIClient.SettingsField<String> = nameTrimmed.isEmpty ? .unchanged : .set(nameTrimmed)
        // Bio: unlike the name it has no OAuth fallback, so empty → clear.
        let bioTrimmed = String(bioText.trimmingCharacters(in: .whitespaces).prefix(280))
        let bioField: APIClient.SettingsField<String> = bioTrimmed.isEmpty ? .clear : .set(bioTrimmed)

        do {
            let updated = try await environment.api.updateSettings(riderKg: rider, bikeKg: bike, customFtp: ftp, name: nameField, bio: bioField)
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

/// Wraps a URL in an Identifiable for `.sheet(item:)`. The existing
/// `ShareSheet` in LittleExplorer/UI/ShareSheet.swift handles the
/// actual UIActivityViewController bridge.
private struct ExportSheetItem: Identifiable {
    let fileURL: URL
    var id: String { fileURL.path }
}

/// Reusable yyyy-MM-dd local formatter used for the export filename.
private extension ISO8601DateFormatter {
    static let localDate: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()
}
