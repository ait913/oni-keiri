import Foundation
import Observation

@MainActor
@Observable
final class RefreshTicker {
    private(set) var tick = 0

    func bump() {
        tick += 1
    }
}

@MainActor
@Observable
final class AppEnvironment {
    let auth: AuthStore
    let api: APIClient
    let ticker: RefreshTicker

    init(auth: AuthStore = AuthStore(), ticker: RefreshTicker = RefreshTicker()) {
        self.auth = auth
        self.api = APIClient(auth: auth)
        self.ticker = ticker
    }
}
