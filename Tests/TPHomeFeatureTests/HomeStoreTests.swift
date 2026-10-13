import Foundation
import Testing
import TPCore
@testable import TPHomeFeature

@MainActor
@Suite struct HomeStoreTests {
    private func makeStore() -> HomeStore {
        HomeStore(
            client: HomeClient(client: HTTPClient(baseURL: URL(string: "https://example.invalid")!)),
            wsClient: HomeWebSocketClient(url: URL(string: "wss://example.invalid/api/ws")!)
        )
    }

    @Test func deviceStateUpdatesPositionWithoutTouchingOnline() {
        let store = makeStore()
        store.blinds = [
            "blind-1": Blind(
                id: "blind-1",
                name: "Salon",
                map: BlindMap(x: 0, y: 0, width: 10, height: 20),
                prefs: BlindPrefs(upTime: 1, downTime: 1, downPos: 0, invertedRelays: false),
                state: BlindState(position: 10, motorState: 0),
                connection: DeviceConnection(online: true, lastSeen: nil)
            )
        ]

        store.apply(.deviceState(id: "blind-1", position: 42, motorState: 2))

        #expect(store.blinds["blind-1"]?.state == BlindState(position: 42, motorState: 2))
        #expect(store.blinds["blind-1"]?.connection?.online == true)
    }

    @Test func deviceOnlineUpdatesOnlineWithoutTouchingPosition() {
        let store = makeStore()
        store.blinds = [
            "blind-1": Blind(
                id: "blind-1",
                name: "Salon",
                map: BlindMap(x: 0, y: 0, width: 10, height: 20),
                prefs: BlindPrefs(upTime: 1, downTime: 1, downPos: 0, invertedRelays: false),
                state: BlindState(position: 10, motorState: 0),
                connection: DeviceConnection(online: false, lastSeen: nil)
            )
        ]

        store.apply(.deviceOnline(id: "blind-1"))

        #expect(store.blinds["blind-1"]?.connection?.online == true)
        #expect(store.blinds["blind-1"]?.state == BlindState(position: 10, motorState: 0))
    }

    @Test func deviceOfflineUpdatesLightOnlineState() {
        let store = makeStore()
        store.lights = [
            "light-1": Light(
                id: "light-1",
                name: "Cocina",
                map: LightMap(x: 0, y: 0),
                state: LightState(on: true),
                connection: DeviceConnection(online: true, lastSeen: nil)
            )
        ]

        store.apply(.deviceOffline(id: "light-1"))

        #expect(store.lights["light-1"]?.connection?.online == false)
        #expect(store.lights["light-1"]?.state == LightState(on: true))
    }
}
