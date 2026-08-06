import Observation
import SwiftUI

struct RecordsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var viewModel = RecordsViewModel()
    @State private var filter: RecordsFilter = .all
    @State private var editingEntry: EntryDto?

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.sectionGap) {
                MonthSwitcher(month: viewModel.month) { offset in
                    viewModel.month = OniDateFormat.addMonths(viewModel.month, by: offset)
                    Task { await viewModel.load(api: environment.api, auth: environment.auth) }
                }

                FilterPills(filter: $filter)

                switch viewModel.state {
                case .loading:
                    LoadingPlaceholderCard(height: 150)
                    LoadingPlaceholderCard(height: 116)
                case .error:
                    ContentUnavailableView {
                        Label("記録を読み込めません", systemImage: "exclamationmark.triangle")
                    } actions: {
                        Button("再試行") {
                            Task { await viewModel.load(api: environment.api, auth: environment.auth) }
                        }
                    }
                case .loaded(let response):
                    if response.entries.isEmpty {
                        ContentUnavailableView("まだ記録がありません", systemImage: "tray")
                            .padding(.top, 80)
                    } else {
                        BreakdownCard(response: response)
                        QualityCard(quality: response.quality)
                        EntryList(entries: filtered(response.entries), cardName: viewModel.cardName(id:)) { entry in
                            editingEntry = entry
                        } delete: { entry in
                            Task { await viewModel.delete(entry: entry, api: environment.api, auth: environment.auth, ticker: environment.ticker) }
                        }
                    }
                }
            }
            .padding(DS.Spacing.screenMargin)
        }
        .navigationTitle("記録")
        .background(DS.Palette.bg)
        .task(id: environment.ticker.tick) {
            await viewModel.load(api: environment.api, auth: environment.auth)
        }
        .refreshable {
            await viewModel.load(api: environment.api, auth: environment.auth)
        }
        .sheet(item: $editingEntry) { entry in
            EntrySheet(
                initialSegment: .expense,
                cards: viewModel.cards,
                employmentType: viewModel.employmentType,
                today: viewModel.today,
                editing: entry
            ) { submission in
                await viewModel.submit(submission, api: environment.api, auth: environment.auth, ticker: environment.ticker)
            }
        }
    }

    private func filtered(_ entries: [EntryDto]) -> [EntryDto] {
        switch filter {
        case .all:
            entries
        case .expense:
            entries.filter { $0.kind == .expense }
        case .income:
            entries.filter { $0.kind == .income }
        case .card:
            entries.filter { $0.kind == .cardExpense }
        }
    }
}

@MainActor
@Observable
final class RecordsViewModel {
    enum State: Equatable {
        case loading
        case loaded(EntriesResponse)
        case error
    }

    var month: String = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: Date())
    }()
    private(set) var state: State = .loading
    private(set) var cards: [CardDto] = []
    private(set) var today: String = {
        DateFormatter.oniKeiriDay.string(from: Date())
    }()
    private(set) var employmentType: EmploymentType = .employee

    func load(api: APIClient, auth: AuthStore) async {
        state = .loading
        do {
            let home = try await api.home(month: month)
            let response = try await api.entries(month: month)
            let loadedCards = try await api.cards()
            cards = loadedCards.filter { !$0.archived }
            today = home.today
            employmentType = home.employmentType
            state = .loaded(response)
        } catch APIError.unauthorized {
            auth.handleUnauthorized()
        } catch {
            state = .error
        }
    }

    func cardName(id: String?) -> String? {
        guard let id else { return nil }
        return cards.first { $0.id == id }?.name
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

    func delete(entry: EntryDto, api: APIClient, auth: AuthStore, ticker: RefreshTicker) async {
        guard entry.sourceRuleId == nil else { return }
        _ = await submit(.delete(id: entry.id), api: api, auth: auth, ticker: ticker)
    }
}

private enum RecordsFilter: String, CaseIterable, Identifiable {
    case all
    case expense
    case income
    case card

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "すべて"
        case .expense: "支出"
        case .income: "収入"
        case .card: "クレカ"
        }
    }

    var accessibilityKey: String { "filter-\(rawValue)" }
}

private struct MonthSwitcher: View {
    let month: String
    let move: (Int) -> Void

    var body: some View {
        HStack {
            Button { move(-1) } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
            }
            Spacer()
            Text(OniDateFormat.monthTitle(month))
                .font(DS.Typo.title)
                .foregroundStyle(DS.Palette.text)
            Spacer()
            Button { move(1) } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 44, height: 44)
            }
        }
        .foregroundStyle(DS.Palette.text)
    }
}

private struct FilterPills: View {
    @Binding var filter: RecordsFilter

    var body: some View {
        HStack(spacing: 8) {
            ForEach(RecordsFilter.allCases) { item in
                Button(item.title) {
                    filter = item
                }
                .font(DS.Typo.caption.weight(.semibold))
                .foregroundStyle(filter == item ? .white : DS.Palette.textSub)
                .padding(.horizontal, 15)
                .frame(height: 38)
                .background(filter == item ? DS.Palette.ink : DS.Palette.bgSoft, in: Capsule())
                .accessibilityIdentifier(item.accessibilityKey)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct BreakdownCard: View {
    let response: EntriesResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("今月の支出内訳")
                    .font(DS.Typo.heading)
                    .foregroundStyle(DS.Palette.textSub)
                Spacer()
                YenText(amount: response.breakdown.reduce(0) { $0 + $1.amount }, style: .amountL)
            }
            HStack(spacing: 14) {
                CategoryDonutChart(breakdown: response.breakdown)
                CategoryRankingList(breakdown: response.breakdown)
            }
        }
        .padding(DS.Spacing.cardPadding)
        .background(DS.Palette.bg)
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.card).stroke(DS.Palette.line))
    }
}

private struct QualityCard: View {
    let quality: EntriesResponse.Quality

    var body: some View {
        let total = quality.fixed + quality.variable
        VStack(alignment: .leading, spacing: 10) {
            Text("支出の質")
                .font(DS.Typo.heading)
                .foregroundStyle(DS.Palette.textSub)
            StackedQualityBar(fixed: quality.fixed, variable: quality.variable)
            HStack {
                Text("削減しづらい固定費 \(percent(quality.fixed, total: total))%")
                Spacer()
                Text("削減できる変動費 \(percent(quality.variable, total: total))%")
            }
            .font(DS.Typo.caption)
            .foregroundStyle(DS.Palette.textSub)
            HStack(spacing: 10) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(DS.Palette.teal)
                    .frame(width: 36, height: 36)
                    .background(DS.Palette.tealSoft, in: RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous))
                Text("変動費を1割削ると")
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.Palette.textSub)
                Spacer()
                Text("+\(YenText.string(amount: quality.savingTip))/月")
                    .font(DS.Typo.amountM)
                    .foregroundStyle(DS.Palette.teal)
            }
            .padding(.top, 8)
            .overlay(alignment: .top) {
                Rectangle().fill(DS.Palette.line).frame(height: 1)
            }
        }
        .padding(DS.Spacing.cardPadding)
        .background(DS.Palette.bg)
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.card).stroke(DS.Palette.line))
    }

    private func percent(_ value: Int, total: Int) -> Int {
        guard total > 0 else { return 0 }
        return Int((Double(value) / Double(total) * 100).rounded())
    }
}

private struct EntryList: View {
    let entries: [EntryDto]
    let cardName: (String?) -> String?
    let edit: (EntryDto) -> Void
    let delete: (EntryDto) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(groupedEntries, id: \.date) { group in
                Text(OniDateFormat.dayHeading(group.date))
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .padding(.horizontal, 4)
                    .padding(.top, 14)
                    .padding(.bottom, 6)
                VStack(spacing: 0) {
                    ForEach(group.entries) { entry in
                        Button {
                            edit(entry)
                        } label: {
                            EntryRow(entry: entry, cardName: cardName(entry.cardId))
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if entry.sourceRuleId == nil {
                                Button("削除", role: .destructive) {
                                    delete(entry)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .background(DS.Palette.bg)
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.card).stroke(DS.Palette.line))
            }
        }
    }

    private var groupedEntries: [(date: String, entries: [EntryDto])] {
        let grouped = Dictionary(grouping: entries, by: \.date)
        return grouped.keys.sorted(by: >).map { date in
            (date, grouped[date, default: []].sorted { $0.id > $1.id })
        }
    }
}

private struct EntryRow: View {
    let entry: EntryDto
    let cardName: String?

    var body: some View {
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.note?.isEmpty == false ? entry.note! : title)
                    .font(DS.Typo.body.weight(.semibold))
                    .foregroundStyle(DS.Palette.text)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(subtitle)
                    if let cardName, entry.kind == .cardExpense {
                        Text(cardName)
                            .padding(.horizontal, 8)
                            .frame(height: 18)
                            .background(DS.Palette.bgSoft, in: Capsule())
                    }
                }
                .font(DS.Typo.labelS)
                .foregroundStyle(DS.Palette.textSub)
                .lineLimit(1)
            }
            Spacer()
            YenText(amount: entry.amount, style: .amountM, positive: entry.kind == .income)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.Palette.line).frame(height: 1)
        }
    }

    @ViewBuilder private var icon: some View {
        if entry.sourceRuleId != nil {
            ServiceTile(initial: entry.note ?? title, color: entry.kind == .income ? DS.Palette.teal : (entry.category?.color ?? DS.Chart.cat6))
        } else if entry.kind == .cardExpense {
            CreditCardMini()
        } else {
            Image(systemName: entry.category?.systemImage ?? "arrow.up")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(entry.kind == .income ? DS.Palette.teal : (entry.category?.color ?? DS.Chart.cat6))
                .frame(width: 36, height: 36)
                .background(DS.Palette.bgSoft, in: RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous))
        }
    }

    private var title: String {
        switch entry.kind {
        case .income:
            entry.incomeSource == .salary ? "給与" : "収入"
        case .expense, .cardExpense:
            entry.category?.displayName ?? "その他"
        }
    }

    private var subtitle: String {
        switch entry.kind {
        case .income:
            entry.incomeSource == .salary ? "給与" : "その他"
        case .expense:
            entry.category?.displayName ?? "支出"
        case .cardExpense:
            "クレカ支出"
        }
    }
}
