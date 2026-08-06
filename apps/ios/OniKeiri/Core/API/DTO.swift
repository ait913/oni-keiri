import Foundation

enum EntryKind: String, Codable {
    case expense
    case cardExpense = "card_expense"
    case income
}

enum IncomeSource: String, Codable {
    case salary
    case other
}

enum EntryCategory: String, Codable, CaseIterable {
    case food
    case daily
    case transport
    case entertainment
    case housing
    case business
    case health
    case other
}

enum EmploymentType: String, Codable, CaseIterable, Identifiable {
    case employee
    case freelance
    case partTime = "part_time"
    case contract

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .employee: "会社員"
        case .freelance: "個人事業主"
        case .partTime: "アルバイト・パート"
        case .contract: "契約・派遣"
        }
    }
}

enum RuleDirection: String, Codable {
    case expense
    case income
}

struct SettingsDto: Codable, Equatable {
    let employmentType: EmploymentType
    let savingsGoal: Int?
}

struct MeResponse: Codable, Equatable {
    struct User: Codable, Equatable {
        let id: String
        let name: String?
        let email: String?
    }

    let user: User
    let onboarded: Bool
    let settings: SettingsDto?
}

struct EntryDto: Codable, Identifiable, Equatable {
    let id: String
    let kind: EntryKind
    let amount: Int
    let date: String
    let yearMonth: String
    let category: EntryCategory?
    let cardId: String?
    let incomeSource: IncomeSource?
    let note: String?
    let sourceRuleId: String?
    let isManuallyEdited: Bool
}

struct DailyPointDto: Codable, Equatable {
    let date: String
    let value: Int
    let projected: Bool
}

struct MinPointDto: Codable, Equatable {
    let date: String
    let value: Int
}

struct CategoryBreakdownDto: Codable, Equatable, Identifiable {
    let category: EntryCategory
    let amount: Int

    var id: String { category.rawValue }
}

enum CalendarEventDto: Codable, Equatable, Identifiable {
    case fixedCost(entryId: String, name: String, date: String, amount: Int, cardId: String?, cardName: String?, category: EntryCategory?)
    case cardPayment(cardId: String, cardName: String, date: String, amount: Int, fromExclusive: String, toInclusive: String, closed: Bool)
    case salary(entryId: String, name: String, date: String, amount: Int)

    enum CodingKeys: String, CodingKey {
        case type
        case entryId
        case name
        case date
        case amount
        case cardId
        case cardName
        case category
        case fromExclusive
        case toInclusive
        case closed
    }

    var id: String {
        switch self {
        case .fixedCost(let entryId, _, _, _, _, _, _), .salary(let entryId, _, _, _):
            entryId
        case .cardPayment(let cardId, _, let date, _, _, _, _):
            "\(cardId)-\(date)"
        }
    }

    var date: String {
        switch self {
        case .fixedCost(_, _, let date, _, _, _, _), .cardPayment(_, _, let date, _, _, _, _), .salary(_, _, let date, _):
            date
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "fixed_cost":
            self = .fixedCost(
                entryId: try container.decode(String.self, forKey: .entryId),
                name: try container.decode(String.self, forKey: .name),
                date: try container.decode(String.self, forKey: .date),
                amount: try container.decode(Int.self, forKey: .amount),
                cardId: try container.decodeIfPresent(String.self, forKey: .cardId),
                cardName: try container.decodeIfPresent(String.self, forKey: .cardName),
                category: try container.decodeIfPresent(EntryCategory.self, forKey: .category)
            )
        case "card_payment":
            self = .cardPayment(
                cardId: try container.decode(String.self, forKey: .cardId),
                cardName: try container.decode(String.self, forKey: .cardName),
                date: try container.decode(String.self, forKey: .date),
                amount: try container.decode(Int.self, forKey: .amount),
                fromExclusive: try container.decode(String.self, forKey: .fromExclusive),
                toInclusive: try container.decode(String.self, forKey: .toInclusive),
                closed: try container.decode(Bool.self, forKey: .closed)
            )
        case "salary":
            self = .salary(
                entryId: try container.decode(String.self, forKey: .entryId),
                name: try container.decode(String.self, forKey: .name),
                date: try container.decode(String.self, forKey: .date),
                amount: try container.decode(Int.self, forKey: .amount)
            )
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown calendar event type: \(type)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .fixedCost(let entryId, let name, let date, let amount, let cardId, let cardName, let category):
            try container.encode("fixed_cost", forKey: .type)
            try container.encode(entryId, forKey: .entryId)
            try container.encode(name, forKey: .name)
            try container.encode(date, forKey: .date)
            try container.encode(amount, forKey: .amount)
            try container.encodeIfPresent(cardId, forKey: .cardId)
            try container.encodeIfPresent(cardName, forKey: .cardName)
            try container.encodeIfPresent(category, forKey: .category)
        case .cardPayment(let cardId, let cardName, let date, let amount, let fromExclusive, let toInclusive, let closed):
            try container.encode("card_payment", forKey: .type)
            try container.encode(cardId, forKey: .cardId)
            try container.encode(cardName, forKey: .cardName)
            try container.encode(date, forKey: .date)
            try container.encode(amount, forKey: .amount)
            try container.encode(fromExclusive, forKey: .fromExclusive)
            try container.encode(toInclusive, forKey: .toInclusive)
            try container.encode(closed, forKey: .closed)
        case .salary(let entryId, let name, let date, let amount):
            try container.encode("salary", forKey: .type)
            try container.encode(entryId, forKey: .entryId)
            try container.encode(name, forKey: .name)
            try container.encode(date, forKey: .date)
            try container.encode(amount, forKey: .amount)
        }
    }
}

struct CalendarResponse: Codable, Equatable {
    let month: String
    let today: String
    let events: [CalendarEventDto]
    let paymentCount: Int
    let paymentTotal: Int
}

struct HomeResponse: Codable, Equatable {
    let today: String
    let month: String
    let spendable: Int
    let remaining: Int
    let income: Int
    let spending: Int
    let cashExpense: Int
    let cardPaymentDue: Int
    let cardUsage: Int
    let savingsGoal: Int?
    let dailySeries: [DailyPointDto]
    let minPoint: MinPointDto
    let upcomingPayments: [CalendarEventDto]
    let upcomingTotal: Int
    let employmentType: EmploymentType
}

struct EntriesResponse: Codable, Equatable {
    struct Quality: Codable, Equatable {
        let fixed: Int
        let variable: Int
        let savingTip: Int
    }

    let entries: [EntryDto]
    let breakdown: [CategoryBreakdownDto]
    let quality: Quality
}

struct CardDto: Codable, Identifiable, Equatable {
    struct NextPayment: Codable, Equatable {
        let month: String
        let paymentDate: String
        let amount: Int
        let closed: Bool
    }

    let id: String
    let name: String
    let closingDay: Int
    let paymentDay: Int
    let revolvingAmount: Int?
    let creditLimit: Int?
    let carryoverBalance: Int
    let archived: Bool
    let utilization: Int
    let monthUsage: Int
    let nextPayment: NextPayment?
}

struct CardDetailResponse: Codable, Equatable {
    struct Payment: Codable, Equatable {
        let month: String
        let paymentDate: String
        let amount: Int
        let fromExclusive: String
        let toInclusive: String
        let closed: Bool
        let balanceAfter: Int
    }

    let card: CardDto
    let payments: [Payment]
    let recentExpenses: [EntryDto]
    let linkedRules: [RecurringRuleDto]
}

struct RecurringRuleDto: Codable, Identifiable, Equatable {
    let id: String
    let direction: RuleDirection
    let name: String
    let amount: Int
    let dayOfMonth: Int
    let cardId: String?
    let category: EntryCategory?
    let startMonth: String
    let active: Bool
}

struct TaxEstimateResponse: Codable, Equatable {
    let year: Int
    let businessIncomeYtd: Int
    let businessExpenseYtd: Int
    let profitYtd: Int
    let rate: Double
    let estimatedTax: Int
    let monthlySetAside: Int
    let annualProjection: Int
}

struct SalaryResponseDto: Codable, Equatable {
    let income: EntryDto
    let expenses: [EntryDto]
}

struct CreateEntryBodyDto: Encodable {
    let kind: EntryKind
    let amount: Int
    let date: String
    let category: EntryCategory?
    let cardId: String?
    let incomeSource: IncomeSource?
    let note: String?
}

struct CreateSalaryBodyDto: Encodable {
    struct Expense: Encodable, Equatable {
        let amount: Int
        let note: String?
    }

    let amount: Int
    let date: String
    let note: String?
    let expenses: [Expense]
}

struct UpdateEntryBodyDto: Encodable {
    let amount: Int?
    let date: String?
    let category: EntryCategory?
    let incomeSource: IncomeSource?
    let note: String?
}

struct CardFormBodyDto: Encodable {
    let name: String
    let closingDay: Int
    let paymentDay: Int
    let revolvingAmount: Int?
    let creditLimit: Int?
    let carryoverBalance: Int
}

struct CardUpdateBodyDto: Encodable {
    let name: String?
    let closingDay: Int?
    let paymentDay: Int?
    let revolvingAmount: Int?
    let creditLimit: Int?
    let carryoverBalance: Int?
    let archived: Bool?
}

struct RuleFormBodyDto: Encodable {
    let direction: RuleDirection
    let name: String
    let amount: Int
    let dayOfMonth: Int
    let cardId: String?
    let category: EntryCategory?
}

struct RuleUpdateBodyDto: Encodable {
    let name: String?
    let amount: Int?
    let dayOfMonth: Int?
    let cardId: String?
    let category: EntryCategory?
    let active: Bool?
}
