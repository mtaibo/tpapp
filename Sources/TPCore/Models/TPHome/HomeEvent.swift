public enum HomeEvent: Equatable, Sendable {
    case deviceOnline(id: String)
    case deviceOffline(id: String)
    case deviceState(id: String, position: Int, motorState: Int)
}
