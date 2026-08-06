import Foundation

enum APIConfig {
    static var baseURL: URL {
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["ONIKEIRI_API_BASE_URL"],
           let url = URL(string: override) {
            return url
        }
        #endif

        let info = Bundle.main.infoDictionary
        let scheme = info?["ONIKEIRI_API_SCHEME"] as? String ?? "https"
        let host = info?["ONIKEIRI_API_HOST"] as? String ?? "onikeiri.appily.run"
        var components = URLComponents()
        components.scheme = scheme
        components.host = host

        if host.contains(":") {
            let parts = host.split(separator: ":", maxSplits: 1).map(String.init)
            components.host = parts.first
            components.port = parts.dropFirst().first.flatMap(Int.init)
        }

        guard let url = components.url else {
            preconditionFailure("Invalid OniKeiri API configuration")
        }
        return url
    }

    static let apiSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        return URLSession(configuration: configuration)
    }()
}
