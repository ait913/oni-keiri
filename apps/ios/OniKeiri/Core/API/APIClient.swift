import Foundation

@MainActor
final class APIClient {
    private let auth: AuthStore
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(auth: AuthStore, session: URLSession = APIConfig.apiSession) {
        self.auth = auth
        self.session = session
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    func home(month: String?) async throws -> HomeResponse {
        try await request("api/home", queryItems: optionalQuery(name: "month", value: month))
    }

    func entries(month: String) async throws -> EntriesResponse {
        try await request("api/entries", queryItems: [URLQueryItem(name: "month", value: month)])
    }

    func createEntry(_ body: CreateEntryBodyDto) async throws -> EntryDto {
        try await request("api/entries", method: "POST", body: body)
    }

    func createSalary(_ body: CreateSalaryBodyDto) async throws -> SalaryResponseDto {
        try await request("api/entries/salary", method: "POST", body: body)
    }

    func updateEntry(id: String, _ body: UpdateEntryBodyDto) async throws -> EntryDto {
        try await request("api/entries/\(id)", method: "PATCH", body: body)
    }

    func deleteEntry(id: String) async throws {
        try await requestEmpty("api/entries/\(id)", method: "DELETE")
    }

    func cards() async throws -> [CardDto] {
        let response: CardsResponse = try await request("api/cards")
        return response.cards
    }

    func createCard(_ body: CardFormBodyDto) async throws -> CardDto {
        try await request("api/cards", method: "POST", body: body)
    }

    func updateCard(id: String, _ body: CardUpdateBodyDto) async throws -> CardDto {
        try await request("api/cards/\(id)", method: "PATCH", body: body)
    }

    func deleteCard(id: String) async throws {
        try await requestEmpty("api/cards/\(id)", method: "DELETE")
    }

    func cardDetail(id: String, months: Int) async throws -> CardDetailResponse {
        try await request("api/cards/\(id)/detail", queryItems: [URLQueryItem(name: "months", value: "\(months)")])
    }

    func recurringRules(direction: RuleDirection?) async throws -> [RecurringRuleDto] {
        let response: RecurringRulesResponse = try await request("api/recurring-rules", queryItems: optionalQuery(name: "direction", value: direction?.rawValue))
        return response.rules
    }

    func createRule(_ body: RuleFormBodyDto) async throws -> RecurringRuleDto {
        try await request("api/recurring-rules", method: "POST", body: body)
    }

    func updateRule(id: String, _ body: RuleUpdateBodyDto) async throws -> RecurringRuleDto {
        try await request("api/recurring-rules/\(id)", method: "PATCH", body: body)
    }

    func deleteRule(id: String) async throws {
        try await requestEmpty("api/recurring-rules/\(id)", method: "DELETE")
    }

    func calendar(month: String) async throws -> CalendarResponse {
        try await request("api/calendar", queryItems: [URLQueryItem(name: "month", value: month)])
    }

    func taxEstimate(year: Int?) async throws -> TaxEstimateResponse {
        try await request("api/tax/estimate", queryItems: optionalQuery(name: "year", value: year.map(String.init)))
    }

    func settings() async throws -> SettingsDto {
        try await request("api/settings")
    }

    func putSettings(_ body: SettingsDto) async throws -> SettingsDto {
        try await request("api/settings", method: "PUT", body: body)
    }

    func deleteAccount() async throws {
        try await requestEmpty("api/me", method: "DELETE")
        auth.handleUnauthorized()
    }

    private func request<Response: Decodable>(_ path: String, method: String = "GET", queryItems: [URLQueryItem] = [], body: Encodable? = nil) async throws -> Response {
        let data = try await requestData(path, method: method, queryItems: queryItems, body: body)
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }

    private func requestEmpty(_ path: String, method: String, queryItems: [URLQueryItem] = [], body: Encodable? = nil) async throws {
        _ = try await requestData(path, method: method, queryItems: queryItems, body: body)
    }

    private func requestData(_ path: String, method: String, queryItems: [URLQueryItem], body: Encodable?) async throws -> Data {
        var request = URLRequest(url: url(path: path, queryItems: queryItems))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = auth.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(AnyEncodable(body))
        }

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
        return data
    }

    private func url(path: String, queryItems: [URLQueryItem]) -> URL {
        let cleanPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var components = URLComponents(url: APIConfig.baseURL.appending(path: cleanPath), resolvingAgainstBaseURL: false)!
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.url!
    }

    private func optionalQuery(name: String, value: String?) -> [URLQueryItem] {
        value.map { [URLQueryItem(name: name, value: $0)] } ?? []
    }

    private func decodeHTTPError(data: Data, status: Int) -> APIError {
        if let errorResponse = try? decoder.decode(ErrorResponse.self, from: data) {
            return .api(status: status, code: errorResponse.error.code, message: errorResponse.error.message)
        }
        return .http(status: status)
    }
}

private struct CardsResponse: Decodable {
    let cards: [CardDto]
}

private struct RecurringRulesResponse: Decodable {
    let rules: [RecurringRuleDto]
}

private struct AnyEncodable: Encodable {
    private let encodeValue: (Encoder) throws -> Void

    init(_ value: Encodable) {
        self.encodeValue = value.encode(to:)
    }

    func encode(to encoder: Encoder) throws {
        try encodeValue(encoder)
    }
}
