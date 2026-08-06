import Observation
import SwiftUI

struct SubsListView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var viewModel = SubsListViewModel()
    @State private var sort: SubsSort = .day
    @State private var editingRule: RecurringRuleDto?
    @State private var showCreate = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(spacing: DS.Spacing.sectionGap) {
                    switch viewModel.state {
                    case .loading:
                        LoadingPlaceholderCard(height: 220)
                    case .error:
                        ContentUnavailableView {
                            Label("定額支払いを読み込めません", systemImage: "exclamationmark.triangle")
                        } actions: {
                            Button("再試行") { Task { await viewModel.load(api: environment.api, auth: environment.auth) } }
                        }
                    case .loaded:
                        SubsSummaryCard(rules: viewModel.rules)
                        SortPills(selection: $sort)
                        ForEach(sortedRules) { rule in
                            Button {
                                editingRule = rule
                            } label: {
                                RuleRow(rule: rule, cards: viewModel.cards, mode: .expense)
                            }
                            .foregroundStyle(DS.Palette.text)
                        }
                    }
                }
                .padding(DS.Spacing.screenMargin)
                .padding(.bottom, 72)
            }
            Button {
                showCreate = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(DS.Palette.ink, in: Circle())
            }
            .padding(20)
        }
        .background(DS.Palette.bg)
        .navigationTitle("サブスク・定額")
        .task(id: environment.ticker.tick) {
            await viewModel.load(api: environment.api, auth: environment.auth)
        }
        .sheet(isPresented: $showCreate) {
            RuleFormSheet(direction: .expense, existing: nil, cards: viewModel.cards) { submission in
                await viewModel.submit(submission, api: environment.api, auth: environment.auth, ticker: environment.ticker)
            }
        }
        .sheet(item: $editingRule) { rule in
            RuleFormSheet(direction: .expense, existing: rule, cards: viewModel.cards) { submission in
                await viewModel.submit(submission, api: environment.api, auth: environment.auth, ticker: environment.ticker)
            }
        }
    }

    private var sortedRules: [RecurringRuleDto] {
        switch sort {
        case .day:
            viewModel.rules.sorted { ($0.dayOfMonth, $0.name) < ($1.dayOfMonth, $1.name) }
        case .high:
            viewModel.rules.sorted { $0.amount > $1.amount }
        case .low:
            viewModel.rules.sorted { $0.amount < $1.amount }
        case .card:
            viewModel.rules.sorted { (cardName($0.cardId), $0.dayOfMonth) < (cardName($1.cardId), $1.dayOfMonth) }
        }
    }

    private func cardName(_ id: String?) -> String {
        id.flatMap { value in viewModel.cards.first { $0.id == value }?.name } ?? "現金/口座"
    }
}

@MainActor
@Observable
final class SubsListViewModel {
    enum State: Equatable { case loading, loaded, error }
    private(set) var state: State = .loading
    private(set) var rules: [RecurringRuleDto] = []
    private(set) var cards: [CardDto] = []

    func load(api: APIClient, auth: AuthStore) async {
        state = .loading
        do {
            rules = try await api.recurringRules(direction: .expense)
            cards = try await api.cards().filter { !$0.archived }
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

private enum SubsSort: CaseIterable, Identifiable {
    case day, high, low, card
    var id: String { title }
    var title: String {
        switch self {
        case .day: "請求日"
        case .high: "高い順"
        case .low: "安い順"
        case .card: "カード別"
        }
    }
}

private struct SubsSummaryCard: View {
    let rules: [RecurringRuleDto]
    private var activeRules: [RecurringRuleDto] { rules.filter(\.active) }
    private var monthlyTotal: Int { activeRules.reduce(0) { $0 + $1.amount } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("今月の定額支払い")
                .font(DS.Typo.caption)
                .foregroundStyle(.white.opacity(0.62))
            Text(YenText.string(amount: monthlyTotal))
                .font(DS.Typo.displayS)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            HStack {
                SummaryMetric(title: "年間換算", value: YenText.string(amount: monthlyTotal * 12))
                Spacer()
                SummaryMetric(title: "登録数", value: "\(activeRules.count)件")
            }
        }
        .padding(20)
        .dsInkSurface()
    }
}

private struct SummaryMetric: View {
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

private struct SortPills: View {
    @Binding var selection: SubsSort

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SubsSort.allCases) { sort in
                    Button(sort.title) {
                        selection = sort
                    }
                    .font(DS.Typo.caption.weight(.semibold))
                    .foregroundStyle(selection == sort ? .white : DS.Palette.textSub)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(selection == sort ? DS.Palette.ink : DS.Palette.bgSoft, in: Capsule())
                }
            }
        }
    }
}

enum RuleRowMode {
    case expense
    case income
}

struct RuleRow: View {
    let rule: RecurringRuleDto
    let cards: [CardDto]
    let mode: RuleRowMode

    var body: some View {
        HStack(spacing: 12) {
            ServiceTile(initial: mode == .income ? "給" : rule.name, color: mode == .income ? DS.Palette.teal : rule.category?.color ?? DS.Chart.cat6)
            VStack(alignment: .leading, spacing: 3) {
                Text(rule.name)
                    .font(DS.Typo.body.weight(.semibold))
                    .foregroundStyle(DS.Palette.text)
                Text(subtitle)
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.Palette.textSub)
            }
            Spacer()
            Text(YenText.string(amount: rule.amount, positive: mode == .income))
                .font(DS.Typo.amountM)
                .foregroundStyle(mode == .income ? DS.Palette.teal : DS.Palette.text)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.Palette.textSub)
        }
        .padding(DS.Spacing.cardPadding)
        .background(DS.Palette.bg)
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.card).stroke(DS.Palette.line))
        .opacity(rule.active ? 1 : 0.54)
    }

    private var subtitle: String {
        if mode == .income {
            return "毎月\(rule.dayOfMonth)日・自動計上"
        }
        let payment = rule.cardId.flatMap { id in cards.first { $0.id == id }?.name } ?? "現金/口座"
        return "毎月\(rule.dayOfMonth)日・\(payment)"
    }
}

enum RuleSubmission {
    case create(RuleFormBodyDto)
    case update(id: String, RuleUpdateBodyDto)
    case delete(id: String)
}

struct RuleFormSheet: View {
    @Environment(\.dismiss) private var dismiss
    let direction: RuleDirection
    let existing: RecurringRuleDto?
    let cards: [CardDto]
    let onSubmit: (RuleSubmission) async -> Bool

    @State private var name: String
    @State private var amount: AmountInput
    @State private var dayOfMonth: Int
    @State private var cardId: String?
    @State private var category: EntryCategory
    @State private var active: Bool
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showDeleteConfirmation = false

    init(direction: RuleDirection, existing: RecurringRuleDto?, cards: [CardDto], onSubmit: @escaping (RuleSubmission) async -> Bool) {
        self.direction = direction
        self.existing = existing
        self.cards = cards.filter { !$0.archived }
        self.onSubmit = onSubmit
        _name = State(initialValue: existing?.name ?? (direction == .income ? "給与" : ""))
        _amount = State(initialValue: AmountInput(amount: existing?.amount ?? 0))
        _dayOfMonth = State(initialValue: existing?.dayOfMonth ?? 25)
        _cardId = State(initialValue: existing?.cardId)
        _category = State(initialValue: existing?.category ?? .daily)
        _active = State(initialValue: existing?.active ?? true)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    TextField(direction == .income ? "給与名" : "名前", text: $name)
                        .font(DS.Typo.body)
                        .padding(.horizontal, 14)
                        .frame(height: 46)
                        .background(DS.Palette.bgSoft, in: Capsule())

                    Text(YenText.string(amount: amount.amount, positive: direction == .income))
                        .font(DS.Typo.displayS)
                        .foregroundStyle(amount.amount == 0 ? DS.Palette.textSub : (direction == .income ? DS.Palette.teal : DS.Palette.text))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Picker(direction == .income ? "毎月の入金日" : "毎月の支払日", selection: $dayOfMonth) {
                        ForEach(1...31, id: \.self) { Text(dayLabel($0)).tag($0) }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 108)

                    if direction == .expense {
                        RuleCardPicker(cards: cards, selection: $cardId)
                        CategoryChipsForRule(selection: $category)
                    }

                    if existing != nil {
                        Toggle(direction == .income ? "停止" : "停止", isOn: Binding(
                            get: { !active },
                            set: { active = !$0 }
                        ))
                        .font(DS.Typo.body)
                        .tint(DS.Palette.teal)
                    }

                    NumericKeypad(amount: $amount)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(DS.Typo.caption)
                            .foregroundStyle(DS.Palette.red)
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        Text(existing == nil ? "追加する" : "保存する")
                            .font(DS.Typo.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                    }
                    .foregroundStyle(.white)
                    .background(canSubmit ? DS.Palette.ink : DS.Palette.textSub, in: Capsule())
                    .disabled(!canSubmit || isSubmitting)

                    if let existing {
                        Button("削除する") {
                            showDeleteConfirmation = true
                        }
                        .font(DS.Typo.body.weight(.semibold))
                        .foregroundStyle(DS.Palette.red)
                        .confirmationDialog("この定額ルールを削除しますか", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                            Button("削除する", role: .destructive) {
                                Task { await delete(id: existing.id) }
                            }
                        }
                    }
                }
                .padding(DS.Spacing.screenMargin)
            }
            .background(DS.Palette.bg)
            .navigationTitle(existing == nil ? (direction == .income ? "給与を追加" : "定額を追加") : "ルールを編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && amount.amount > 0
    }

    private func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let success: Bool
        if let existing {
            success = await onSubmit(.update(id: existing.id, RuleUpdateBodyDto(
                name: trimmed,
                amount: amount.amount,
                dayOfMonth: dayOfMonth,
                cardId: direction == .expense ? cardId : nil,
                category: direction == .expense ? category : nil,
                active: active
            )))
        } else {
            success = await onSubmit(.create(RuleFormBodyDto(
                direction: direction,
                name: trimmed,
                amount: amount.amount,
                dayOfMonth: dayOfMonth,
                cardId: direction == .expense ? cardId : nil,
                category: direction == .expense ? category : nil
            )))
        }
        isSubmitting = false
        if success {
            dismiss()
        } else {
            errorMessage = "保存できませんでした。"
        }
    }

    private func delete(id: String) async {
        isSubmitting = true
        let success = await onSubmit(.delete(id: id))
        isSubmitting = false
        if success {
            dismiss()
        } else {
            errorMessage = "削除できませんでした。"
        }
    }
}

private struct RuleCardPicker: View {
    let cards: [CardDto]
    @Binding var selection: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                cardButton(nil, title: "現金/口座")
                ForEach(cards) { card in
                    cardButton(card.id, title: card.name)
                }
            }
        }
    }

    private func cardButton(_ id: String?, title: String) -> some View {
        Button {
            selection = id
        } label: {
            HStack(spacing: 8) {
                if id != nil { CreditCardMini() }
                Text(title)
            }
        }
        .font(DS.Typo.caption.weight(.semibold))
        .foregroundStyle(selection == id ? .white : DS.Palette.text)
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(selection == id ? DS.Palette.ink : DS.Palette.bgSoft, in: Capsule())
    }
}

private struct CategoryChipsForRule: View {
    @Binding var selection: EntryCategory

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(EntryCategory.allCases, id: \.rawValue) { category in
                    Button {
                        selection = category
                    } label: {
                        Label(category.displayName, systemImage: category.systemImage)
                    }
                    .font(DS.Typo.caption.weight(.semibold))
                    .foregroundStyle(selection == category ? .white : DS.Palette.textSub)
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .background(selection == category ? DS.Palette.ink : DS.Palette.bgSoft, in: Capsule())
                }
            }
        }
    }
}
