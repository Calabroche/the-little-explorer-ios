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

    /// PATCH /api/me — update rider weight, bike weight, FTP override,
    /// and display name. Field semantics mirror the web API:
    ///   - `.unchanged` → key omitted from request
    ///   - `.set(value)` → key set to the number / string
    ///   - `.clear` → key explicitly set to null (= revert to default
    ///                / fall back to OAuth-provided name)
    func updateSettings(
        riderKg: SettingsField<Double>,
        bikeKg: SettingsField<Double>,
        customFtp: SettingsField<Int>,
        name: SettingsField<String> = .unchanged,
    ) async throws -> MeProfile {
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
        switch name {
        case .unchanged: break
        case .set(let v): body["name"] = v
        case .clear:     body["name"] = NSNull()
        }
        return try await patchJSON("/api/me", jsonObject: body)
    }

    /// POST /api/me/disconnect-strava — unlink the Strava account
    /// without deleting the user. Strava token revoked best-effort,
    /// the accounts row is dropped, athlete_id is nulled. Already-
    /// synced activities are preserved.
    func disconnectStrava() async throws {
        try await emptyPost(method: "POST", path: "/api/me/disconnect-strava")
    }

    /// GET /api/me/export — RGPD art. 20 portability dump.
    /// Returns raw JSON bytes. Caller writes to a temp file and
    /// hands to UIActivityViewController so the user can save / mail
    /// / AirDrop it.
    func exportMyData() async throws -> Data {
        let url = baseURL.appendingPathComponent("/api/me/export")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse {
            if (200..<300).contains(http.statusCode) { return data }
            if http.statusCode == 401 { throw APIError.unauthorized }
            throw APIError.http(http.statusCode)
        }
        return data
    }

    enum SettingsField<V> {
        case unchanged
        case set(V)
        case clear
    }

    /// DELETE /api/me — wipe the signed-in user from Supabase. The
    /// server best-effort revokes the Strava token then cascades the
    /// delete across activities / sessions / accounts / api_tokens.
    ///
    /// Caller is responsible for `SessionStore.clear()` + bouncing
    /// back to LoginView after this returns successfully. Throws on
    /// any non-2xx response so the UI can show an error and leave the
    /// session intact.
    func deleteAccount() async throws {
        try await emptyPost(method: "DELETE", path: "/api/me")
    }

    /// POST /api/me/logout-all — invalidate every active session for
    /// the current user (both web JWTs and iOS bearer tokens). Less
    /// destructive than `deleteAccount` — data stays, user just gets
    /// kicked out everywhere and has to sign back in.
    ///
    /// Same UI contract: caller clears SessionStore on success.
    func logoutAllDevices() async throws {
        try await emptyPost(method: "POST", path: "/api/me/logout-all")
    }

    /// Shared no-body request used by `deleteAccount` and
    /// `logoutAllDevices`. Both expect a 204 (No Content) on success.
    private func emptyPost(method: String, path: String) async throws {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 204 || (200..<300).contains(http.statusCode) {
                return
            }
            if http.statusCode == 401 { throw APIError.unauthorized }
            let preview = String(data: data.prefix(200), encoding: .utf8) ?? ""
            Log.api.error("\(method, privacy: .public) \(path, privacy: .public) — HTTP \(http.statusCode) · \(preview, privacy: .public)")
            throw APIError.http(http.statusCode)
        }
    }

    // MARK: - Itineraries

    struct ItinerarySummary: Decodable, Sendable, Identifiable {
        let id: String
        let name: String
        let distance_km: Double?
        let created_at: String
        let waypoint_count: Int
    }

    struct ItinerariesResponse: Decodable, Sendable {
        let items: [ItinerarySummary]
    }

    struct ItineraryDetail: Decodable, Sendable {
        let id: String
        let name: String
        let distance_km: Double?
        let created_at: String
        let payload: Itinerary
    }

    /// GET /api/itineraries — list of the user's saved itineraries
    /// as lightweight summaries (no geometry / waypoints, just
    /// metadata for picking).
    func fetchItineraries() async throws -> [ItinerarySummary] {
        let response: ItinerariesResponse = try await get("/api/itineraries")
        return response.items
    }

    /// GET /api/itineraries?id=<id> — full itinerary with payload.
    func fetchItinerary(id: String) async throws -> Itinerary {
        // NB: pass `id` via the query param, NOT inline in the path —
        // appendingPathComponent percent-encodes the `?`, which would hit a
        // bogus path and return the 404 HTML page (decode then fails with
        // "Unexpected character '<'"), silently dropping every server route.
        let response: ItineraryDetail = try await get("/api/itineraries", query: ["id": id])
        return response.payload
    }

    /// POST /api/itineraries — persist an itinerary upstream so the
    /// Watch can sync it + other devices can see it.
    @discardableResult
    func uploadItinerary(_ itinerary: Itinerary) async throws -> String {
        struct Body: Encodable {
            let id: String
            let name: String
            let distance_km: Double?
            let payload: Itinerary
        }
        let body = Body(
            id:          itinerary.id,
            name:        itinerary.name,
            distance_km: itinerary.distanceKm,
            payload:     itinerary,
        )
        struct Result: Decodable { let id: String; let name: String }
        let result: Result = try await post("/api/itineraries", body: body)
        return result.id
    }

    /// DELETE /api/itineraries — remove server-side. Local cache is
    /// updated by the caller.
    func deleteItinerary(id: String) async throws {
        let url = baseURL.appendingPathComponent("/api/itineraries")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: ["id": id])
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 204 || (200..<300).contains(http.statusCode) { return }
            if http.statusCode == 401 { throw APIError.unauthorized }
            let preview = String(data: data.prefix(200), encoding: .utf8) ?? ""
            Log.api.error("DELETE /api/itineraries \(http.statusCode) · \(preview, privacy: .public)")
            throw APIError.http(http.statusCode)
        }
    }

    // MARK: - Bike maintenance tracker

    /// GET /api/equipment — returns the user's bike pieces with
    /// computed wear ratios. Read-only on iOS for v1; add / edit
    /// happens on the web because the forms are complex and the
    /// 18 pieces are typically seeded once.
    func fetchEquipment() async throws -> EquipmentResponse {
        try await get("/api/equipment")
    }

    /// PATCH /api/equipment — toggles `replaced: true` on a row.
    /// The server stamps `replaced_at = now()` and the next fetch
    /// drops the item from the active list.
    func markEquipmentReplaced(id: String) async throws {
        let url = baseURL.appendingPathComponent("/api/equipment")
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "id":       id,
            "replaced": true,
        ])
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 204 || (200..<300).contains(http.statusCode) { return }
            if http.statusCode == 401 { throw APIError.unauthorized }
            let preview = String(data: data.prefix(200), encoding: .utf8) ?? ""
            Log.api.error("PATCH /api/equipment \(http.statusCode) · \(preview, privacy: .public)")
            throw APIError.http(http.statusCode)
        }
    }

    /// DELETE /api/equipment — hard-delete (vs `markReplaced` which
    /// keeps the row in history). Used for typos / mis-added items.
    func deleteEquipment(id: String) async throws {
        let url = baseURL.appendingPathComponent("/api/equipment")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: ["id": id])
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 204 || (200..<300).contains(http.statusCode) { return }
            if http.statusCode == 401 { throw APIError.unauthorized }
            let preview = String(data: data.prefix(200), encoding: .utf8) ?? ""
            Log.api.error("DELETE /api/equipment \(http.statusCode) · \(preview, privacy: .public)")
            throw APIError.http(http.statusCode)
        }
    }

    // MARK: - Carnet d'entretien

    /// GET /api/service-events?gear_id=<id> — returns the user's
    /// maintenance log scoped to one bike, plus a server-computed
    /// "next due" snapshot per kind. Same shape iOS + web consume.
    func fetchServiceEvents(gearId: String) async throws -> ServiceEventResponse {
        // Query via the param (see fetchItinerary) — inline `?` in the path
        // gets percent-encoded by appendingPathComponent and 404s to HTML.
        try await get("/api/service-events", query: ["gear_id": gearId])
    }

    /// POST /api/service-events — log one maintenance event. Server
    /// defaults `km_at_event` to the bike's current total if we omit
    /// it; we always pass it explicitly so the entry survives a
    /// later Strava-sync (which changes the "current km" out from
    /// under us).
    func addServiceEvent(
        gearId: String,
        kind: ServiceKind,
        date: Date,
        kmAtEvent: Double?,
        notes: String?,
    ) async throws {
        let url = baseURL.appendingPathComponent("/api/service-events")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        var body: [String: Any] = [
            "gear_id": gearId,
            "kind":    kind.rawValue,
            "date":    ISO8601DateFormatter.dateOnly.string(from: date),
        ]
        if let kmAtEvent { body["km_at_event"] = kmAtEvent }
        if let notes, !notes.isEmpty { body["notes"] = notes }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse {
            if (200..<300).contains(http.statusCode) { return }
            if http.statusCode == 401 { throw APIError.unauthorized }
            let preview = String(data: data.prefix(200), encoding: .utf8) ?? ""
            Log.api.error("POST /api/service-events \(http.statusCode) · \(preview, privacy: .public)")
            throw APIError.http(http.statusCode)
        }
    }

    /// DELETE /api/service-events — wipe a logged event by id.
    func deleteServiceEvent(id: String) async throws {
        let url = baseURL.appendingPathComponent("/api/service-events")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: ["id": id])
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse {
            if (200..<300).contains(http.statusCode) { return }
            if http.statusCode == 401 { throw APIError.unauthorized }
            let preview = String(data: data.prefix(200), encoding: .utf8) ?? ""
            Log.api.error("DELETE /api/service-events \(http.statusCode) · \(preview, privacy: .public)")
            throw APIError.http(http.statusCode)
        }
    }

    // MARK: - Admin

    struct AdminUser: Decodable, Sendable, Identifiable {
        let id: String
        let email: String?
        let name: String?
        let image: String?
        let athleteId: Int?
        let activityCount: Int?
        let providers: [String]?
        let createdAt: String?

        enum CodingKeys: String, CodingKey {
            case id, email, name, image, providers
            case athleteId      = "athleteId"
            case activityCount  = "activities"
            case createdAt      = "createdAt"
        }
    }

    struct AdminUsersResponse: Decodable, Sendable { let users: [AdminUser] }

    func adminUsers() async throws -> [AdminUser] {
        let response: AdminUsersResponse = try await get("/api/admin/users")
        return response.users
    }

    /// Hard-delete a user (cascades to all their data). Mirrors the web
    /// admin's "✗ Supprimer". Server enforces the same allowlist + the
    /// "can't delete yourself" guard.
    @discardableResult
    func adminDeleteUser(id: String) async throws -> Bool {
        struct Resp: Decodable, Sendable { let ok: Bool? }
        let url = baseURL.appendingPathComponent("/api/admin/users")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["id": id])
        let resp: Resp = try await execute(request)
        return resp.ok ?? true
    }

    /// Decodable mirror of GET /api/admin/metrics (the web /admin/metrics
    /// dashboard data). Field names map the snake_case JSON via CodingKeys
    /// since the shared decoder doesn't apply convertFromSnakeCase.
    struct AdminMetrics: Decodable, Sendable {
        struct Totals: Decodable, Sendable {
            let users: Int
            let activities: Int
            let events7d: Int
            let signups7d: Int
            let exportsTotal: Int
            let dauToday: Int
            enum CodingKeys: String, CodingKey {
                case users, activities
                case events7d     = "events_7d"
                case signups7d    = "signups_7d"
                case exportsTotal = "exports_total"
                case dauToday     = "dau_today"
            }
        }
        struct DauPoint: Decodable, Sendable, Identifiable {
            let day: String
            let count: Int
            var id: String { day }
        }
        struct Funnel: Decodable, Sendable {
            let signup: Int
            let welcomeDone: Int
            let sportDone: Int
            let profileDone: Int
            let stravaConnected: Int
            let stravaSkipped: Int
            let complete: Int
            enum CodingKeys: String, CodingKey {
                case signup, complete
                case welcomeDone     = "welcome_done"
                case sportDone       = "sport_done"
                case profileDone     = "profile_done"
                case stravaConnected = "strava_connected"
                case stravaSkipped   = "strava_skipped"
            }
        }
        struct EventCount: Decodable, Sendable, Identifiable {
            let type: String
            let count: Int
            var id: String { type }
        }
        struct Sync: Decodable, Sendable {
            let received7d: Int
            let synced7d: Int
            let successRate: Double
            enum CodingKeys: String, CodingKey {
                case received7d  = "received_7d"
                case synced7d    = "synced_7d"
                case successRate = "success_rate"
            }
        }
        struct RecentEvent: Decodable, Sendable, Identifiable {
            let type: String
            let userId: String?
            let userName: String?
            let occurredAt: String
            let properties: JSONValue?
            let id = UUID()
            enum CodingKeys: String, CodingKey {
                case type, userName, properties
                case userId     = "user_id"
                case occurredAt = "occurred_at"
            }
        }
        /// Minimal arbitrary-JSON value so we can show event `properties`
        /// (a free-form object) without modelling every event's shape.
        enum JSONValue: Decodable, Sendable {
            case string(String), number(Double), bool(Bool)
            case object([String: JSONValue]), array([JSONValue]), null

            init(from decoder: Decoder) throws {
                let c = try decoder.singleValueContainer()
                if c.decodeNil() { self = .null; return }
                if let b = try? c.decode(Bool.self)   { self = .bool(b); return }
                if let n = try? c.decode(Double.self) { self = .number(n); return }
                if let s = try? c.decode(String.self) { self = .string(s); return }
                if let o = try? c.decode([String: JSONValue].self) { self = .object(o); return }
                if let a = try? c.decode([JSONValue].self)         { self = .array(a); return }
                self = .null
            }

            /// Compact one-line rendering for the activity tail's detail column.
            var display: String {
                switch self {
                case .string(let s): return s
                case .bool(let b):   return b ? "true" : "false"
                case .number(let n): return n == n.rounded() ? String(Int(n)) : String(n)
                case .null:          return "null"
                case .array(let a):  return "[" + a.map(\.display).joined(separator: ", ") + "]"
                case .object(let o): return o.map { "\($0.key): \($0.value.display)" }.sorted().joined(separator: ", ")
                }
            }

            var isEmpty: Bool {
                switch self {
                case .object(let o): return o.isEmpty
                case .array(let a):  return a.isEmpty
                case .null:          return true
                default:             return false
                }
            }
        }

        /// One user's day-by-day activity over the 30-day window. Keeps each
        /// rider's daily presence that the aggregate `dau` count collapses.
        struct DauUser: Decodable, Sendable, Identifiable {
            let userId: String
            let name: String?
            let total: Int
            let days: [String: Int]      // day ("YYYY-MM-DD") → event count
            var id: String { userId }
            enum CodingKeys: String, CodingKey {
                case name, total, days
                case userId = "userId"
            }
        }

        let totals: Totals
        let dau: [DauPoint]
        let dauDays: [String]
        let dauByUser: [DauUser]
        let funnel: Funnel
        let events: [EventCount]
        let sync: Sync
        let recent: [RecentEvent]
    }

    func adminMetrics() async throws -> AdminMetrics {
        try await get("/api/admin/metrics")
    }

    // MARK: - Strava manual sync

    @discardableResult
    func syncStrava() async throws -> SyncResult {
        try await post("/api/strava/sync", body: EmptyBody())
    }

    struct SyncResult: Decodable, Sendable { let ok: Bool; let count: Int? }
    private struct EmptyBody: Encodable {}

    // MARK: - Strava upload — push a locally-recorded ride

    struct StravaUploadResult: Decodable, Sendable {
        let ok: Bool
        let uploadId: Int?
        let status: String?
    }

    /// Push a `RideRecord` to the user's Strava account as a new
    /// activity. Server-side endpoint serialises a GPX and multipart-
    /// POSTs it to Strava's /uploads. Strava processes the file async
    /// — our existing webhook picks up the resulting activity-create
    /// event and syncs it back into Supabase.
    @discardableResult
    func uploadToStrava(record: RideRecord) async throws -> StravaUploadResult {
        struct Body: Encodable {
            let gpx: String
            let name: String
            let activityType: String
            let externalId: String
        }
        let body = Body(
            gpx:          RideGpxBuilder.build(record),
            name:         record.title,
            activityType: record.originalType ?? record.type,
            externalId:   "tle-ride-\(record.id)",
        )
        return try await post("/api/strava/upload-activity", body: body)
    }

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

    // MARK: - Route analysis (way types + surfaces)

    struct RouteAnalysis: Decodable, Sendable {
        struct Bucket: Decodable, Sendable, Identifiable {
            let key: String
            let label: String
            let meters: Int
            var id: String { key }
        }
        let wayTypes: [Bucket]
        let surfaces: [Bucket]
        let totalM: Int

        enum CodingKeys: String, CodingKey {
            case wayTypes, surfaces
            case totalM = "total_m"
        }
    }

    /// Way-type + surface breakdown for a route (OSM-enriched). Re-routes
    /// the waypoints server-side, so we just send the ordered points.
    func routeWays(waypoints: [Coordinate]) async throws -> RouteAnalysis {
        struct Body: Encodable { let waypoints: [[Double]] }
        return try await post("/api/route-ways", body: Body(waypoints: waypoints.map { [$0.lat, $0.lng] }))
    }

    // MARK: - Resupply points (water / food) along a route

    /// One OSM place near the route where a rider can refill water or grab
    /// food. `cat` is "water" | "supermarket" | "convenience" | "bakery".
    struct RoutePoi: Decodable, Sendable, Identifiable {
        let cat: String
        let name: String?
        let lat: Double
        let lng: Double
        var id: String { "\(cat):\(lat),\(lng)" }
        var coordinate: Coordinate { Coordinate(lat: lat, lng: lng) }
    }

    /// Water + food resupply points within ~120 m of the route geometry.
    func routePois(geometry: [Coordinate]) async throws -> [RoutePoi] {
        struct Body: Encodable { let geometry: [[Double]] }
        struct Resp: Decodable { let pois: [RoutePoi] }
        let r: Resp = try await post("/api/route-pois", body: Body(geometry: geometry.map { [$0.lat, $0.lng] }))
        return r.pois
    }

    // MARK: - Cols / summits near a departure

    /// A named mountain pass (`kind == "col"`) or summit (`kind == "sommet"`)
    /// near the departure, with elevation, straight-line distance and commune.
    struct Col: Decodable, Sendable, Identifiable {
        let name: String
        let kind: String        // "col" | "sommet"
        let lat: Double
        let lng: Double
        let ele: Int?           // summit elevation (m), when known
        let distKm: Double      // straight-line distance from the departure
        let city: String?       // commune the col sits in
        var id: String { "col:\(lat),\(lng)" }
        var coordinate: Coordinate { Coordinate(lat: lat, lng: lng) }
        var isSummit: Bool { kind == "sommet" }
    }

    /// Named cols + summits within `radiusKm` of (lat, lng), nearest first.
    func cols(lat: Double, lng: Double, radiusKm: Double) async throws -> [Col] {
        struct Body: Encodable { let lat: Double; let lng: Double; let radiusKm: Double }
        struct Resp: Decodable { let cols: [Col] }
        let r: Resp = try await post("/api/cols", body: Body(lat: lat, lng: lng, radiusKm: radiusKm))
        return r.cols
    }

    /// `profile` is "bike" (default) or "foot" (running — OSRM foot profile,
    /// allows footpaths).
    func bikeRoute(waypoints: [Coordinate], steps: Bool = false, profile: String = "bike") async throws -> BikeRoute {
        struct Body: Encodable {
            let waypoints: [[Double]]
            let steps: Bool
            let profile: String
        }
        let body = Body(
            waypoints: waypoints.map { [$0.lat, $0.lng] },
            steps: steps,
            profile: profile,
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
        let path = req.url?.path ?? "?"
        let method = req.httpMethod ?? "?"
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            Log.api.error("\(method, privacy: .public) \(path, privacy: .public) — transport: \(error.localizedDescription, privacy: .public)")
            throw APIError.transport(error)
        }
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 {
                Log.auth.error("\(method, privacy: .public) \(path, privacy: .public) — 401 unauthorized")
                throw APIError.unauthorized
            }
            if !(200..<300).contains(http.statusCode) {
                let preview = String(data: data.prefix(200), encoding: .utf8) ?? ""
                Log.api.error("\(method, privacy: .public) \(path, privacy: .public) — HTTP \(http.statusCode) · \(preview, privacy: .public)")
                throw APIError.http(http.statusCode)
            }
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            // Log a chunk of the payload so the diagnostics view shows
            // what the server actually sent when decoding broke. Useful
            // when a model drifts away from the API (the bike-route bug
            // we just fixed would have surfaced here instantly).
            let preview = String(data: data.prefix(400), encoding: .utf8) ?? "<binary>"
            Log.api.error("\(method, privacy: .public) \(path, privacy: .public) — decode failure: \(error.localizedDescription, privacy: .public) · body: \(preview, privacy: .public)")
            throw APIError.decoding(error)
        }
    }
}
