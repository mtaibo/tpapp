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

    public func get<Response: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> Response {
        let data = try await execute(path: path, method: "GET", query: query, body: Optional<EmptyBody>.none)
        return try decode(data)
    }

    public func post<Body: Encodable, Response: Decodable>(_ path: String, query: [String: String] = [:], body: Body) async throws -> Response {
        let data = try await execute(path: path, method: "POST", query: query, body: body)
        return try decode(data)
    }

    public func post(_ path: String) async throws {
        _ = try await execute(path: path, method: "POST", query: [:], body: Optional<EmptyBody>.none)
    }

    public func post<Response: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> Response {
        let data = try await execute(path: path, method: "POST", query: query, body: Optional<EmptyBody>.none)
        return try decode(data)
    }

    public func patch<Body: Encodable, Response: Decodable>(_ path: String, body: Body) async throws -> Response {
        let data = try await execute(path: path, method: "PATCH", query: [:], body: body)
        return try decode(data)
    }

    public func delete<Response: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> Response {
        let data = try await execute(path: path, method: "DELETE", query: query, body: Optional<EmptyBody>.none)
        return try decode(data)
    }

    public func delete<Body: Encodable, Response: Decodable>(_ path: String, body: Body) async throws -> Response {
        let data = try await execute(path: path, method: "DELETE", query: [:], body: body)
        return try decode(data)
    }

    /// Raw binary GET for responses that aren't JSON, e.g. file downloads.
    public func getData(_ path: String, query: [String: String] = [:]) async throws -> Data {
        try await execute(path: path, method: "GET", query: query, body: Optional<EmptyBody>.none)
    }

    public struct UploadFile: Sendable {
        public let fieldName: String
        public let filename: String
        public let mimeType: String
        public let data: Data

        public init(fieldName: String = "files", filename: String, mimeType: String = "application/octet-stream", data: Data) {
            self.fieldName = fieldName
            self.filename = filename
            self.mimeType = mimeType
            self.data = data
        }
    }

    public func upload<Response: Decodable>(_ path: String, query: [String: String] = [:], files: [UploadFile]) async throws -> Response {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        for file in files {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(file.fieldName)\"; filename=\"\(file.filename)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: \(file.mimeType)\r\n\r\n".data(using: .utf8)!)
            body.append(file.data)
            body.append("\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        let data = try await executeRaw(
            path: path,
            method: "POST",
            query: query,
            contentType: "multipart/form-data; boundary=\(boundary)",
            body: body
        )
        return try decode(data)
    }

    private func decode<Response: Decodable>(_ data: Data) throws -> Response {
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding
        }
    }

    private func execute<Body: Encodable>(path: String, method: String, query: [String: String], body: Body?) async throws -> Data {
        let encodedBody = try body.map { try encoder.encode($0) }
        return try await executeRaw(
            path: path,
            method: method,
            query: query,
            contentType: encodedBody == nil ? nil : "application/json",
            body: encodedBody
        )
    }

    private func executeRaw(path: String, method: String, query: [String: String], contentType: String?, body: Data?) async throws -> Data {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = body
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
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
