import Foundation

/// Push-only WebSocket stream for tphome device events. Matches the web client's `socket.js`:
/// flat 3-second reconnect delay on any drop, no backoff/jitter.
public final class HomeWebSocketClient: Sendable {
    private let url: URL
    private let session: URLSession

    public init(url: URL, session: URLSession = .shared) {
        self.url = url
        self.session = session
    }

    public func events() -> AsyncStream<HomeEvent> {
        AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    await Self.runConnection(url: url, session: session, continuation: continuation)
                    try? await Task.sleep(for: .seconds(3))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func runConnection(
        url: URL,
        session: URLSession,
        continuation: AsyncStream<HomeEvent>.Continuation
    ) async {
        let webSocketTask = session.webSocketTask(with: url)
        webSocketTask.resume()
        defer { webSocketTask.cancel(with: .goingAway, reason: nil) }

        while !Task.isCancelled {
            do {
                let message = try await webSocketTask.receive()
                guard case .string(let text) = message, let event = decode(text) else { continue }
                continuation.yield(event)
            } catch {
                return
            }
        }
    }

    /// Two-stage decode of the `{"event": str, "data": {...}}` envelope: peek `event` to know
    /// which shape `data` should be, then pull the fields that shape needs. Unknown events drop silently.
    static func decode(_ text: String) -> HomeEvent? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = object["event"] as? String,
              let payload = object["data"] as? [String: Any] else { return nil }

        switch event {
        case "device_online":
            guard let id = payload["id"] as? String else { return nil }
            return .deviceOnline(id: id)
        case "device_offline":
            guard let id = payload["id"] as? String else { return nil }
            return .deviceOffline(id: id)
        case "device_state":
            guard let id = payload["id"] as? String,
                  let state = payload["state"] as? [String: Any],
                  let position = state["position"] as? Int,
                  let motorState = state["motor_state"] as? Int else { return nil }
            return .deviceState(id: id, position: position, motorState: motorState)
        default:
            return nil
        }
    }
}
