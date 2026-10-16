public struct ClaudeSession: Decodable, Equatable, Sendable, Identifiable {
    public enum State: String, Decodable, Sendable {
        case starting, connecting, connected, disconnected
        /// Waiting on a prompt in the terminal, e.g. the first-run folder trust question.
        case needsAttention = "needs_attention"

        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = State(rawValue: raw) ?? .starting
        }
    }

    /// tmux session name.
    public let name: String
    public let directory: String
    public let createdAt: Int?
    /// Where to continue this session: claude.ai/code or the Claude app.
    public let url: String?
    public let state: State
    /// The session this panel itself was set up from — stopping it drops that conversation.
    public let isPrimary: Bool
    /// Started from this panel (as opposed to by hand in a terminal).
    public let managed: Bool

    public var id: String { name }
}

public struct ClaudeSessionList: Decodable, Equatable, Sendable {
    public let sessions: [ClaudeSession]
    /// Directories a new session may be started in.
    public let directories: [String]
}
