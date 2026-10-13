public struct BlindState: Decodable, Equatable, Sendable {
    public var position: Int
    public var motorState: Int

    public init(position: Int, motorState: Int) {
        self.position = position
        self.motorState = motorState
    }

    public enum MotorState: Int, Sendable {
        case idle = 0
        case waiting = 1
        case moving = 2
        case stopping = 3
    }

    public var motor: MotorState { MotorState(rawValue: motorState) ?? .idle }
}
