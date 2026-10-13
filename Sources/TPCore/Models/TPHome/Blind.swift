public struct Blind: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let map: BlindMap
    public let prefs: BlindPrefs
    public var state: BlindState?
    public var connection: DeviceConnection?

    public init(id: String, name: String, map: BlindMap, prefs: BlindPrefs, state: BlindState?, connection: DeviceConnection?) {
        self.id = id
        self.name = name
        self.map = map
        self.prefs = prefs
        self.state = state
        self.connection = connection
    }
}
