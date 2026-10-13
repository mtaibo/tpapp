public struct MapConfig: Decodable, Equatable, Sendable {
    public struct Room: Decodable, Equatable, Sendable, Identifiable {
        public let id: String
        public let x: Double
        public let y: Double
        public let w: Double
        public let h: Double
    }

    public struct Label: Decodable, Equatable, Sendable {
        public let x: Double
        public let y: Double
        public let text: String
    }

    public struct Door: Decodable, Equatable, Sendable {
        public let x1: Double
        public let y1: Double
        public let x2: Double
        public let y2: Double
    }

    public let viewBox: String
    public let rooms: [Room]
    public let labels: [Label]
    public let doors: [Door]
}
