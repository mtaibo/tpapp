import Foundation

public enum APIError: Error, Equatable, Sendable {
    case invalidResponse
    case server(status: Int, message: String?)
    case decoding
    case transport(String)
    case sessionExpired
}

public extension APIError {
    var displayMessage: String {
        switch self {
        case .server(_, let detail): return detail ?? "Unexpected error"
        case .transport(let description): return "Couldn't connect: \(description)"
        case .decoding, .invalidResponse: return "Unexpected error"
        case .sessionExpired: return "Your session has expired"
        }
    }
}

public func apiErrorMessage(_ error: Error) -> String {
    (error as? APIError)?.displayMessage ?? "Unexpected error"
}
