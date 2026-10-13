public struct LightState: Decodable, Equatable, Sendable {
    public var on: Bool

    public init(on: Bool) {
        self.on = on
    }
}
