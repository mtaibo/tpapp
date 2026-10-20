import Foundation

extension Notification.Name {
    /// Posted whenever a request is turned back by the gateway's login redirect, i.e. the
    /// session cookie is no longer valid. AuthSession observes this to drop back to signed-out.
    public static let tpSessionExpired = Notification.Name("TPSessionExpired")
}

/// The gateway's forward_auth sends a 302 to the login page when the session is gone. Following
/// it would hand back login HTML where JSON was expected, so every redirect is blocked here and
/// surfaced as `.sessionExpired` instead.
private final class RedirectBlockingDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

/// Blocks redirects like `RedirectBlockingDelegate`, and also hangs the download task's own
/// progress under a caller's `Progress`, so whoever waits on the file (e.g. another app a file
/// was dragged to) sees it advance — and can cancel it.
private final class FileDownloadDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let progress: Progress?

    init(progress: Progress?) {
        self.progress = progress
    }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        guard let progress else { return }
        progress.addChild(task.progress, withPendingUnitCount: progress.totalUnitCount)
        progress.cancellationHandler = { [weak task] in task?.cancel() }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

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

    public func put<Body: Encodable, Response: Decodable>(_ path: String, body: Body) async throws -> Response {
        let data = try await execute(path: path, method: "PUT", query: [:], body: body)
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

    /// Raw binary GET streamed straight to a file instead of into memory, for big downloads.
    /// Returns a temporary file the caller must move or delete.
    public func downloadFile(_ path: String, query: [String: String] = [:], progress: Progress? = nil) async throws -> URL {
        let request = makeRequest(path: path, method: "GET", query: query, contentType: nil, body: nil)
        let fileURL: URL
        let response: URLResponse
        do {
            (fileURL, response) = try await session.download(for: request, delegate: FileDownloadDelegate(progress: progress))
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
        do {
            try Self.validate(response, data: { (try? Data(contentsOf: fileURL)) ?? Data() })
        } catch {
            try? FileManager.default.removeItem(at: fileURL)
            throw error
        }
        return fileURL
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
        let request = makeRequest(path: path, method: method, query: query, contentType: contentType, body: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request, delegate: RedirectBlockingDelegate())
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
        try Self.validate(response, data: { data })
        return data
    }

    private func makeRequest(path: String, method: String, query: [String: String], contentType: String?, body: Data?) -> URLRequest {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
            // URLComponents leaves "+" literal, but the server form-decodes it as a space — which
            // broke the photo cursor's "+00:00" offset and stopped pagination after page one.
            components.percentEncodedQuery = components.percentEncodedQuery?
                .replacingOccurrences(of: "+", with: "%2B")
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.clientPlatform, forHTTPHeaderField: "X-TP-Client")
        request.httpBody = body
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    /// `data` is only read for a failed response's error detail.
    private static func validate(_ response: URLResponse, data: () -> Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        if (300..<400).contains(http.statusCode) {
            NotificationCenter.default.post(name: .tpSessionExpired, object: nil)
            throw APIError.sessionExpired
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.server(status: http.statusCode, message: errorDetail(from: data()))
        }
    }

    #if os(iOS)
    private static let clientPlatform = "ios"
    #elseif os(macOS)
    private static let clientPlatform = "macos"
    #else
    private static let clientPlatform = "native"
    #endif

    private static func errorDetail(from data: Data) -> String? {
        struct ErrorBody: Decodable { let detail: String? }
        return try? JSONDecoder().decode(ErrorBody.self, from: data).detail
    }
}

private struct EmptyBody: Encodable {}
