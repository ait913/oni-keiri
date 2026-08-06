import SwiftUI

enum EntrySegment: String, CaseIterable, Identifiable {
    case expense
    case income
    case cardExpense

    var id: String { rawValue }

    var title: String {
        switch self {
        case .expense: "支出"
        case .income: "収入"
        case .cardExpense: "クレカ支出"
        }
    }
}

enum KeypadKey: Equatable, Identifiable {
    case digit(Int)
    case doubleZero
    case backspace

    var id: String {
        switch self {
        case .digit(let value): "\(value)"
        case .doubleZero: "00"
        case .backspace: "backspace"
        }
    }

    var label: String {
        switch self {
        case .digit(let value): "\(value)"
        case .doubleZero: "00"
        case .backspace: "⌫"
        }
    }
}

struct AmountInput: Equatable {
    private(set) var digits: String = ""
    var amount: Int { Int(digits) ?? 0 }

    init(amount: Int = 0) {
        digits = amount > 0 ? String(amount) : ""
    }

    mutating func tap(_ key: KeypadKey) {
        switch key {
        case .digit(let value):
            append(String(value))
        case .doubleZero:
            append("00")
        case .backspace:
            if !digits.isEmpty {
                digits.removeLast()
            }
        }
    }

    private mutating func append(_ value: String) {
        guard digits.count < 8 else { return }
        let next = digits + value
        guard let amount = Int(next), amount > 0 else { return }
        digits = String(next.prefix(8))
    }
}

enum EntrySubmission {
    case create(CreateEntryBodyDto)
    case createSalary(CreateSalaryBodyDto)
    case update(id: String, UpdateEntryBodyDto)
    case delete(id: String)
}

struct EntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var environment

    private let cards: [CardDto]
    private let employmentType: EmploymentType
    private let today: String
    private let editing: EntryDto?
    private let onSubmit: (EntrySubmission) async -> Bool

    @State private var segment: EntrySegment
    @State private var amount: AmountInput
    @State private var category: EntryCategory
    @State private var cardId: String?
    @State private var incomeSource: IncomeSource
    @State private var note = ""
    @State private var date: Date
    @State private var includeBusinessExpenses = false
    @State private var businessExpenses: [BusinessExpenseInput] = []
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showDeleteConfirmation = false
    @State private var showCardForm = false

    init(
        initialSegment: EntrySegment,
        cards: [CardDto],
        employmentType: EmploymentType,
        today: String,
        editing: EntryDto? = nil,
        onSubmit: @escaping (EntrySubmission) async -> Bool
    ) {
        self.cards = cards.filter { !$0.archived }
        self.employmentType = employmentType
        self.today = today
        self.editing = editing
        self.onSubmit = onSubmit

        let segment = editing.map(Self.segment(for:)) ?? initialSegment
        _segment = State(initialValue: segment)
        _amount = State(initialValue: AmountInput(amount: editing?.amount ?? 0))
        _category = State(initialValue: editing?.category ?? .food)
        _cardId = State(initialValue: editing?.cardId)
        _incomeSource = State(initialValue: editing?.incomeSource ?? .other)
        _note = State(initialValue: editing?.note ?? "")
        _date = State(initialValue: DateFormatter.oniKeiriDay.date(from: editing?.date ?? today) ?? Date())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Capsule()
                        .fill(DS.Palette.line)
                        .frame(width: 36, height: 5)
                        .padding(.top, 6)

                    if editing == nil {
                        SegmentPicker(segment: $segment, cardsAvailable: !cards.isEmpty)
                    }

                    Text(YenText.string(amount: amount.amount, positive: segment == .income))
                        .font(DS.Typo.display)
                        .foregroundStyle(amount.amount == 0 ? DS.Palette.textSub : (segment == .income ? DS.Palette.teal : DS.Palette.text))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)

                    if segment == .expense || segment == .cardExpense {
                        CategoryChips(selection: $category, employmentType: employmentType)
                    }

                    if segment == .cardExpense {
                        CardChips(cards: cards, selection: $cardId) {
                            showCardForm = true
                        }
                    }

                    if segment == .income {
                        IncomeControls(
                            incomeSource: $incomeSource,
                            includeBusinessExpenses: $includeBusinessExpenses,
                            businessExpenses: $businessExpenses,
                            employmentType: employmentType
                        )
                    }

                    TextField("メモ", text: $note)
                        .font(DS.Typo.body)
                        .padding(.horizontal, 14)
                        .frame(height: 46)
                        .background(DS.Palette.bgSoft, in: Capsule())

                    DatePicker("日付", selection: $date, displayedComponents: .date)
                        .font(DS.Typo.body)
                        .tint(DS.Palette.ink)

                    NumericKeypad(amount: $amount)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(DS.Typo.caption)
                            .foregroundStyle(DS.Palette.red)
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        if isSubmitting {
                            ProgressView().tint(.white)
                        } else {
                            Text(editing == nil ? "追加する" : "保存する")
                                .font(DS.Typo.body.weight(.semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .foregroundStyle(.white)
                    .background(canSubmit ? DS.Palette.ink : DS.Palette.textSub, in: Capsule())
                    .disabled(!canSubmit || isSubmitting)

                    if let editing {
                        Button("削除する") {
                            showDeleteConfirmation = true
                        }
                        .font(DS.Typo.body.weight(.semibold))
                        .foregroundStyle(DS.Palette.red)
                        .padding(.top, 4)
                        .confirmationDialog("この記録を削除しますか", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                            Button("削除する", role: .destructive) {
                                Task { await delete(id: editing.id) }
                            }
                        }
                    }
                }
                .padding(DS.Spacing.screenMargin)
            }
            .background(DS.Palette.bg)
            .navigationTitle(editing == nil ? "記録を追加" : "記録を編集")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            if segment == .cardExpense, cardId == nil {
                cardId = cards.first?.id
            }
        }
        .onChange(of: segment) { _, newValue in
            if newValue == .cardExpense, cardId == nil {
                cardId = cards.first?.id
            }
        }
        .sheet(isPresented: $showCardForm) {
            CardFormSheet { body in
                do {
                    _ = try await environment.api.createCard(body)
                    environment.ticker.bump()
                    return true
                } catch APIError.unauthorized {
                    environment.auth.handleUnauthorized()
                    return false
                } catch {
                    return false
                }
            }
        }
    }

    private var canSubmit: Bool {
        guard amount.amount > 0 else { return false }
        if segment == .cardExpense {
            return cardId != nil
        }
        return true
    }

    private func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil

        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let dateString = DateFormatter.oniKeiriDay.string(from: date)
        let success: Bool
        if let editing {
            success = await onSubmit(.update(id: editing.id, UpdateEntryBodyDto(
                amount: amount.amount,
                date: dateString,
                category: segment == .income ? nil : category,
                incomeSource: segment == .income ? incomeSource : nil,
                note: trimmedNote.isEmpty ? nil : trimmedNote
            )))
        } else if segment == .income, incomeSource == .salary, includeBusinessExpenses, employmentType == .freelance {
            success = await onSubmit(.createSalary(CreateSalaryBodyDto(
                amount: amount.amount,
                date: dateString,
                note: trimmedNote.isEmpty ? nil : trimmedNote,
                expenses: businessExpenses.compactMap(\.dto)
            )))
        } else {
            success = await onSubmit(.create(CreateEntryBodyDto(
                kind: kind,
                amount: amount.amount,
                date: dateString,
                category: segment == .income ? nil : category,
                cardId: segment == .cardExpense ? cardId : nil,
                incomeSource: segment == .income ? incomeSource : nil,
                note: trimmedNote.isEmpty ? nil : trimmedNote
            )))
        }

        isSubmitting = false
        if success {
            dismiss()
        } else {
            errorMessage = "保存できませんでした。時間をおいて再試行してください。"
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

    private var kind: EntryKind {
        switch segment {
        case .expense: .expense
        case .income: .income
        case .cardExpense: .cardExpense
        }
    }

    private static func segment(for entry: EntryDto) -> EntrySegment {
        switch entry.kind {
        case .expense: .expense
        case .income: .income
        case .cardExpense: .cardExpense
        }
    }
}

private struct SegmentPicker: View {
    @Binding var segment: EntrySegment
    let cardsAvailable: Bool

    var body: some View {
        HStack(spacing: 8) {
            ForEach(EntrySegment.allCases) { item in
                Button(item.title) {
                    segment = item
                }
                .font(DS.Typo.caption.weight(.semibold))
                .foregroundStyle(segment == item ? .white : DS.Palette.textSub)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(segment == item ? DS.Palette.ink : DS.Palette.bgSoft, in: Capsule())
                .disabled(item == .cardExpense && !cardsAvailable)
                .opacity(item == .cardExpense && !cardsAvailable ? 0.45 : 1)
                .accessibilityIdentifier("segment-\(item.rawValue.replacingOccurrences(of: "cardExpense", with: "card"))")
            }
        }
    }
}

private struct CategoryChips: View {
    @Binding var selection: EntryCategory
    let employmentType: EmploymentType

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.rawValue) { category in
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
                    .accessibilityIdentifier(category.rawValue)
                }
            }
        }
    }

    private var categories: [EntryCategory] {
        EntryCategory.allCases.filter { $0 != .business || employmentType == .freelance }
    }
}

private struct CardChips: View {
    let cards: [CardDto]
    @Binding var selection: String?
    let onAddCard: () -> Void

    var body: some View {
        if cards.isEmpty {
            VStack(spacing: 10) {
                Text("カードを登録してください")
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.Palette.textSub)
                Button("カードを追加") {
                    onAddCard()
                }
                .font(DS.Typo.caption.weight(.semibold))
                .foregroundStyle(DS.Palette.teal)
            }
            .frame(maxWidth: .infinity)
            .padding(14)
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.card).stroke(DS.Palette.line))
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(cards) { card in
                        Button {
                            selection = card.id
                        } label: {
                            HStack(spacing: 8) {
                                CreditCardMini()
                                Text(card.name)
                            }
                        }
                        .font(DS.Typo.caption.weight(.semibold))
                        .foregroundStyle(selection == card.id ? .white : DS.Palette.text)
                        .padding(.horizontal, 12)
                        .frame(height: 40)
                        .background(selection == card.id ? DS.Palette.ink : DS.Palette.bgSoft, in: Capsule())
                    }
                }
            }
        }
    }
}

private struct IncomeControls: View {
    @Binding var incomeSource: IncomeSource
    @Binding var includeBusinessExpenses: Bool
    @Binding var businessExpenses: [BusinessExpenseInput]
    let employmentType: EmploymentType

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                incomeButton(.salary, title: "給与")
                incomeButton(.other, title: "その他")
            }

            if employmentType == .freelance && incomeSource == .salary {
                Toggle("経費も同時に入力", isOn: $includeBusinessExpenses)
                    .font(DS.Typo.body)
                    .tint(DS.Palette.teal)
                if includeBusinessExpenses {
                    VStack(spacing: 8) {
                        ForEach($businessExpenses) { $expense in
                            HStack(spacing: 8) {
                                TextField("経費メモ", text: $expense.note)
                                TextField("金額", value: $expense.amount, formatter: NumberFormatter())
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 96)
                            }
                            .font(DS.Typo.caption)
                            .padding(10)
                            .background(DS.Palette.bgSoft, in: RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous))
                        }
                        if businessExpenses.count < 20 {
                            Button("経費行を追加") {
                                businessExpenses.append(BusinessExpenseInput())
                            }
                            .font(DS.Typo.caption.weight(.semibold))
                            .foregroundStyle(DS.Palette.teal)
                        }
                    }
                }
            }
        }
    }

    private func incomeButton(_ source: IncomeSource, title: String) -> some View {
        Button(title) {
            incomeSource = source
        }
        .font(DS.Typo.caption.weight(.semibold))
        .foregroundStyle(incomeSource == source ? .white : DS.Palette.textSub)
        .frame(maxWidth: .infinity)
        .frame(height: 38)
        .background(incomeSource == source ? DS.Palette.ink : DS.Palette.bgSoft, in: Capsule())
    }
}

struct BusinessExpenseInput: Identifiable, Equatable {
    let id = UUID()
    var amount: Int = 0
    var note = ""

    var dto: CreateSalaryBodyDto.Expense? {
        guard amount > 0 else { return nil }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return .init(amount: amount, note: trimmed.isEmpty ? nil : trimmed)
    }
}

struct NumericKeypad: View {
    @Binding var amount: AmountInput
    private let keys: [KeypadKey] = [.digit(1), .digit(2), .digit(3), .digit(4), .digit(5), .digit(6), .digit(7), .digit(8), .digit(9), .doubleZero, .digit(0), .backspace]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(keys) { key in
                Button {
                    amount.tap(key)
                } label: {
                    Text(key.label)
                        .font(DS.Typo.title)
                        .foregroundStyle(DS.Palette.text)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(DS.Palette.bgSoft, in: RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous))
                }
            }
        }
    }
}

struct CreditCardMini: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color(hex: 0x17181C), Color(hex: 0x34353B)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 42, height: 28)
    }
}

struct FeaturePlaceholderView: View {
    let title: String

    var body: some View {
        Text(title)
            .font(DS.Typo.body)
            .foregroundStyle(DS.Palette.text)
            .navigationTitle(title)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DS.Palette.bg)
    }
}
