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
    private let userDefaultsKey = "tle.session.token.v1"

    init() {
        // Lazy-load the token on init so RootView can decide what to
        // render at app launch without an async hop. Try keychain first;
        // if it's empty (e.g. simulator wiped the access-group binding
        // on a fresh build), fall back to UserDefaults which survives
        // any in-place reinstall.
        if let stored = readKeychain() ?? readUserDefaults() {
            Task { @MainActor in
                self.token = stored
            }
        }
    }

    @MainActor
    func setToken(_ value: String) {
        writeKeychain(value)
        writeUserDefaults(value)
        token = value
    }

    @MainActor
    func clear() {
        deleteKeychain()
        deleteUserDefaults()
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
            // Stronger accessibility than the previous
            // `AfterFirstUnlock`: now the token is readable ONLY while
            // the device is unlocked AND only on the device that
            // wrote it (never restored to another device from an
            // iCloud / Finder backup). Defends against:
            //   • Stolen-and-still-unlocked: less common since unlock
            //     state matters, but combined with the 90-day server
            //     expiry the window narrows further.
            //   • Backup restore to attacker's device: previously the
            //     token would travel with the backup; now it doesn't.
            q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
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

    // MARK: - UserDefaults fallback
    //
    // Mirrors the token in UserDefaults so it survives the simulator's
    // keychain weirdness (unsigned builds can land in a different access
    // group than the previous install, orphaning keychain items even
    // though the .db file persists). On signed device builds the keychain
    // works correctly and this is just a redundant write.

    private func writeUserDefaults(_ value: String) {
        UserDefaults.standard.set(value, forKey: userDefaultsKey)
    }

    private func readUserDefaults() -> String? {
        UserDefaults.standard.string(forKey: userDefaultsKey)
    }

    private func deleteUserDefaults() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }
}

/// What `/api/me` returns. Stays in sync with the web's MeResponse type.
struct MeProfile: Codable, Sendable {
    let id:         String
    let email:      String?
    let name:       String?
    let image:      String?
    let athleteId:  Int?
    /// Stored overrides — null fields mean "use defaults" from the
    /// effective fallback ladder (db override → legacy → default).
    let settings:   StoredSettings?
    let effective:  EffectiveProfile

    struct EffectiveProfile: Codable, Sendable {
        let riderKg:   Double
        let bikeKg:    Double
        let customFtp: Int?
    }

    struct StoredSettings: Codable, Sendable {
        let riderKg:   Double?
        let bikeKg:    Double?
        let customFtp: Int?

        enum CodingKeys: String, CodingKey {
            case riderKg   = "rider_kg"
            case bikeKg    = "bike_kg"
            case customFtp = "custom_ftp"
        }
    }
}
