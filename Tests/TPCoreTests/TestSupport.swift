import Foundation
@testable import TPCore

final class StubURLProtocol: URLProtocol {
    /// Serialized tests guarantee exclusive access; see TPCoreTestsRoot.
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

func makeStubSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    return URLSession(configuration: config)
}

func jsonResponse(_ url: URL, status: Int, json: String) -> (HTTPURLResponse, Data) {
    let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
    return (response, Data(json.utf8))
}

/// URLSession replaces `httpBody` with `httpBodyStream` before handing the request to a custom `URLProtocol`.
func requestBody(_ request: URLRequest) -> Data? {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }
    var data = Data()
    let bufferSize = 4096
    var buffer = [UInt8](repeating: 0, count: bufferSize)
    while stream.hasBytesAvailable {
        let read = stream.read(&buffer, maxLength: bufferSize)
        if read <= 0 { break }
        data.append(buffer, count: read)
    }
    return data
}

final class FakeSessionCookieStore: SessionCookieStore {
    nonisolated(unsafe) var hasSessionCookie: Bool
    private(set) nonisolated(unsafe) var clearCallCount = 0

    init(hasSessionCookie: Bool = false) {
        self.hasSessionCookie = hasSessionCookie
    }

    func clear() {
        clearCallCount += 1
        hasSessionCookie = false
    }
}
