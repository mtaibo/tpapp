public struct Light: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let map: LightMap
    public var state: LightState?
    public var connection: DeviceConnection?

    public init(id: String, name: String, map: LightMap, state: LightState?, connection: DeviceConnection?) {
        self.id = id
        self.name = name
        self.map = map
        self.state = state
        self.connection = connection
    }
}
