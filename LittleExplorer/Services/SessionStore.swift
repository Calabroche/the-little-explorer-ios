import Foundation
import Observation
import Security

/// Stores the bearer token issued by the web app after Google/Strava OAuth.
///
/// Backing store: iOS Keychain (kSecClassGenericPassword). Survives app
/// reinstalls because the keychain item is tied to the user's iCloud
/// keychain when synchronization is enabled at the system level; even
/// without iCloud it persists across app launches and deletes.
///
/// The token is a 32-byte base64url string issued by
/// `/auth/native-done` on the web app. It's sent as
/// `Authorization: Bearer <token>` on every authenticated request.
///
/// On sign-out we delete the keychain item and any cached state.
@Observable
final class SessionStore {

    /// SwiftUI-observable snapshot of the auth state. Mutated only on
    /// the main thread.
    @MainActor var token: String? {
        didSet { isAuthenticated = token != nil }
    }
    @MainActor private(set) var isAuthenticated: Bool = false

    /// Optional cached profile (filled in by APIClient.me() after first
    /// authenticated request). UI reads this to render the avatar + name.
    @MainActor var profile: MeProfile?

    private let service = "com.calabrese.little-explorer-ios.token"
    private let account = "default"

    init() {
        // Lazy-load the token on init so RootView can decide what to
        // render at app launch without an async hop.
        if let stored = readKeychain() {
            Task { @MainActor in
                self.token = stored
            }
        }
    }

    @MainActor
    func setToken(_ value: String) {
        writeKeychain(value)
        token = value
    }

    @MainActor
    func clear() {
        deleteKeychain()
        token = nil
        profile = nil
    }

    // MARK: - Keychain helpers

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func writeKeychain(_ value: String) {
        guard let data = value.data(using: .utf8) else { return }
        // Try update first, fall back to add. Idempotent.
        var q = baseQuery()
        let upd: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(q as CFDictionary, upd as CFDictionary)
        if status == errSecItemNotFound {
            q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(q as CFDictionary, nil)
        }
    }

    private func readKeychain() -> String? {
        var q = baseQuery()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        guard status == errSecSuccess,
              let data = out as? Data,
              let s = String(data: data, encoding: .utf8) else { return nil }
        return s
    }

    private func deleteKeychain() {
        SecItemDelete(baseQuery() as CFDictionary)
    }
}

/// What `/api/me` returns. Stays in sync with the web's MeResponse type.
struct MeProfile: Codable, Sendable {
    let id:         String
    let email:      String?
    let name:       String?
    let athleteId:  Int?
    let effective:  EffectiveProfile

    struct EffectiveProfile: Codable, Sendable {
        let riderKg:   Double
        let bikeKg:    Double
        let customFtp: Int?
    }
}
