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
            if let data = body.data(using: .utf8) {
                // {"detail": "message"} — simplejwt and DRF generic errors
                if let json = try? JSONDecoder().decode([String: String].self, from: data),
                   let detail = json["detail"] {
                    return detail
                }
                // {"field": ["message"]} — DRF validation errors
                if let json = try? JSONDecoder().decode([String: [String]].self, from: data) {
                    let messages = json.values.flatMap { $0 }
                    if !messages.isEmpty { return messages.joined(separator: ". ") }
                }
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
        decoder.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            // DRF emits "2026-05-18T10:30:00.123456Z" when microseconds > 0
            let withFractional = ISO8601DateFormatter()
            withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = withFractional.date(from: string) { return date }
            // DRF emits "2026-05-18T10:30:00Z" when microseconds == 0
            let withoutFractional = ISO8601DateFormatter()
            withoutFractional.formatOptions = [.withInternetDateTime]
            if let date = withoutFractional.date(from: string) { return date }
            // Date-only fields e.g. event date: "2026-05-01" — parse in local timezone
            // so May 1 stays May 1 regardless of UTC offset
            if string.count == 10 {
                let localFmt = DateFormatter()
                localFmt.locale = Locale(identifier: "en_US_POSIX")
                localFmt.dateFormat = "yyyy-MM-dd"
                localFmt.timeZone = TimeZone.current
                if let date = localFmt.date(from: string) { return date }
            }
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

    // PATCH request
    func patch<Body: Encodable & Sendable, Response: Decodable & Sendable>(
        _ path: String, body: Body, token: String
    ) async throws -> Response {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let encoded = try encoder.encode(body)
        let data = try await request(path: path, method: "PATCH", body: encoded, token: token)
        return try decode(data)
    }

    // DELETE request
    func delete(_ path: String, token: String) async throws {
        _ = try await request(path: path, method: "DELETE", body: nil as Data?, token: token)
    }

    // Vehicle photo upload — returns photo_url
    func uploadVehiclePhoto(_ path: String, imageData: Data, token: String) async throws -> String {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw APIError.invalidURL }
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let crlf = "\r\n"
        var body = Data()
        body.append("--\(boundary)\(crlf)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"photo\"; filename=\"photo.jpg\"\(crlf)".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\(crlf)\(crlf)".data(using: .utf8)!)
        body.append(imageData)
        body.append(crlf.data(using: .utf8)!)
        body.append("--\(boundary)--\(crlf)".data(using: .utf8)!)
        req.httpBody = body

        do {
            let (data, response) = try await session.data(for: req)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401 { throw APIError.unauthorized }
            if code >= 400 {
                let msg = String(data: data, encoding: .utf8) ?? ""
                throw APIError.serverError(code, msg)
            }
            struct Resp: Decodable { let photoUrl: String }
            let parsed = try decoder.decode(Resp.self, from: data)
            return parsed.photoUrl
        } catch let e as APIError { throw e }
        catch { throw APIError.networkError(error) }
    }

    // Multipart photo upload — returns the absolute URL of the saved photo
    func uploadPhoto(_ path: String, imageData: Data, slot: Int, token: String) async throws -> String {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw APIError.invalidURL }
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        var body = Data()
        let crlf = "\r\n"
        // slot field
        body.append("--\(boundary)\(crlf)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"slot\"\(crlf)\(crlf)".data(using: .utf8)!)
        body.append("\(slot)\(crlf)".data(using: .utf8)!)
        // photo file
        body.append("--\(boundary)\(crlf)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"photo\"; filename=\"photo.jpg\"\(crlf)".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\(crlf)\(crlf)".data(using: .utf8)!)
        body.append(imageData)
        body.append(crlf.data(using: .utf8)!)
        body.append("--\(boundary)--\(crlf)".data(using: .utf8)!)
        req.httpBody = body

        do {
            let (data, response) = try await session.data(for: req)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401 { throw APIError.unauthorized }
            if code >= 400 {
                let msg = String(data: data, encoding: .utf8) ?? ""
                throw APIError.serverError(code, msg)
            }
            struct PhotoResponse: Decodable { let url: String }
            let parsed = try decoder.decode(PhotoResponse.self, from: data)
            return parsed.url
        } catch let e as APIError { throw e }
        catch { throw APIError.networkError(error) }
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
