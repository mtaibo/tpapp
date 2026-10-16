import Foundation
import Testing
@testable import TPCore

extension TPCoreTestsRoot {

@Suite struct AdminClientTests {
    private func makeClient() -> AdminClient {
        AdminClient(client: HTTPClient(baseURL: URL(string: "https://example.invalid")!, session: makeStubSession()))
    }

    private func query(_ request: URLRequest) -> [String: String] {
        guard let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems else { return [:] }
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    @Test func decodesSystemStatus() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url?.path == "/api/system")
            return jsonResponse(request.url!, status: 200, json: #"""
            {
                "hostname": "tphome",
                "uptime_seconds": 339201.07,
                "temperature_c": 46.85,
                "throttled": {"raw": "0x50000", "now": [], "since_boot": ["under_voltage", "soft_temp_limit"]},
                "cpu_percent": null,
                "cpu_count": 4,
                "load": [0.38, 0.17, 0.06],
                "memory": {"total": 8000, "used": 2000, "available": 6000, "swap_total": 100, "swap_used": 10},
                "disks": [{"name": "system", "mount": "/", "total": 100, "used": 30, "free": 70}]
            }
            """#)
        }

        let status = try await makeClient().systemStatus()

        #expect(status.hostname == "tphome")
        #expect(status.temperatureC == 46.85)
        #expect(status.throttled?.sinceBoot == ["under_voltage", "soft_temp_limit"])
        #expect(status.cpuPercent == nil)
        #expect(status.memory.swapUsed == 10)
        #expect(status.disks.map(\.mount) == ["/"])
    }

    @Test func decodesModulesWithContainers() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url?.path == "/api/modules")
            return jsonResponse(request.url!, status: 200, json: #"""
            {"modules": [
                {
                    "name": "tpstore", "path": "/home/u/tpstore", "installed": true,
                    "repo": {"branch": "main", "commit": "89b02b3", "subject": "fix: cursor", "date": "2026-10-16T12:00:00+02:00"},
                    "containers": [{
                        "name": "tpstore-api", "service": "store-api", "project": "tpstore", "image": "tpstore-store-api",
                        "state": "running", "status": "Up 41 minutes", "health": null, "created_at": "2026-10-16 10:55:56 +0000 UTC"
                    }]
                },
                {"name": "tpadmin", "path": "/home/u/tpadmin", "installed": true, "repo": null, "containers": [], "service_state": "active"}
            ]}
            """#)
        }

        let modules = try await makeClient().modules()

        #expect(modules.map(\.name) == ["tpstore", "tpadmin"])
        #expect(modules[0].repo?.commit == "89b02b3")
        #expect(modules[0].containers.first?.isRunning == true)
        #expect(modules[0].serviceState == nil)
        #expect(modules[1].serviceState == "active")
    }

    @Test func requestsLogsWithTail() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url?.path == "/api/containers/tpstore-api/logs")
            #expect(self.query(request)["tail"] == "50")
            return jsonResponse(request.url!, status: 200, json: #"{"name": "tpstore-api", "lines": ["a", "b"]}"#)
        }

        let lines = try await makeClient().logs(container: "tpstore-api", tail: 50)

        #expect(lines == ["a", "b"])
    }

    @Test func performsContainerAction() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url?.path == "/api/containers/tpstore-api/restart")
            #expect(request.httpMethod == "POST")
            return jsonResponse(request.url!, status: 200, json: #"{"name": "tpstore-api", "action": "restart", "ok": true}"#)
        }

        try await makeClient().perform(.restart, container: "tpstore-api")
    }

    @Test func surfacesRefusedStopAsServerError() async throws {
        StubURLProtocol.handler = { request in
            jsonResponse(request.url!, status: 403, json: #"{"detail": "gateway can't be stopped from here"}"#)
        }

        do {
            try await makeClient().perform(.stop, container: "gateway")
            Issue.record("expected request to throw")
        } catch let error as APIError {
            #expect(error == .server(status: 403, message: "gateway can't be stopped from here"))
        }
    }

    @Test func startsDeployForOneService() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url?.path == "/api/modules/tpstore/deploy")
            #expect(request.httpMethod == "POST")
            #expect(self.query(request)["service"] == "store-api")
            return jsonResponse(request.url!, status: 200, json: #"""
            {"id": "abc123", "title": "Deploy tpstore (store-api)", "status": "running", "output": "$ git pull\n", "started_at": 1792150000.5, "finished_at": null}
            """#)
        }

        let job = try await makeClient().deploy(module: "tpstore", service: "store-api")

        #expect(job.id == "abc123")
        #expect(job.status == .running)
        #expect(job.finishedAt == nil)
    }

    @Test func decodesClaudeSessions() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url?.path == "/api/claude/sessions")
            return jsonResponse(request.url!, status: 200, json: #"""
            {
                "sessions": [
                    {"name": "rc", "directory": "/home/u/workspace", "created_at": 1792144961,
                     "url": "https://claude.ai/code?environment=env_1", "state": "connected", "is_primary": true, "managed": false},
                    {"name": "claude-tpstore", "directory": "/home/u/workspace/tpstore", "created_at": null,
                     "url": null, "state": "needs_attention", "is_primary": false, "managed": true},
                    {"name": "claude-x", "directory": "/home/u/workspace/x", "created_at": null,
                     "url": null, "state": "something_new", "is_primary": false, "managed": true}
                ],
                "directories": ["/home/u/workspace", "/home/u/workspace/tpstore"]
            }
            """#)
        }

        let list = try await makeClient().claudeSessions()

        #expect(list.sessions.map(\.state) == [.connected, .needsAttention, .starting])
        #expect(list.sessions[0].isPrimary)
        #expect(list.directories.count == 2)
    }

    @Test func startsClaudeSessionInDirectory() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url?.path == "/api/claude/sessions")
            #expect(request.httpMethod == "POST")
            let body = try #require(requestBody(request))
            let decoded = try JSONDecoder().decode([String: String].self, from: body)
            #expect(decoded["directory"] == "/home/u/workspace/tpstore")
            return jsonResponse(request.url!, status: 200, json: #"""
            {"name": "claude-tpstore", "directory": "/home/u/workspace/tpstore", "created_at": null,
             "url": "https://claude.ai/code?environment=env_2", "state": "connected", "is_primary": false, "managed": true}
            """#)
        }

        let session = try await makeClient().startClaudeSession(directory: "/home/u/workspace/tpstore")

        #expect(session.url == "https://claude.ai/code?environment=env_2")
    }

    @Test func stopsClaudeSession() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url?.path == "/api/claude/sessions/claude-tpstore")
            #expect(request.httpMethod == "DELETE")
            return jsonResponse(request.url!, status: 200, json: #"{"name": "claude-tpstore", "stopped": true}"#)
        }

        try await makeClient().stopClaudeSession(name: "claude-tpstore")
    }
}

}
