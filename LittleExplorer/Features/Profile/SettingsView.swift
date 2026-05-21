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

    var body: some View {
        Form {
            Section("Profil cycliste") {
                LabeledField(label: "Poids du coureur (kg)", placeholder: "ex. 66", text: $riderKgText, keyboard: .decimalPad)
                LabeledField(label: "Poids du vélo (kg)", placeholder: "ex. 8.2", text: $bikeKgText, keyboard: .decimalPad)
                LabeledField(label: "FTP custom (W)", placeholder: "vide = défaut", text: $customFtpText, keyboard: .numberPad)
                Text("Laisse un champ vide pour revenir à la valeur par défaut.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
