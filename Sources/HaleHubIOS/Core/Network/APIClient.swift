import Foundation

enum APIError: Error, LocalizedError {
    case invalidURL
    case unauthorized
    case serverError(Int, String)
    case decodingError(Error)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .unauthorized: return "Session expired — please log in again"
        case .serverError(let code, let body):
            // Try to parse DRF validation errors like {"field": ["message"]}
            if let data = body.data(using: .utf8),
               let json = try? JSONDecoder().decode([String: [String]].self, from: data) {
                let messages = json.values.flatMap { $0 }
                if !messages.isEmpty { return messages.joined(separator: ". ") }
            }
            return "Server error (\(code))"
        case .decodingError(let e): return "Data error: \(e.localizedDescription)"
        case .networkError(let e): return e.localizedDescription
        }
    }
}

actor APIClient {
    static let shared = APIClient()

    private let baseURL = "https://flyhomemn.com/api"
    private let session: URLSession
    private let decoder: JSONDecoder

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)

        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        decoder.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            if let date = formatter.date(from: string) { return date }
            // Fallback: date-only strings like "2025-01-15"
            let fallback = ISO8601DateFormatter()
            fallback.formatOptions = [.withFullDate]
            if let date = fallback.date(from: string) { return date }
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Cannot parse date: \(string)"
            )
        }
    }

    func get<T: Decodable & Sendable>(_ path: String, token: String) async throws -> T {
        let data = try await request(path: path, method: "GET", body: nil as Data?, token: token)
        return try decode(data)
    }

    func post<Body: Encodable & Sendable, Response: Decodable & Sendable>(
        _ path: String, body: Body, token: String?
    ) async throws -> Response {
        // Must use snake_case — Django serializers expect event_type, price_per_gallon, etc.
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let encoded = try encoder.encode(body)
        let data = try await request(path: path, method: "POST", body: encoded, token: token)
        return try decode(data)
    }

    // POST with no request body (e.g. mark-cooked)
    func postEmpty<Response: Decodable & Sendable>(_ path: String, token: String) async throws -> Response {
        let data = try await request(path: path, method: "POST", body: nil as Data?, token: token)
        return try decode(data)
    }

    // DELETE request
    func delete(_ path: String, token: String) async throws {
        _ = try await request(path: path, method: "DELETE", body: nil as Data?, token: token)
    }

    private func request(path: String, method: String, body: Data?, token: String?) async throws -> Data {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.httpBody = body
        do {
            let (data, response) = try await session.data(for: req)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401 { throw APIError.unauthorized }
            if code >= 400 {
                let msg = String(data: data, encoding: .utf8) ?? ""
                throw APIError.serverError(code, msg)
            }
            return data
        } catch let e as APIError { throw e }
        catch { throw APIError.networkError(error) }
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do { return try decoder.decode(T.self, from: data) }
        catch { throw APIError.decodingError(error) }
    }
}
