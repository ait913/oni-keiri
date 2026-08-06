import Observation
import SwiftUI

struct TaxView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var viewModel = TaxViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.sectionGap) {
                switch viewModel.state {
                case .loading:
                    LoadingPlaceholderCard(height: 260)
                case .guarded:
                    ContentUnavailableView {
                        Label("税金目安は個人事業主向けです", systemImage: "gearshape")
                    } description: {
                        Text("設定の働き方を「個人事業主」にすると、経費入力と税金目安を使えます。")
                    } actions: {
                        NavigationLink("設定を開く") {
                            SettingsView()
                        }
                    }
                case .error:
                    ContentUnavailableView {
                        Label("税金目安を読み込めません", systemImage: "exclamationmark.triangle")
                    } actions: {
                        Button("再試行") { Task { await viewModel.load(api: environment.api, auth: environment.auth) } }
                    }
                case .loaded(let estimate):
                    TaxHero(estimate: estimate)
                    TaxBreakdownCard(estimate: estimate)
                    Text("概算率による目安です。実際の納付額は確定申告で決まります")
                        .font(DS.Typo.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(DS.Spacing.screenMargin)
        }
        .background(DS.Palette.bg)
        .navigationTitle("税金目安")
        .task(id: environment.ticker.tick) {
            await viewModel.load(api: environment.api, auth: environment.auth)
        }
    }
}

@MainActor
@Observable
final class TaxViewModel {
    enum State: Equatable {
        case loading
        case guarded
        case loaded(TaxEstimateResponse)
        case error
    }

    private(set) var state: State = .loading

    func load(api: APIClient, auth: AuthStore) async {
        state = .loading
        do {
            let settings = try await api.settings()
            guard settings.employmentType == .freelance else {
                state = .guarded
                return
            }
            state = .loaded(try await api.taxEstimate(year: nil))
        } catch APIError.unauthorized {
            auth.handleUnauthorized()
        } catch {
            state = .error
        }
    }
}

private struct TaxHero: View {
    let estimate: TaxEstimateResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("毎月 取っておく目安")
                .font(DS.Typo.caption)
                .foregroundStyle(.white.opacity(0.62))
            Text(YenText.string(amount: estimate.monthlySetAside))
                .font(DS.Typo.displayS)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            HStack {
                SummaryMetricDark(title: "年間目安", value: YenText.string(amount: estimate.annualProjection))
                Spacer()
                SummaryMetricDark(title: "概算率", value: "\(Int((estimate.rate * 100).rounded()))%")
            }
        }
        .padding(20)
        .dsInkSurface()
    }
}

private struct SummaryMetricDark: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(DS.Typo.labelS)
                .foregroundStyle(.white.opacity(0.55))
            Text(value)
                .font(DS.Typo.amountM)
                .foregroundStyle(.white)
        }
    }
}

private struct TaxBreakdownCard: View {
    let estimate: TaxEstimateResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("今年の見込み (1月〜今日)")
                .font(DS.Typo.heading)
                .foregroundStyle(DS.Palette.textSub)
                .padding(.bottom, 4)
            row("事業収入", amount: estimate.businessIncomeYtd)
            row("経費", amount: estimate.businessExpenseYtd)
            row("利益 (課税所得ざっくり)", amount: estimate.profitYtd)
            row("税金の目安", amount: estimate.estimatedTax, color: DS.Palette.red, sub: "所得税+住民税+国保")
        }
        .padding(DS.Spacing.cardPadding)
        .background(DS.Palette.bg)
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.card).stroke(DS.Palette.line))
    }

    private func row(_ title: String, amount: Int, color: Color = DS.Palette.text, sub: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DS.Typo.body)
                    .foregroundStyle(DS.Palette.text)
                if let sub {
                    Text(sub)
                        .font(DS.Typo.caption)
                        .foregroundStyle(DS.Palette.textSub)
                }
            }
            Spacer()
            Text(YenText.string(amount: amount))
                .font(DS.Typo.amountM)
                .foregroundStyle(color)
        }
        .padding(.vertical, 8)
    }
}
