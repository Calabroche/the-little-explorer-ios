import Foundation

enum APIError: Error, LocalizedError {
    case invalidURL
    case http(Int)
    case decoding(Error)
    case transport(Error)
    case unauthorized   // 401 — token missing/expired/revoked

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .http(let code): return "Server returned \(code)"
        case .decoding(let err): return "Decoding error: \(err.localizedDescription)"
        case .transport(let err): return "Network error: \(err.localizedDescription)"
        case .unauthorized: return "Session expirée — reconnecte-toi."
        }
    }
}

actor APIClient {
    static let shared = APIClient()

    /// Backend deployed on Vercel — same code as the web app.
    private let baseURL = URL(string: "https://the-little-explorer-app.vercel.app")!

    private let session: URLSession
    private let decoder: JSONDecoder

    /// Bearer token issued by /auth/native-done after the user signed
    /// in via the web's Google or Strava OAuth flow. Set by
    /// AppEnvironment whenever SessionStore.token changes; sent as
    /// `Authorization: Bearer …` on every authenticated request.
    private var authToken: String?

    init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
    }

    func setAuthToken(_ token: String?) {
        self.authToken = token
    }

    // MARK: - Activities

    /// Lists the signed-in user's activities. The `user:` parameter is
    /// kept for backward compat with older call sites but is ignored
    /// by the server — user is derived from the bearer token.
    func activities(user: AppUser? = nil) async throws -> [RideRecord] {
        _ = user // legacy
        return try await get("/api/activities")
    }

    // MARK: - Profile (/api/me)

    func me() async throws -> MeProfile {
        try await get("/api/me")
    }

    /// PATCH /api/me — update rider weight, bike weight, FTP override.
    /// Field semantics mirror the web API:
    ///   - `.unchanged` → key omitted from request
    ///   - `.set(value)` → key set to the number
    ///   - `.clear` → key explicitly set to null (= revert to default)
    func updateSettings(riderKg: SettingsField<Double>, bikeKg: SettingsField<Double>, customFtp: SettingsField<Int>) async throws -> MeProfile {
        var body: [String: Any] = [:]
        switch riderKg {
        case .unchanged: break
        case .set(let v): body["rider_kg"] = v
        case .clear:     body["rider_kg"] = NSNull()
        }
        switch bikeKg {
        case .unchanged: break
        case .set(let v): body["bike_kg"] = v
        case .clear:     body["bike_kg"] = NSNull()
        }
        switch customFtp {
        case .unchanged: break
        case .set(let v): body["custom_ftp"] = v
        case .clear:     body["custom_ftp"] = NSNull()
        }
        return try await patchJSON("/api/me", jsonObject: body)
    }

    enum SettingsField<V> {
        case unchanged
        case set(V)
        case clear
    }

    // MARK: - Admin

    struct AdminUser: Decodable, Sendable, Identifiable {
        let id: String
        let email: String?
        let name: String?
        let athleteId: Int?
        let activityCount: Int?
        let providers: [String]?
        let createdAt: String?

        enum CodingKeys: String, CodingKey {
            case id, email, name, providers
            case athleteId      = "athlete_id"
            case activityCount  = "activity_count"
            case createdAt      = "created_at"
        }
    }

    struct AdminUsersResponse: Decodable, Sendable { let users: [AdminUser] }

    func adminUsers() async throws -> [AdminUser] {
        let response: AdminUsersResponse = try await get("/api/admin/users")
        return response.users
    }

    // MARK: - Strava manual sync

    @discardableResult
    func syncStrava() async throws -> SyncResult {
        try await post("/api/strava/sync", body: EmptyBody())
    }

    struct SyncResult: Decodable, Sendable { let ok: Bool; let count: Int? }
    private struct EmptyBody: Encodable {}

    // MARK: - BAN address search / reverse geocode

    func searchPlaces(query: String) async throws -> [CommuneResult] {
        guard query.count >= 2 else { return [] }
        return try await get("/api/commune-search", query: ["q": query])
    }

    func reverseGeocode(lat: Double, lng: Double, exclude: String? = nil) async throws -> [CommuneResult] {
        var query: [String: String] = [
            "lat": String(lat),
            "lng": String(lng),
        ]
        if let exclude, !exclude.isEmpty { query["exclude"] = exclude }
        return try await get("/api/commune-search", query: query)
    }

    // MARK: - Elevation

    struct ElevationResponse: Decodable { let elevations: [Double] }

    func elevation(for points: [Coordinate]) async throws -> [Double] {
        let payload = ["points": points.map { [$0.lat, $0.lng] }]
        let response: ElevationResponse = try await post("/api/elevation", body: payload)
        return response.elevations
    }

    // MARK: - Bike routing

    func bikeRoute(waypoints: [Coordinate], steps: Bool = false) async throws -> BikeRoute {
        struct Body: Encodable {
            let waypoints: [[Double]]
            let steps: Bool
        }
        let body = Body(
            waypoints: waypoints.map { [$0.lat, $0.lng] },
            steps: steps,
        )
        return try await post("/api/route-bike", body: body)
    }

    // MARK: - Generic helpers

    private func get<T: Decodable>(
        _ path: String,
        query: [String: String] = [:],
    ) async throws -> T {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components?.url else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        return try await execute(request)
    }

    private func post<T: Decodable, B: Encodable>(
        _ path: String,
        body: B,
    ) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await execute(request)
    }

    private func patchJSON<T: Decodable>(
        _ path: String,
        jsonObject: [String: Any],
    ) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: jsonObject, options: [])
        return try await execute(request)
    }

    private func execute<T: Decodable>(_ request: URLRequest) async throws -> T {
        var req = request
        if let token = authToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw APIError.transport(error)
        }
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 {
                // Token expired or revoked — surface a distinct error
                // so the RootView can sign out and bounce to LoginView.
                throw APIError.unauthorized
            }
            if !(200..<300).contains(http.statusCode) {
                throw APIError.http(http.statusCode)
            }
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }
}
