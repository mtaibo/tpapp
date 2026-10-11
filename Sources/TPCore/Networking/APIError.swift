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
        case .server(_, let detail): return detail ?? "Error inesperado"
        case .transport(let description): return "No se pudo conectar: \(description)"
        case .decoding, .invalidResponse: return "Error inesperado"
        case .sessionExpired: return "Tu sesión ha caducado"
        }
    }
}

public func apiErrorMessage(_ error: Error) -> String {
    (error as? APIError)?.displayMessage ?? "Error inesperado"
}
