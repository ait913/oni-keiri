import Foundation
import Observation

@MainActor
@Observable
final class AuthStore {
    enum State: Equatable {
        case unknown
        case signedOut
        case signedIn
    }

    private(set) var state: State = .unknown
    private(set) var me: MeResponse?

    @ObservationIgnored private let keychain: KeychainStore
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private let decoder: JSONDecoder
    @ObservationIgnored private let encoder: JSONEncoder
    @ObservationIgnored var onLocalSignOut: (() -> Void)?
    @ObservationIgnored private var storedToken: String?

    var token: String? { storedToken }

    init(keychain: KeychainStore = KeychainStore(), session: URLSession = APIConfig.apiSession) {
        self.keychain = keychain
        self.session = session
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
        self.storedToken = try? keychain.load()

        #if DEBUG
        if let token = ProcessInfo.processInfo.environment["ONIKEIRI_UI_TEST_BEARER_TOKEN"], !token.isEmpty {
            try? keychain.save(token: token)
            self.storedToken = token
        }
        #endif
    }

    func bootstrap() async {
        guard let token = (try? keychain.load()) ?? storedToken else {
            storedToken = nil
            me = nil
            state = .signedOut
            return
        }

        storedToken = token
        do {
            me = try await fetchMe(token: token)
            state = .signedIn
        } catch APIError.unauthorized {
            try? keychain.delete()
            storedToken = nil
            me = nil
            state = .signedOut
        } catch {
            state = .signedOut
        }
    }

    func signInWithApple(idToken: String) async throws {
        let body = SocialIDTokenSignInBody(provider: "apple", idToken: IDTokenBody(token: idToken))
        let response = try await authRequest(path: "/api/auth/sign-in/social", body: body)
        guard let token = response.value(forHTTPHeaderField: "set-auth-token"), !token.isEmpty else {
            throw APIError.api(status: response.statusCode, code: "TOKEN_MISSING", message: "Authentication token was not returned.")
        }
        try keychain.save(token: token)
        storedToken = token
        me = try await fetchMe(token: token)
        state = .signedIn
    }

    func handleUnauthorized() {
        try? keychain.delete()
        storedToken = nil
        me = nil
        onLocalSignOut?()
        state = .signedOut
    }

    func signOut() async {
        if storedToken != nil {
            do {
                _ = try await authRequestWithData(path: "/api/auth/sign-out", body: EmptyBody(), requiresAuth: true)
            } catch {
                // Local sign-out must complete even if the server request fails.
            }
        }
        try? keychain.delete()
        storedToken = nil
        me = nil
        state = .signedOut
    }

    func refreshMe() async {
        guard let token else {
            state = .signedOut
            return
        }
        do {
            me = try await fetchMe(token: token)
            state = .signedIn
        } catch APIError.unauthorized {
            handleUnauthorized()
        } catch {
            // Keep the current auth state on transient refresh failures.
        }
    }

    private func fetchMe(token: String) async throws -> MeResponse {
        var request = URLRequest(url: APIConfig.baseURL.appending(path: "api/me"))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.transport("Invalid HTTP response")
        }
        if httpResponse.statusCode == 401 {
            throw APIError.unauthorized
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw decodeHTTPError(data: data, status: httpResponse.statusCode)
        }
        do {
            return try decoder.decode(MeResponse.self, from: data)
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }

    private func authRequest(path: String, body: Encodable) async throws -> HTTPURLResponse {
        let (data, response) = try await authRequestWithData(path: path, body: body)
        guard (200...299).contains(response.statusCode) else {
            throw decodeHTTPError(data: data, status: response.statusCode)
        }
        return response
    }

    private func authRequestWithData(path: String, body: Encodable, requiresAuth: Bool = false) async throws -> (Data, HTTPURLResponse) {
        let cleanPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var request = URLRequest(url: APIConfig.baseURL.appending(path: cleanPath))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if requiresAuth, let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try encoder.encode(AuthAnyEncodable(body))

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.transport("Invalid HTTP response")
        }
        return (data, httpResponse)
    }

    private func decodeHTTPError(data: Data, status: Int) -> APIError {
        if status == 401 {
            return .unauthorized
        }
        if let errorResponse = try? decoder.decode(ErrorResponse.self, from: data) {
            return .api(status: status, code: errorResponse.error.code, message: errorResponse.error.message)
        }
        return .http(status: status)
    }
}

private struct IDTokenBody: Encodable {
    let token: String
}

private struct SocialIDTokenSignInBody: Encodable {
    let provider: String
    let idToken: IDTokenBody
}

private struct EmptyBody: Encodable {}

private struct AuthAnyEncodable: Encodable {
    private let encodeValue: (Encoder) throws -> Void

    init(_ value: Encodable) {
        self.encodeValue = value.encode(to:)
    }

    func encode(to encoder: Encoder) throws {
        try encodeValue(encoder)
    }
}
