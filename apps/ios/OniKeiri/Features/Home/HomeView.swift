import Observation
import SwiftUI

struct HomeView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var viewModel = HomeViewModel()
    @State private var activeSheet: HomeEntrySheet?

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.sectionGap) {
                switch viewModel.state {
                case .loading:
                    HeaderView(month: "----年-月", remainingDays: nil)
                    LoadingHero()
                    PlaceholderCard(height: 86)
                    PlaceholderCard(height: 180)
                case .error:
                    ErrorHero {
                        Task { await viewModel.load(api: environment.api, auth: environment.auth) }
                    }
                case .loaded(let home):
                    HeaderView(month: OniDateFormat.monthTitle(home.month), remainingDays: OniDateFormat.remainingDays(today: home.today))
                    HeroCard(home: home)
                    QuickActionRow(cards: viewModel.cards) { segment in
                        activeSheet = HomeEntrySheet(segment: segment)
                    }
                    FeatureGrid(employmentType: home.employmentType)
                    UpcomingPaymentsCard(home: home)
                    BalanceCard(home: home)
                }
            }
            .padding(DS.Spacing.screenMargin)
        }
        .background(DS.Palette.bg)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: environment.ticker.tick) {
            await viewModel.load(api: environment.api, auth: environment.auth)
        }
        .refreshable {
            await viewModel.load(api: environment.api, auth: environment.auth)
        }
        .sheet(item: $activeSheet) { item in
            if let home = viewModel.home {
                EntrySheet(
                    initialSegment: item.segment,
                    cards: viewModel.cards,
                    employmentType: home.employmentType,
                    today: home.today
                ) { submission in
                    await viewModel.submit(submission, api: environment.api, auth: environment.auth, ticker: environment.ticker)
                }
            }
        }
    }
}

@MainActor
@Observable
final class HomeViewModel {
    enum State: Equatable {
        case loading
        case loaded(HomeResponse)
        case error
    }

    private(set) var state: State = .loading
    private(set) var home: HomeResponse?
    private(set) var cards: [CardDto] = []

    func load(api: APIClient, auth: AuthStore) async {
        state = .loading
        do {
            let loadedHome = try await api.home(month: nil)
            let loadedCards = try await api.cards()
            home = loadedHome
            cards = loadedCards.filter { !$0.archived }
            state = .loaded(loadedHome)
        } catch APIError.unauthorized {
            auth.handleUnauthorized()
        } catch {
            state = .error
        }
    }

    func submit(_ submission: EntrySubmission, api: APIClient, auth: AuthStore, ticker: RefreshTicker) async -> Bool {
        do {
            switch submission {
            case .create(let body):
                _ = try await api.createEntry(body)
            case .createSalary(let body):
                _ = try await api.createSalary(body)
            case .update(let id, let body):
                _ = try await api.updateEntry(id: id, body)
            case .delete(let id):
                try await api.deleteEntry(id: id)
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

private struct HomeEntrySheet: Identifiable {
    let id = UUID()
    let segment: EntrySegment
}

private struct HeaderView: View {
    let month: String
    let remainingDays: Int?

    var body: some View {
        HStack(spacing: 10) {
            Text("鬼")
                .font(DS.Typo.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(DS.Palette.red, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(month)
                    .font(DS.Typo.title)
                    .foregroundStyle(DS.Palette.text)
                if let remainingDays {
                    Text("あと\(remainingDays)日")
                        .font(DS.Typo.caption)
                        .foregroundStyle(DS.Palette.textSub)
                }
            }
            Spacer()
        }
    }
}

private struct HeroCard: View {
    let home: HomeResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("今月あと使える額")
                .font(DS.Typo.caption)
                .foregroundStyle(.white.opacity(0.62))
            Text(YenText.string(amount: home.spendable))
                .font(DS.Typo.display)
                .foregroundStyle(home.spendable < 0 ? DS.Palette.red : .white)
                .lineLimit(1)
                .minimumScaleFactor(0.74)
                .padding(.top, 6)

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("収入−支出・予定込み")
                        .font(DS.Typo.labelS)
                        .foregroundStyle(.white.opacity(0.55))
                    Text("\(YenText.string(amount: home.income)) − \(YenText.string(amount: home.spending))")
                        .font(DS.Typo.amountM)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("貯金見込み")
                        .font(DS.Typo.labelS)
                        .foregroundStyle(.white.opacity(0.55))
                    Text(YenText.string(amount: home.remaining))
                        .font(DS.Typo.amountM)
                        .foregroundStyle(home.remaining < 0 ? DS.Palette.red : DS.Palette.heroTeal)
                }
            }
            .padding(.top, 18)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .dsInkSurface()
    }
}

private struct QuickActionRow: View {
    let cards: [CardDto]
    let action: (EntrySegment) -> Void

    var body: some View {
        HStack(spacing: DS.Spacing.gridGap) {
            QuickActionButton(title: "支出", systemImage: "arrow.down") { action(.expense) }
                .accessibilityIdentifier("quick-expense")
            QuickActionButton(title: "収入", systemImage: "arrow.up") { action(.income) }
                .accessibilityIdentifier("quick-income")
            QuickActionButton(title: "クレカ支出", systemImage: "creditcard") { action(.cardExpense) }
                .accessibilityIdentifier("quick-card")
        }
    }
}

private struct QuickActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 21, weight: .medium))
                Text(title)
                    .font(DS.Typo.labelS)
                    .foregroundStyle(DS.Palette.textSub)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 70)
            .background(DS.Palette.bg)
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.card).stroke(DS.Palette.line))
        }
        .foregroundStyle(DS.Palette.text)
    }
}

private struct FeatureGrid: View {
    let employmentType: EmploymentType

    var body: some View {
        let features = [
            ("サブスク・定額", "arrow.triangle.2.circlepath", "feature-subs"),
            ("カード", "creditcard", "feature-cards"),
            ("給与", "banknote", "feature-salary"),
            ("税金目安", "chart.bar", "feature-tax")
        ].filter { employmentType == .freelance || $0.2 != "feature-tax" }

        HStack(spacing: DS.Spacing.gridGap) {
            ForEach(features, id: \.2) { feature in
                NavigationLink {
                    FeaturePlaceholderView(title: feature.0)
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: feature.1)
                            .font(.system(size: 22, weight: .medium))
                            .frame(width: 52, height: 52)
                            .background(DS.Palette.bgSoft, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                        Text(feature.0)
                            .font(DS.Typo.labelS)
                            .foregroundStyle(DS.Palette.textSub)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity)
                }
                .foregroundStyle(DS.Palette.text)
                .accessibilityIdentifier(feature.2)
            }
        }
    }
}

private struct UpcomingPaymentsCard: View {
    let home: HomeResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("今後の支払い")
                    .font(DS.Typo.heading)
                    .foregroundStyle(DS.Palette.textSub)
                Spacer()
                NavigationLink("カレンダーで見る ›") {
                    FeaturePlaceholderView(title: "カレンダー")
                }
                .font(DS.Typo.caption.weight(.semibold))
                .foregroundStyle(DS.Palette.teal)
            }

            if home.upcomingPayments.isEmpty {
                Text("この先の支払い予定はありません")
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            } else {
                ForEach(Array(home.upcomingPayments.prefix(3))) { payment in
                    PaymentRow(payment: payment)
                }
                HStack {
                    Text("\(monthNumber(home.month))月の残り支払い予定 (\(home.upcomingPayments.count)件)")
                        .font(DS.Typo.caption)
                        .foregroundStyle(DS.Palette.textSub)
                    Spacer()
                    Text(YenText.string(amount: home.upcomingTotal))
                        .font(DS.Typo.amountM)
                        .foregroundStyle(DS.Palette.text)
                }
                .padding(.top, 4)
            }
        }
        .padding(DS.Spacing.cardPadding)
        .background(DS.Palette.bg)
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.card).stroke(DS.Palette.line))
    }

    private func monthNumber(_ month: String) -> Int {
        Int(month.suffix(2)) ?? 0
    }
}

private struct PaymentRow: View {
    let payment: CalendarEventDto

    var body: some View {
        HStack(spacing: 12) {
            Text(OniDateFormat.dayMonth(payment.date))
                .font(DS.Typo.caption)
                .foregroundStyle(DS.Palette.textSub)
                .frame(width: 34, alignment: .leading)
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(payment.title)
                    .font(DS.Typo.body.weight(.semibold))
                    .foregroundStyle(DS.Palette.text)
                Text(subtitle)
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .lineLimit(1)
            }
            Spacer()
            Text(YenText.string(amount: payment.amount))
                .font(DS.Typo.amountM)
                .foregroundStyle(DS.Palette.text)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.Palette.line).frame(height: 1)
        }
    }

    @ViewBuilder private var icon: some View {
        switch payment {
        case .cardPayment:
            CreditCardMini()
        case .fixedCost(_, let name, _, _, _, _, let category):
            ServiceTile(initial: name, color: category?.color ?? DS.Chart.cat6)
        case .salary(_, let name, _, _):
            ServiceTile(initial: name, color: DS.Palette.teal)
        }
    }

    private var subtitle: String {
        switch payment {
        case .fixedCost(_, _, _, _, _, let cardName, _):
            cardName.map { "\($0)カードから" } ?? "現金/口座"
        case .cardPayment(_, _, _, _, let fromExclusive, let toInclusive, _):
            "\(OniDateFormat.dayMonth(fromExclusive))〜\(OniDateFormat.dayMonth(toInclusive)) 利用分"
        case .salary:
            "自動計上"
        }
    }
}

private struct BalanceCard: View {
    let home: HomeResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("残高推移")
                    .font(DS.Typo.heading)
                    .foregroundStyle(DS.Palette.textSub)
                Spacer()
                Text("\(monthNumber(home.month))月末まで")
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.Palette.textSub)
            }
            BalanceLineChart(series: normalizedSeries, minPoint: home.minPoint, savingsGoal: home.savingsGoal)
        }
        .padding(DS.Spacing.cardPadding)
        .background(DS.Palette.bg)
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.card).stroke(DS.Palette.line))
    }

    private var normalizedSeries: [DailyPointDto] {
        home.dailySeries.isEmpty ? [DailyPointDto(date: home.today, value: 0, projected: false)] : home.dailySeries
    }

    private func monthNumber(_ month: String) -> Int {
        Int(month.suffix(2)) ?? 0
    }
}

private struct LoadingHero: View {
    var body: some View {
        ProgressView()
            .frame(maxWidth: .infinity)
            .frame(height: 172)
            .dsInkSurface()
    }
}

private struct ErrorHero: View {
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text("ホームを読み込めませんでした")
                .font(DS.Typo.body.weight(.semibold))
                .foregroundStyle(.white)
            Button("再試行", action: retry)
                .font(DS.Typo.caption.weight(.semibold))
                .foregroundStyle(DS.Palette.ink)
                .padding(.horizontal, 18)
                .frame(height: 38)
                .background(.white, in: Capsule())
        }
        .frame(maxWidth: .infinity)
        .frame(height: 172)
        .dsInkSurface()
    }
}

private struct PlaceholderCard: View {
    let height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
            .fill(DS.Palette.bg)
            .frame(height: height)
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.card).stroke(DS.Palette.line))
            .overlay(ProgressView())
    }
}
