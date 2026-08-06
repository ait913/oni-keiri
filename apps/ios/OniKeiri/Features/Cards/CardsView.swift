import Observation
import SwiftUI

struct CardsListView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var viewModel = CardsListViewModel()
    @State private var showCreate = false

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.sectionGap) {
                switch viewModel.state {
                case .loading:
                    LoadingPlaceholderCard(height: 180)
                case .error:
                    ContentUnavailableView {
                        Label("カードを読み込めません", systemImage: "exclamationmark.triangle")
                    } actions: {
                        Button("再試行") { Task { await viewModel.load(api: environment.api, auth: environment.auth) } }
                    }
                case .loaded:
                    ForEach(viewModel.cards) { card in
                        NavigationLink {
                            CardDetailView(cardId: card.id)
                        } label: {
                            CardListRow(card: card)
                        }
                        .foregroundStyle(DS.Palette.text)
                    }
                    Button {
                        showCreate = true
                    } label: {
                        Text("+ カードを追加")
                            .font(DS.Typo.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .overlay(Capsule().stroke(DS.Palette.line))
                    }
                    .foregroundStyle(DS.Palette.text)
                }
            }
            .padding(DS.Spacing.screenMargin)
        }
        .background(DS.Palette.bg)
        .navigationTitle("カード")
        .task(id: environment.ticker.tick) {
            await viewModel.load(api: environment.api, auth: environment.auth)
        }
        .sheet(isPresented: $showCreate) {
            CardFormSheet { body in
                await viewModel.create(body, api: environment.api, auth: environment.auth, ticker: environment.ticker)
            }
        }
    }
}

@MainActor
@Observable
final class CardsListViewModel {
    enum State: Equatable { case loading, loaded, error }
    private(set) var state: State = .loading
    private(set) var cards: [CardDto] = []

    func load(api: APIClient, auth: AuthStore) async {
        state = .loading
        do {
            cards = try await api.cards()
            state = .loaded
        } catch APIError.unauthorized {
            auth.handleUnauthorized()
        } catch {
            state = .error
        }
    }

    func create(_ body: CardFormBodyDto, api: APIClient, auth: AuthStore, ticker: RefreshTicker) async -> Bool {
        do {
            _ = try await api.createCard(body)
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

private struct CardListRow: View {
    let card: CardDto

    var body: some View {
        HStack(spacing: 12) {
            CreditCardMini()
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(card.name)
                        .font(DS.Typo.body.weight(.semibold))
                    if card.archived {
                        Text("アーカイブ")
                            .font(DS.Typo.labelS)
                            .foregroundStyle(DS.Palette.textSub)
                    }
                }
                Text("締め \(dayLabel(card.closingDay)) / 支払い \(dayLabel(card.paymentDay))")
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.Palette.textSub)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("今月利用")
                    .font(DS.Typo.labelS)
                    .foregroundStyle(DS.Palette.textSub)
                Text(YenText.string(amount: card.monthUsage))
                    .font(DS.Typo.amountM)
                    .foregroundStyle(DS.Palette.text)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.Palette.textSub)
        }
        .padding(DS.Spacing.cardPadding)
        .background(DS.Palette.bg)
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.card).stroke(DS.Palette.line))
    }
}

struct CardDetailView: View {
    @Environment(AppEnvironment.self) private var environment
    let cardId: String
    @State private var viewModel = CardDetailViewModel()
    @State private var showEdit = false

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.sectionGap) {
                switch viewModel.state {
                case .loading:
                    LoadingPlaceholderCard(height: 220)
                case .error(let message):
                    ContentUnavailableView {
                        Label(message, systemImage: "exclamationmark.triangle")
                    } actions: {
                        Button("再試行") { Task { await viewModel.load(cardId: cardId, api: environment.api, auth: environment.auth) } }
                    }
                case .loaded(let detail):
                    CardHero(card: detail.card)
                    NextPaymentCard(card: detail.card)
                    ScheduleCard(payments: detail.payments)
                    EntryPreviewCard(title: "最近のクレカ支出", entries: detail.recentExpenses)
                    LinkedRulesCard(rules: detail.linkedRules)
                    CardDangerActions(
                        archived: detail.card.archived,
                        errorMessage: viewModel.actionError,
                        onArchive: {
                            await viewModel.archive(card: detail.card, api: environment.api, auth: environment.auth, ticker: environment.ticker)
                        },
                        onDelete: {
                            await viewModel.delete(card: detail.card, api: environment.api, auth: environment.auth, ticker: environment.ticker)
                        }
                    )
                }
            }
            .padding(DS.Spacing.screenMargin)
        }
        .background(DS.Palette.bg)
        .navigationTitle("カード詳細")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("編集") { showEdit = true }
                    .disabled(viewModel.detail == nil)
            }
        }
        .task(id: environment.ticker.tick) {
            await viewModel.load(cardId: cardId, api: environment.api, auth: environment.auth)
        }
        .sheet(isPresented: $showEdit) {
            if let card = viewModel.detail?.card {
                CardFormSheet(existing: card) { body in
                    await viewModel.update(card: card, body: body, api: environment.api, auth: environment.auth, ticker: environment.ticker)
                }
            }
        }
    }
}

@MainActor
@Observable
final class CardDetailViewModel {
    enum State: Equatable {
        case loading
        case loaded(CardDetailResponse)
        case error(String)
    }

    private(set) var state: State = .loading
    private(set) var detail: CardDetailResponse?
    var actionError: String?

    func load(cardId: String, api: APIClient, auth: AuthStore) async {
        state = .loading
        do {
            let loaded = try await api.cardDetail(id: cardId, months: 3)
            detail = loaded
            actionError = nil
            state = .loaded(loaded)
        } catch APIError.unauthorized {
            auth.handleUnauthorized()
        } catch {
            state = .error("カード詳細を読み込めません")
        }
    }

    func update(card: CardDto, body: CardFormBodyDto, api: APIClient, auth: AuthStore, ticker: RefreshTicker) async -> Bool {
        do {
            _ = try await api.updateCard(id: card.id, CardUpdateBodyDto(
                name: body.name,
                closingDay: body.closingDay,
                paymentDay: body.paymentDay,
                revolvingAmount: body.revolvingAmount,
                creditLimit: body.creditLimit,
                carryoverBalance: body.carryoverBalance,
                archived: card.archived
            ))
            ticker.bump()
            return true
        } catch APIError.unauthorized {
            auth.handleUnauthorized()
            return false
        } catch {
            return false
        }
    }

    func archive(card: CardDto, api: APIClient, auth: AuthStore, ticker: RefreshTicker) async {
        do {
            _ = try await api.updateCard(id: card.id, CardUpdateBodyDto(
                name: nil,
                closingDay: nil,
                paymentDay: nil,
                revolvingAmount: nil,
                creditLimit: nil,
                carryoverBalance: nil,
                archived: !card.archived
            ))
            ticker.bump()
        } catch APIError.unauthorized {
            auth.handleUnauthorized()
        } catch {
            actionError = "アーカイブ状態を変更できませんでした。"
        }
    }

    func delete(card: CardDto, api: APIClient, auth: AuthStore, ticker: RefreshTicker) async {
        do {
            try await api.deleteCard(id: card.id)
            ticker.bump()
        } catch APIError.unauthorized {
            auth.handleUnauthorized()
        } catch APIError.api(let status, let code, _ ) where status == 409 || code == "CARD_IN_USE" {
            actionError = "このカードは記録または定額支出で使われています。削除ではなくアーカイブしてください。"
        } catch {
            actionError = "カードを削除できませんでした。"
        }
    }
}

private struct CardHero: View {
    let card: CardDto

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(card.name)
                .font(DS.Typo.title)
                .foregroundStyle(.white)
            Text("締め日 \(dayLabel(card.closingDay))・支払日 \(dayLabel(card.paymentDay))・リボ \(card.revolvingAmount == nil ? "OFF" : "ON")")
                .font(DS.Typo.caption)
                .foregroundStyle(.white.opacity(0.62))
            VStack(alignment: .leading, spacing: 8) {
                Text(limitText)
                    .font(DS.Typo.amountM)
                    .foregroundStyle(.white)
                if let limit = card.creditLimit, limit > 0 {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.20))
                            Capsule().fill(.white).frame(width: proxy.size.width * min(CGFloat(card.utilization) / CGFloat(limit), 1))
                        }
                    }
                    .frame(height: 6)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .aspectRatio(1.62, contentMode: .fit)
        .dsInkSurface(radius: DS.Radius.hero)
    }

    private var limitText: String {
        if let limit = card.creditLimit {
            return "使用 \(YenText.string(amount: card.utilization)) / 限度 \(YenText.string(amount: limit))"
        }
        return "使用 \(YenText.string(amount: card.utilization))"
    }
}

private struct NextPaymentCard: View {
    let card: CardDto

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("来月の支払い目安")
                .font(DS.Typo.heading)
                .foregroundStyle(DS.Palette.textSub)
            Text(YenText.string(amount: card.nextPayment?.amount ?? 0))
                .font(DS.Typo.amountL)
                .foregroundStyle(DS.Palette.text)
            Text(status)
                .font(DS.Typo.caption)
                .foregroundStyle(DS.Palette.textSub)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Spacing.cardPadding)
        .background(DS.Palette.bg)
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.card).stroke(DS.Palette.line))
    }

    private var status: String {
        guard let payment = card.nextPayment else { return "支払い予定はありません" }
        let suffix = payment.closed ? "確定済み" : "見込み"
        return "\(OniDateFormat.dayMonth(payment.paymentDate)) に支払い予定・\(suffix)"
    }
}

private struct ScheduleCard: View {
    let payments: [CardDetailResponse.Payment]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("支払い予定")
                .font(DS.Typo.heading)
                .foregroundStyle(DS.Palette.textSub)
            ForEach(payments, id: \.paymentDate) { payment in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(OniDateFormat.dayMonth(payment.paymentDate))
                            .font(DS.Typo.body.weight(.semibold))
                        Text("\(OniDateFormat.dayMonth(payment.fromExclusive))〜\(OniDateFormat.dayMonth(payment.toInclusive)) 利用分")
                            .font(DS.Typo.caption)
                            .foregroundStyle(DS.Palette.textSub)
                    }
                    Spacer()
                    Text(YenText.string(amount: payment.amount))
                        .font(DS.Typo.amountM)
                }
                .padding(.vertical, 8)
            }
        }
        .padding(DS.Spacing.cardPadding)
        .background(DS.Palette.bg)
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.card).stroke(DS.Palette.line))
    }
}

private struct EntryPreviewCard: View {
    let title: String
    let entries: [EntryDto]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(DS.Typo.heading)
                .foregroundStyle(DS.Palette.textSub)
            if entries.isEmpty {
                Text("まだありません")
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .padding(.vertical, 8)
            } else {
                ForEach(entries) { entry in
                    HStack {
                        ServiceTile(initial: entry.note ?? entry.category?.displayName ?? "支", color: entry.category?.color ?? DS.Chart.cat6)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.note ?? entry.category?.displayName ?? "クレカ支出")
                                .font(DS.Typo.body.weight(.semibold))
                            Text(OniDateFormat.dayMonth(entry.date))
                                .font(DS.Typo.caption)
                                .foregroundStyle(DS.Palette.textSub)
                        }
                        Spacer()
                        Text(YenText.string(amount: entry.amount))
                            .font(DS.Typo.amountM)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .padding(DS.Spacing.cardPadding)
        .background(DS.Palette.bg)
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.card).stroke(DS.Palette.line))
    }
}

private struct LinkedRulesCard: View {
    let rules: [RecurringRuleDto]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("紐づく定額支出")
                .font(DS.Typo.heading)
                .foregroundStyle(DS.Palette.textSub)
            if rules.isEmpty {
                Text("まだありません")
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .padding(.vertical, 8)
            } else {
                ForEach(rules) { rule in
                    HStack {
                        ServiceTile(initial: rule.name, color: rule.category?.color ?? DS.Chart.cat6)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rule.name)
                                .font(DS.Typo.body.weight(.semibold))
                            Text("自動でクレカ支出に計上")
                                .font(DS.Typo.caption)
                                .foregroundStyle(DS.Palette.textSub)
                        }
                        Spacer()
                        Text(YenText.string(amount: rule.amount))
                            .font(DS.Typo.amountM)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .padding(DS.Spacing.cardPadding)
        .background(DS.Palette.bg)
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.card).stroke(DS.Palette.line))
    }
}

private struct CardDangerActions: View {
    let archived: Bool
    let errorMessage: String?
    let onArchive: () async -> Void
    let onDelete: () async -> Void
    @State private var confirmDelete = false

    var body: some View {
        VStack(spacing: 10) {
            Button(archived ? "アーカイブを解除" : "アーカイブ") {
                Task { await onArchive() }
            }
            .font(DS.Typo.body.weight(.semibold))
            .foregroundStyle(DS.Palette.text)
            Button("削除する") {
                confirmDelete = true
            }
            .font(DS.Typo.body.weight(.semibold))
            .foregroundStyle(DS.Palette.red)
            if let errorMessage {
                Text(errorMessage)
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.Palette.red)
            }
        }
        .confirmationDialog("このカードを削除しますか", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("削除する", role: .destructive) {
                Task { await onDelete() }
            }
        }
    }
}

struct CardFormSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let existing: CardDto?
    private let onSave: (CardFormBodyDto) async -> Bool

    @State private var name: String
    @State private var closingDay: Int
    @State private var paymentDay: Int
    @State private var revolvingEnabled: Bool
    @State private var revolvingAmount: Int
    @State private var creditLimit: Int
    @State private var carryoverBalance: Int
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(existing: CardDto? = nil, onSave: @escaping (CardFormBodyDto) async -> Bool) {
        self.existing = existing
        self.onSave = onSave
        _name = State(initialValue: existing?.name ?? "")
        _closingDay = State(initialValue: existing?.closingDay ?? 31)
        _paymentDay = State(initialValue: existing?.paymentDay ?? 27)
        _revolvingEnabled = State(initialValue: existing?.revolvingAmount != nil)
        _revolvingAmount = State(initialValue: existing?.revolvingAmount ?? 0)
        _creditLimit = State(initialValue: existing?.creditLimit ?? 0)
        _carryoverBalance = State(initialValue: existing?.carryoverBalance ?? 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("カード名", text: $name)
                    Picker("締め日", selection: $closingDay) {
                        ForEach(1...31, id: \.self) { Text(dayLabel($0)).tag($0) }
                    }
                    Picker("支払日", selection: $paymentDay) {
                        ForEach(1...31, id: \.self) { Text(dayLabel($0)).tag($0) }
                    }
                }
                Section {
                    Toggle("リボ", isOn: $revolvingEnabled)
                    if revolvingEnabled {
                        TextField("月額", value: $revolvingAmount, formatter: NumberFormatter())
                            .keyboardType(.numberPad)
                    }
                    TextField("限度額 (任意)", value: $creditLimit, formatter: NumberFormatter())
                        .keyboardType(.numberPad)
                    TextField("現在の未払い残高", value: $carryoverBalance, formatter: NumberFormatter())
                        .keyboardType(.numberPad)
                    Text("アプリ登録前の未払い分・リボ残高を入れてください")
                        .font(DS.Typo.caption)
                        .foregroundStyle(DS.Palette.textSub)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(DS.Typo.caption)
                        .foregroundStyle(DS.Palette.red)
                }
            }
            .navigationTitle(existing == nil ? "カードを追加" : "カードを編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { Task { await save() } }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
        }
    }

    private func save() async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSaving = true
        errorMessage = nil
        let success = await onSave(CardFormBodyDto(
            name: trimmed,
            closingDay: closingDay,
            paymentDay: paymentDay,
            revolvingAmount: revolvingEnabled && revolvingAmount > 0 ? revolvingAmount : nil,
            creditLimit: creditLimit > 0 ? creditLimit : nil,
            carryoverBalance: max(0, carryoverBalance)
        ))
        isSaving = false
        if success {
            dismiss()
        } else {
            errorMessage = "保存できませんでした。"
        }
    }
}

func dayLabel(_ day: Int) -> String {
    day == 31 ? "月末" : "\(day)日"
}
