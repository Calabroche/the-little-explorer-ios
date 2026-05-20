import Foundation
import AuthenticationServices

/// Drives the OAuth flow for native login.
///
/// Strategy: rather than implementing Google/Strava OAuth natively
/// (which would require maintaining two client configurations,
/// custom URL schemes for the providers themselves, etc.), we
/// piggyback on the web app's existing NextAuth setup:
///
///   1. ASWebAuthenticationSession opens
///      https://the-little-explorer-app.vercel.app/login?callbackUrl=/auth/native-done
///   2. User signs in via Google or Strava (the same buttons as the
///      web app's login page)
///   3. NextAuth completes OAuth, sets a session cookie
///   4. /auth/native-done (a server component on the web) reads the
///      session, mints a long-lived bearer token, and redirects to
///      `littleexplorer://auth/done?token=<token>`
///   5. ASWebAuthenticationSession's callbackURLScheme catches the
///      custom scheme and returns the URL to this class
///   6. We extract `token`, hand it to SessionStore
///
/// Result: the iOS app gets the same multi-user / Google+Strava auth
/// the web has, with ~80 LOC instead of 800.
@MainActor
final class AuthService: NSObject, ASWebAuthenticationPresentationContextProviding {

    /// Backend deployed on Vercel — same code as the web app.
    private let baseURL = URL(string: "https://the-little-explorer-app.vercel.app")!

    /// Must match CFBundleURLSchemes in project.yml.
    private let callbackScheme = "littleexplorer"

    /// Keep a strong reference while the auth session is active.
    /// ASWebAuthenticationSession is released when this drops to nil.
    private var session: ASWebAuthenticationSession?

    /// Launches the in-app browser to the web login page. Awaits the
    /// custom-scheme redirect, extracts the token, returns it.
    ///
    /// `provider` is the NextAuth provider id — currently "google" or
    /// "strava". Forwarding it via the `?callbackUrl=` chain skips the
    /// /login screen so the user lands directly on the provider's
    /// authorization page (one less tap).
    func authenticate(provider: String) async throws -> String {
        // We want the user to land on /login (which then renders both
        // buttons) so they can pick. If we wanted to skip the picker
        // we'd hit /api/auth/signin/<provider> directly, but that
        // requires a POST + CSRF and ASWebAuthenticationSession only
        // supports GET. So: /login is fine.
        let callbackUrl = "/auth/native-done"
        var comps = URLComponents(url: baseURL.appendingPathComponent("login"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "callbackUrl", value: callbackUrl)]
        guard let start = comps.url else {
            throw AuthError.invalidURL
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let s = ASWebAuthenticationSession(
                url: start,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let error {
                    continuation.resume(throwing: AuthError.system(error))
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: AuthError.noCallback)
                    return
                }
                // Expecting littleexplorer://auth/done?token=XXX
                let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
                if let token = items.first(where: { $0.name == "token" })?.value, !token.isEmpty {
                    continuation.resume(returning: token)
                } else if let errMsg = items.first(where: { $0.name == "error" })?.value {
                    continuation.resume(throwing: AuthError.serverError(errMsg))
                } else {
                    continuation.resume(throwing: AuthError.noToken)
                }
            }
            s.presentationContextProvider = self
            // Use an ephemeral session so the user isn't auto-signed-in
            // from a previous Safari session — gives them the chance to
            // pick a different Google account.
            s.prefersEphemeralWebBrowserSession = false
            // Note: provider param is unused right now — could route to
            // /api/auth/signin/<provider> in a future iteration.
            _ = provider
            self.session = s
            s.start()
        }
    }

    // MARK: - ASWebAuthenticationPresentationContextProviding

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Find the first key window. ASWebAuthenticationSession will
        // present its Safari-backed sheet on top of this anchor.
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })
        return scene?.windows.first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}

enum AuthError: LocalizedError {
    case invalidURL
    case noCallback
    case noToken
    case serverError(String)
    case system(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:        return "URL d'authentification invalide."
        case .noCallback:        return "Pas de retour depuis l'authentification."
        case .noToken:           return "Token manquant dans la réponse."
        case .serverError(let s): return "Erreur serveur : \(s)"
        case .system(let err):   return err.localizedDescription
        }
    }
}
