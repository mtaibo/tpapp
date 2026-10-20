import Foundation
import Testing
@testable import TPCore

extension TPCoreTestsRoot {

@Suite struct StoreClientTests {
    private func makeClient() -> StoreClient {
        StoreClient(client: HTTPClient(baseURL: URL(string: "https://example.invalid")!, session: makeStubSession()))
    }

    private func query(_ request: URLRequest) -> [String: String] {
        guard let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems else { return [:] }
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    @Test func listsDirectory() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url?.path == "/api/files/list")
            #expect(request.httpMethod == "GET")
            #expect(self.query(request)["path"] == "docs")
            #expect(self.query(request)["location"] == "external")
            return jsonResponse(request.url!, status: 200, json: #"""
            {
                "path": "docs",
                "entries": [
                    {"name": "a.txt", "type": "file", "size": 10, "modified": 1700000000.0, "icon_name": null, "upload_id": null, "bytes_received": null},
                    {"name": "sub", "type": "directory", "size": null, "modified": 1700000001.0, "icon_name": "📁", "upload_id": null, "bytes_received": null}
                ]
            }
            """#)
        }

        let listing = try await makeClient().listDirectory(path: "docs")

        #expect(listing.path == "docs")
        #expect(listing.entries == [
            FileEntry(name: "a.txt", type: .file, size: 10, modified: 1700000000.0, iconName: nil, uploadId: nil, bytesReceived: nil),
            FileEntry(name: "sub", type: .directory, size: nil, modified: 1700000001.0, iconName: "📁", uploadId: nil, bytesReceived: nil)
        ])
    }

    @Test func fetchesDiskInfo() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url?.path == "/api/files/disk")
            return jsonResponse(request.url!, status: 200, json: #"{"total":1000,"used":400,"free":600}"#)
        }

        let disk = try await makeClient().diskInfo()

        #expect(disk == DiskInfo(total: 1000, used: 400, free: 600))
    }

    @Test func createsFolder() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url?.path == "/api/files/mkdir")
            #expect(request.httpMethod == "POST")
            let body = try #require(requestBody(request))
            let decoded = try JSONDecoder().decode([String: String].self, from: body)
            #expect(decoded["path"] == "docs/new")
            #expect(decoded["location"] == "external")
            return jsonResponse(request.url!, status: 200, json: #"{"created":"docs/new"}"#)
        }

        try await makeClient().createFolder(path: "docs/new")
    }

    @Test func renamesEntry() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url?.path == "/api/files/rename")
            let body = try #require(requestBody(request))
            let decoded = try JSONDecoder().decode([String: String].self, from: body)
            #expect(decoded["path"] == "docs/a.txt")
            #expect(decoded["new_name"] == "b.txt")
            return jsonResponse(request.url!, status: 200, json: #"{"renamed":"docs/b.txt"}"#)
        }

        try await makeClient().rename(path: "docs/a.txt", newName: "b.txt")
    }

    @Test func movesEntry() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url?.path == "/api/files/move")
            let body = try #require(requestBody(request))
            let decoded = try JSONDecoder().decode([String: String].self, from: body)
            #expect(decoded["path"] == "docs/a.txt")
            #expect(decoded["dest_dir"] == "archive")
            return jsonResponse(request.url!, status: 200, json: #"{"moved":"archive/a.txt"}"#)
        }

        try await makeClient().move(path: "docs/a.txt", destDir: "archive")
    }

    @Test func deletesEntry() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url?.path == "/api/files")
            #expect(request.httpMethod == "DELETE")
            #expect(self.query(request)["path"] == "docs/a.txt")
            return jsonResponse(request.url!, status: 200, json: #"{"deleted":"docs/a.txt"}"#)
        }

        try await makeClient().delete(path: "docs/a.txt")
    }

    @Test func downloadsRawBytes() async throws {
        let payload = Data("hello world".utf8)
        StubURLProtocol.handler = { request in
            #expect(request.url?.path == "/api/files/download")
            #expect(self.query(request)["path"] == "docs/a.txt")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/octet-stream"])!
            return (response, payload)
        }

        let data = try await makeClient().download(path: "docs/a.txt")

        #expect(data == payload)
    }

    @Test func streamsDownloadToFileWithProgress() async throws {
        let payload = Data(repeating: 7, count: 64 * 1024)
        StubURLProtocol.handler = { request in
            #expect(request.url?.path == "/api/files/download-zip")
            #expect(self.query(request)["path"] == "docs")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Length": "\(payload.count)"])!
            return (response, payload)
        }

        let progress = Progress(totalUnitCount: 100)
        let file = try await makeClient().downloadFile(path: "docs", asZip: true, progress: progress)
        defer { try? FileManager.default.removeItem(at: file) }

        #expect(try Data(contentsOf: file) == payload)
        #expect(progress.fractionCompleted == 1)
    }

    @Test func failedFileDownloadThrowsAndLeavesNoFile() async throws {
        StubURLProtocol.handler = { request in
            jsonResponse(request.url!, status: 404, json: #"{"detail":"Source not found"}"#)
        }

        await #expect(throws: APIError.server(status: 404, message: "Source not found")) {
            try await makeClient().downloadFile(path: "missing.mov")
        }
    }

    @Test func uploadsFileAsMultipart() async throws {
        let fileData = Data("file-contents".utf8)
        StubURLProtocol.handler = { request in
            #expect(request.url?.path == "/api/files/upload")
            #expect(self.query(request)["path"] == "docs")
            let contentType = try #require(request.value(forHTTPHeaderField: "Content-Type"))
            #expect(contentType.hasPrefix("multipart/form-data; boundary="))
            let body = try #require(requestBody(request))
            let bodyString = String(decoding: body, as: UTF8.self)
            #expect(bodyString.contains("name=\"files\"; filename=\"a.txt\""))
            #expect(bodyString.contains("file-contents"))
            return jsonResponse(request.url!, status: 200, json: #"{"uploaded":["a.txt"]}"#)
        }

        try await makeClient().upload(path: "docs", filename: "a.txt", data: fileData, mimeType: "text/plain")
    }

    @Test func listsShares() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url?.path == "/api/shares")
            return jsonResponse(request.url!, status: 200, json: #"""
            [
                {
                    "token": "abc123",
                    "url": "https://share.migueltaibo.com/abc123",
                    "location": "external",
                    "path": "docs/a.txt",
                    "hidden": false,
                    "has_password": true,
                    "editable": false,
                    "public": false,
                    "created_at": "2026-01-01T00:00:00Z",
                    "is_file": true
                }
            ]
            """#)
        }

        let shares = try await makeClient().shares()

        #expect(shares == [
            ShareLink(
                token: "abc123",
                url: "https://share.migueltaibo.com/abc123",
                location: .external,
                path: "docs/a.txt",
                hidden: false,
                hasPassword: true,
                editable: false,
                isPublic: false,
                createdAt: "2026-01-01T00:00:00Z",
                isFile: true
            )
        ])
    }

    @Test func createsShare() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url?.path == "/api/shares")
            #expect(request.httpMethod == "POST")
            let body = try #require(requestBody(request))
            struct Decoded: Decodable { let path: String; let location: String; let hidden: Bool }
            let decoded = try JSONDecoder().decode(Decoded.self, from: body)
            #expect(decoded.path == "docs/a.txt")
            #expect(decoded.location == "external")
            #expect(decoded.hidden == true)
            return jsonResponse(request.url!, status: 200, json: #"""
            {
                "token": "xyz",
                "url": "https://share.migueltaibo.com/xyz",
                "location": "external",
                "path": "docs/a.txt",
                "hidden": true,
                "has_password": false,
                "editable": false,
                "public": false,
                "created_at": "2026-01-01T00:00:00Z",
                "is_file": true
            }
            """#)
        }

        let share = try await makeClient().createShare(location: .external, path: "docs/a.txt", hidden: true)

        #expect(share.token == "xyz")
    }

    @Test func updatesShareWithRemappedPublicField() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url?.path == "/api/shares/xyz")
            #expect(request.httpMethod == "PATCH")
            let body = try #require(requestBody(request))
            let decoded = try JSONDecoder().decode([String: Bool].self, from: body)
            #expect(decoded["public"] == true)
            #expect(decoded["editable"] == nil)
            return jsonResponse(request.url!, status: 200, json: #"""
            {
                "token": "xyz",
                "url": "https://share.migueltaibo.com/xyz",
                "location": "external",
                "path": "docs/a.txt",
                "hidden": true,
                "has_password": false,
                "editable": false,
                "public": true,
                "created_at": "2026-01-01T00:00:00Z",
                "is_file": true
            }
            """#)
        }

        let share = try await makeClient().updateShare(token: "xyz", isPublic: true)

        #expect(share.isPublic == true)
    }

    @Test func deletesShare() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url?.path == "/api/shares/xyz")
            #expect(request.httpMethod == "DELETE")
            return jsonResponse(request.url!, status: 200, json: #"{"deleted":"xyz"}"#)
        }

        try await makeClient().deleteShare("xyz")
    }
}

}
