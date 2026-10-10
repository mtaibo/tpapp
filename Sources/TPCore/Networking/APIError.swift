import Foundation

public enum APIError: Error, Equatable, Sendable {
    case invalidResponse
    case server(status: Int, message: String?)
    case decoding
    case transport(String)
}

public extension APIError {
    var displayMessage: String {
        switch self {
        case .server(_, let detail): return detail ?? "Error inesperado"
        case .transport: return "No se pudo conectar"
        case .decoding, .invalidResponse: return "Error inesperado"
        }
    }
}

public func apiErrorMessage(_ error: Error) -> String {
    (error as? APIError)?.displayMessage ?? "Error inesperado"
}
