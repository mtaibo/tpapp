public struct BlindPrefs: Decodable, Equatable, Sendable {
    public let upTime: Int
    public let downTime: Int
    public let downPos: Int
    public let invertedRelays: Bool

    public init(upTime: Int, downTime: Int, downPos: Int, invertedRelays: Bool) {
        self.upTime = upTime
        self.downTime = downTime
        self.downPos = downPos
        self.invertedRelays = invertedRelays
    }
}
