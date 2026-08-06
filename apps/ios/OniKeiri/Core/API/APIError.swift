import Foundation

enum APIError: Error, Equatable {
    case unauthorized
    case api(status: Int, code: String, message: String)
    case http(status: Int)
    case transport(String)
    case decoding(String)
}

struct ErrorResponse: Codable {
    struct Inner: Codable {
        let code: String
        let message: String
    }

    let error: Inner
}
