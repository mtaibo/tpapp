import Foundation

public enum APIError: Error, Equatable, Sendable {
    case invalidResponse
    case server(status: Int, message: String?)
    case decoding
    case transport(String)
}
