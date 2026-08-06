import Observation
import SwiftUI

struct SalaryListView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var viewModel = SalaryListViewModel()
    @State private var showCreate = false
    @State private var editingRule: RecurringRuleDto?

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.sectionGap) {
                switch viewModel.state {
                case .loading:
                    LoadingPlaceholderCard(height: 170)
                case .error:
                    ContentUnavailableView {
                        Label("給与を読み込めません", systemImage: "exclamationmark.triangle")
                    } actions: {
                        Button("再試行") { Task { await viewModel.load(api: environment.api, auth: environment.auth) } }
                    }
                case .loaded:
                    ForEach(viewModel.rules) { rule in
                        Button {
                            editingRule = rule
                        } label: {
                            RuleRow(rule: rule, cards: [], mode: .income)
                        }
                        .foregroundStyle(DS.Palette.text)
                    }
                    Button {
                        showCreate = true
                    } label: {
                        Text("+ 給与を追加")
                            .font(DS.Typo.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .overlay(Capsule().stroke(DS.Palette.line))
                    }
                    .foregroundStyle(DS.Palette.text)

                    Text("臨時収入・不定期の入金はホームの「収入」から都度追加できます。個人事業主では給与入力時に経費も同時に登録できます")
                        .font(DS.Typo.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
            }
            .padding(DS.Spacing.screenMargin)
        }
        .background(DS.Palette.bg)
        .navigationTitle("給与")
        .task(id: environment.ticker.tick) {
            await viewModel.load(api: environment.api, auth: environment.auth)
        }
        .sheet(isPresented: $showCreate) {
            RuleFormSheet(direction: .income, existing: nil, cards: []) { submission in
                await viewModel.submit(submission, api: environment.api, auth: environment.auth, ticker: environment.ticker)
            }
        }
        .sheet(item: $editingRule) { rule in
            RuleFormSheet(direction: .income, existing: rule, cards: []) { submission in
                await viewModel.submit(submission, api: environment.api, auth: environment.auth, ticker: environment.ticker)
            }
        }
    }
}

@MainActor
@Observable
final class SalaryListViewModel {
    enum State: Equatable { case loading, loaded, error }
    private(set) var state: State = .loading
    private(set) var rules: [RecurringRuleDto] = []

    func load(api: APIClient, auth: AuthStore) async {
        state = .loading
        do {
            rules = try await api.recurringRules(direction: .income)
                .sorted { ($0.dayOfMonth, $0.name) < ($1.dayOfMonth, $1.name) }
            state = .loaded
        } catch APIError.unauthorized {
            auth.handleUnauthorized()
        } catch {
            state = .error
        }
    }

    func submit(_ submission: RuleSubmission, api: APIClient, auth: AuthStore, ticker: RefreshTicker) async -> Bool {
        do {
            switch submission {
            case .create(let body):
                _ = try await api.createRule(body)
            case .update(let id, let body):
                _ = try await api.updateRule(id: id, body)
            case .delete(let id):
                try await api.deleteRule(id: id)
            }
            ticker.bump()
            return true
        } catch APIError.unauthorized {
            auth.handleUnauthorized()
            return false
        } catch {
            return false
        }
    }
}
