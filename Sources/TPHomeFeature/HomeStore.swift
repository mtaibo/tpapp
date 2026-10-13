import Foundation
import TPCore

@MainActor
public final class HomeStore: ObservableObject {
    @Published public internal(set) var blinds: [String: Blind] = [:]
    @Published public internal(set) var lights: [String: Light] = [:]
    @Published public private(set) var mapConfig: MapConfig?
    @Published public private(set) var isLoading = false
    @Published public private(set) var loadError: String?

    private let client: HomeClient
    private let wsClient: HomeWebSocketClient
    private var eventTask: Task<Void, Never>?

    public init(client: HomeClient, wsClient: HomeWebSocketClient) {
        self.client = client
        self.wsClient = wsClient
    }

    /// Call once at app launch; the socket stays live across tab switches, mirroring `App.vue`.
    public func start() async {
        await refresh()
        guard eventTask == nil else { return }
        eventTask = Task { [weak self] in
            guard let self else { return }
            for await event in self.wsClient.events() {
                self.apply(event)
            }
        }
    }

    public func refresh() async {
        isLoading = true
        loadError = nil
        do {
            async let fetchedBlinds = client.blinds()
            async let fetchedLights = client.lights()
            async let fetchedMap = client.mapConfig()
            let (blindsResult, lightsResult, mapResult) = try await (fetchedBlinds, fetchedLights, fetchedMap)
            blinds = Dictionary(uniqueKeysWithValues: blindsResult.map { ($0.id, $0) })
            lights = Dictionary(uniqueKeysWithValues: lightsResult.map { ($0.id, $0) })
            mapConfig = mapResult
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    func apply(_ event: HomeEvent) {
        switch event {
        case .deviceOnline(let id):
            setOnline(id: id, online: true)
        case .deviceOffline(let id):
            setOnline(id: id, online: false)
        case .deviceState(let id, let position, let motorState):
            blinds[id]?.state = BlindState(position: position, motorState: motorState)
        }
    }

    private func setOnline(id: String, online: Bool) {
        if blinds[id] != nil {
            blinds[id]?.connection = DeviceConnection(online: online, lastSeen: blinds[id]?.connection?.lastSeen)
        }
        if lights[id] != nil {
            lights[id]?.connection = DeviceConnection(online: online, lastSeen: lights[id]?.connection?.lastSeen)
        }
    }

    public func sendUp(_ id: String) async {
        try? await client.up(id)
    }

    public func sendDown(_ id: String) async {
        try? await client.down(id)
    }

    public func sendStop(_ id: String) async {
        try? await client.stop(id)
    }

    public func sendSet(_ id: String, position: Int) async {
        try? await client.set(id, position: position)
    }
}
