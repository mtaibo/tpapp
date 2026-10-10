import Foundation

public struct HTTPClient: Sendable {
    public let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        self.encoder = encoder
    }

    public func get<Response: Decodable>(_ path: String) async throws -> Response {
        let data = try await execute(path: path, method: "GET", body: Optional<EmptyBody>.none)
        return try decode(data)
    }

    public func post<Body: Encodable, Response: Decodable>(_ path: String, body: Body) async throws -> Response {
        let data = try await execute(path: path, method: "POST", body: body)
        return try decode(data)
    }

    public func post(_ path: String) async throws {
        _ = try await execute(path: path, method: "POST", body: Optional<EmptyBody>.none)
    }

    private func decode<Response: Decodable>(_ data: Data) throws -> Response {
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding
        }
    }

    private func execute<Body: Encodable>(path: String, method: String, body: Body?) async throws -> Data {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = try encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.server(status: http.statusCode, message: Self.errorDetail(from: data))
        }
        return data
    }

    private static func errorDetail(from data: Data) -> String? {
        struct ErrorBody: Decodable { let detail: String? }
        return try? JSONDecoder().decode(ErrorBody.self, from: data).detail
    }
}

private struct EmptyBody: Encodable {}
