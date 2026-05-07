import Foundation

enum APIError: Error, LocalizedError {
    case invalidURL
    case http(Int)
    case decoding(Error)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .http(let code): return "Server returned \(code)"
        case .decoding(let err): return "Decoding error: \(err.localizedDescription)"
        case .transport(let err): return "Network error: \(err.localizedDescription)"
        }
    }
}

actor APIClient {
    static let shared = APIClient()

    /// Backend deployed on Vercel — same code as the web app.
    private let baseURL = URL(string: "https://the-little-explorer-app.vercel.app")!

    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
    }

    // MARK: - Activities

    func activities(user: AppUser) async throws -> [RideRecord] {
        try await get("/api/activities", query: ["user": user.rawValue])
    }

    // MARK: - BAN address search / reverse geocode

    func searchPlaces(query: String) async throws -> [CommuneResult] {
        guard query.count >= 2 else { return [] }
        return try await get("/api/commune-search", query: ["q": query])
    }

    func reverseGeocode(lat: Double, lng: Double) async throws -> [CommuneResult] {
        try await get("/api/commune-search", query: [
            "lat": String(lat),
            "lng": String(lng),
        ])
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

    private func execute<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(error)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.http(http.statusCode)
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }
}
