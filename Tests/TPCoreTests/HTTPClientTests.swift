import Foundation
import Testing
@testable import TPCore

extension TPCoreTestsRoot {

@Suite struct HTTPClientTests {
    @Test func decodesSuccessfulResponse() async throws {
        StubURLProtocol.handler = { request in
            jsonResponse(request.url!, status: 200, json: #"{"status":"ok"}"#)
        }
        let client = HTTPClient(baseURL: URL(string: "https://example.invalid")!, session: makeStubSession())

        struct StatusResponse: Decodable { let status: String }
        let result: StatusResponse = try await client.get("/ping")

        #expect(result.status == "ok")
    }

    @Test func mapsServerErrorDetail() async throws {
        StubURLProtocol.handler = { request in
            jsonResponse(request.url!, status: 401, json: #"{"detail":"Credenciales inválidas"}"#)
        }
        let client = HTTPClient(baseURL: URL(string: "https://example.invalid")!, session: makeStubSession())

        struct Empty: Decodable {}
        do {
            let _: Empty = try await client.get("/secret")
            Issue.record("expected request to throw")
        } catch let error as APIError {
            #expect(error == .server(status: 401, message: "Credenciales inválidas"))
        }
    }

    @Test func encodesRequestBodyAsSnakeCase() async throws {
        StubURLProtocol.handler = { request in
            let body = try #require(requestBody(request))
            let decoded = try JSONDecoder().decode([String: String].self, from: body)
            #expect(decoded["display_name"] == "Ada")
            return jsonResponse(request.url!, status: 200, json: #"{"status":"ok"}"#)
        }
        let client = HTTPClient(baseURL: URL(string: "https://example.invalid")!, session: makeStubSession())

        struct Body: Encodable { let displayName: String }
        struct StatusResponse: Decodable { let status: String }
        let _: StatusResponse = try await client.post("/profile", body: Body(displayName: "Ada"))
    }
}

}
