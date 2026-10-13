import Foundation
import Testing
@testable import TPCore

extension TPCoreTestsRoot {

@Suite struct HomeClientTests {
    private func makeClient() -> HomeClient {
        HomeClient(client: HTTPClient(baseURL: URL(string: "https://example.invalid")!, session: makeStubSession()))
    }

    @Test func fetchesBlinds() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url?.path == "/api/devices/blinds")
            #expect(request.httpMethod == "GET")
            return jsonResponse(request.url!, status: 200, json: #"""
            [
                {
                    "id": "blind-1",
                    "name": "Salon",
                    "map": {"x": 10, "y": 20, "width": 30, "height": 80},
                    "prefs": {"up_time": 12000, "down_time": 11000, "down_pos": 0, "inverted_relays": false},
                    "state": {"position": 50, "motor_state": 0},
                    "connection": {"online": true, "last_seen": "2026-01-01 12:34:56.789012"}
                }
            ]
            """#)
        }

        let blinds = try await makeClient().blinds()

        #expect(blinds == [
            Blind(
                id: "blind-1",
                name: "Salon",
                map: BlindMap(x: 10, y: 20, width: 30, height: 80),
                prefs: BlindPrefs(upTime: 12000, downTime: 11000, downPos: 0, invertedRelays: false),
                state: BlindState(position: 50, motorState: 0),
                connection: DeviceConnection(online: true, lastSeen: "2026-01-01 12:34:56.789012")
            )
        ])
    }

    @Test func fetchesLights() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url?.path == "/api/devices/lights")
            #expect(request.httpMethod == "GET")
            return jsonResponse(request.url!, status: 200, json: #"""
            [
                {
                    "id": "light-1",
                    "name": "Cocina",
                    "map": {"x": 5, "y": 6},
                    "state": {"on": true},
                    "connection": {"online": false, "last_seen": null}
                }
            ]
            """#)
        }

        let lights = try await makeClient().lights()

        #expect(lights == [
            Light(
                id: "light-1",
                name: "Cocina",
                map: LightMap(x: 5, y: 6),
                state: LightState(on: true),
                connection: DeviceConnection(online: false, lastSeen: nil)
            )
        ])
    }

    @Test func fetchesMapConfigUnharmedBySnakeCaseConversion() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url?.path == "/api/config/map")
            return jsonResponse(request.url!, status: 200, json: #"""
            {
                "viewBox": "0 0 400 300",
                "rooms": [{"id": "salon", "x": 0, "y": 0, "w": 200, "h": 150}],
                "labels": [{"x": 100, "y": 75, "text": "Salon"}],
                "doors": [{"x1": 190, "y1": 50, "x2": 200, "y2": 50}]
            }
            """#)
        }

        let config = try await makeClient().mapConfig()

        #expect(config == MapConfig(
            viewBox: "0 0 400 300",
            rooms: [MapConfig.Room(id: "salon", x: 0, y: 0, w: 200, h: 150)],
            labels: [MapConfig.Label(x: 100, y: 75, text: "Salon")],
            doors: [MapConfig.Door(x1: 190, y1: 50, x2: 200, y2: 50)]
        ))
    }

    @Test func sendsUpCommand() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url?.path == "/api/commands/blind-1/up")
            #expect(request.httpMethod == "POST")
            return jsonResponse(request.url!, status: 200, json: "{}")
        }

        try await makeClient().up("blind-1")
    }

    @Test func sendsDownCommand() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url?.path == "/api/commands/blind-1/down")
            #expect(request.httpMethod == "POST")
            return jsonResponse(request.url!, status: 200, json: "{}")
        }

        try await makeClient().down("blind-1")
    }

    @Test func sendsStopCommand() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url?.path == "/api/commands/blind-1/stop")
            #expect(request.httpMethod == "POST")
            return jsonResponse(request.url!, status: 200, json: "{}")
        }

        try await makeClient().stop("blind-1")
    }

    @Test func sendsSetCommand() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url?.path == "/api/commands/blind-1/set/42")
            #expect(request.httpMethod == "POST")
            return jsonResponse(request.url!, status: 200, json: "{}")
        }

        try await makeClient().set("blind-1", position: 42)
    }
}

}
