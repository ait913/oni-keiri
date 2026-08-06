import Observation
import SwiftUI

struct CalendarView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var viewModel = CalendarViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.sectionGap) {
                CalendarMonthHeader(month: viewModel.month) { offset in
                    Task { await viewModel.moveMonth(by: offset, api: environment.api, auth: environment.auth) }
                }

                switch viewModel.state {
                case .loading:
                    LoadingPlaceholderCard(height: 360)
                case .error:
                    ContentUnavailableView {
                        Label("カレンダーを読み込めません", systemImage: "exclamationmark.triangle")
                    } actions: {
                        Button("再試行") { Task { await viewModel.load(api: environment.api, auth: environment.auth) } }
                    }
                case .loaded(let response):
                    MonthGrid(response: response)
                    PaymentScheduleCard(response: response)
                }
            }
            .padding(DS.Spacing.screenMargin)
        }
        .background(DS.Palette.bg)
        .navigationTitle("カレンダー")
        .task(id: environment.ticker.tick) {
            await viewModel.load(api: environment.api, auth: environment.auth)
        }
    }
}

@MainActor
@Observable
final class CalendarViewModel {
    enum State: Equatable {
        case loading
        case loaded(CalendarResponse)
        case error
    }

    var month: String = DateFormatter.oniKeiriMonth.string(from: Date())
    private(set) var state: State = .loading

    func load(api: APIClient, auth: AuthStore) async {
        state = .loading
        do {
            state = .loaded(try await api.calendar(month: month))
        } catch APIError.unauthorized {
            auth.handleUnauthorized()
        } catch {
            state = .error
        }
    }

    func moveMonth(by offset: Int, api: APIClient, auth: AuthStore) async {
        month = OniDateFormat.addMonths(month, by: offset)
        await load(api: api, auth: auth)
    }
}

private struct CalendarMonthHeader: View {
    let month: String
    let move: (Int) -> Void

    var body: some View {
        HStack {
            Button {
                move(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 40, height: 40)
                    .background(DS.Palette.bgSoft, in: Circle())
            }
            Spacer()
            Text(OniDateFormat.monthTitle(month))
                .font(DS.Typo.title)
                .foregroundStyle(DS.Palette.text)
            Spacer()
            Button {
                move(1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 40, height: 40)
                    .background(DS.Palette.bgSoft, in: Circle())
            }
        }
        .foregroundStyle(DS.Palette.text)
    }
}

private struct MonthGrid: View {
    let response: CalendarResponse
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    private let weekdays = ["日", "月", "火", "水", "木", "金", "土"]

    var body: some View {
        VStack(spacing: 8) {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(weekdays.enumerated()), id: \.offset) { index, label in
                    Text(label)
                        .font(DS.Typo.labelS)
                        .foregroundStyle(weekdayColor(index))
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(cells) { cell in
                    CalendarCell(cell: cell, events: eventsByDate[cell.date] ?? [], today: response.today)
                }
            }
        }
    }

    private var cells: [MonthCell] {
        guard let firstDate = DateFormatter.oniKeiriDay.date(from: "\(response.month)-01") else { return [] }
        var calendar = Foundation.Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        guard let range = calendar.range(of: .day, in: .month, for: firstDate) else { return [] }
        let weekday = calendar.component(.weekday, from: firstDate)
        var values: [MonthCell] = []
        for _ in 0..<(weekday - 1) {
            values.append(MonthCell(date: UUID().uuidString, day: nil))
        }
        for day in range {
            values.append(MonthCell(date: "\(response.month)-\(String(format: "%02d", day))", day: day))
        }
        while values.count % 7 != 0 {
            values.append(MonthCell(date: UUID().uuidString, day: nil))
        }
        return values
    }

    private var eventsByDate: [String: [CalendarEventDto]] {
        Dictionary(grouping: response.events, by: \.date)
    }

    private func weekdayColor(_ index: Int) -> Color {
        if index == 0 { return DS.Palette.red }
        if index == 6 { return DS.Palette.blue }
        return DS.Palette.textSub
    }
}

private struct MonthCell: Identifiable {
    let date: String
    let day: Int?
    var id: String { date }
}

private struct CalendarCell: View {
    let cell: MonthCell
    let events: [CalendarEventDto]
    let today: String

    var body: some View {
        VStack(spacing: 3) {
            if let day = cell.day {
                Text("\(day)")
                    .font(DS.Typo.labelS.weight(.semibold))
                    .foregroundStyle(cell.date == today ? .white : DS.Palette.text)
                    .frame(width: 22, height: 22)
                    .background(cell.date == today ? DS.Palette.ink : .clear, in: Circle())
                ForEach(Array(events.prefix(2))) { event in
                    eventIcon(event)
                }
                if events.count > 2 {
                    Text("+\(events.count - 2)")
                        .font(DS.Typo.labelS)
                        .foregroundStyle(DS.Palette.textSub)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 70)
        .background(cell.day == nil ? DS.Palette.bgSoft : DS.Palette.bg, in: RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.tile).stroke(DS.Palette.line))
    }

    @ViewBuilder
    private func eventIcon(_ event: CalendarEventDto) -> some View {
        switch event {
        case .cardPayment:
            CreditCardMini()
                .scaleEffect(0.58)
                .frame(width: 24, height: 16)
        case .fixedCost(_, let name, _, _, _, _, let category):
            ServiceTile(initial: name, color: category?.color ?? DS.Chart.cat6, size: .small)
        case .salary:
            ServiceTile(initial: "給", color: DS.Palette.teal, size: .small)
        }
    }
}

private struct PaymentScheduleCard: View {
    let response: CalendarResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(Int(response.month.suffix(2)) ?? 0)月の支払い予定 (\(response.paymentCount)件)")
                    .font(DS.Typo.heading)
                    .foregroundStyle(DS.Palette.textSub)
                Spacer()
                Text(YenText.string(amount: response.paymentTotal))
                    .font(DS.Typo.amountM)
                    .foregroundStyle(DS.Palette.text)
            }
            ForEach(paymentEvents) { event in
                switch event {
                case .cardPayment(let cardId, _, _, _, _, _, _):
                    NavigationLink {
                        CardDetailView(cardId: cardId)
                    } label: {
                        CalendarPaymentRow(event: event)
                    }
                    .foregroundStyle(DS.Palette.text)
                default:
                    CalendarPaymentRow(event: event)
                }
            }
        }
        .padding(DS.Spacing.cardPadding)
        .background(DS.Palette.bg)
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.card).stroke(DS.Palette.line))
    }

    private var paymentEvents: [CalendarEventDto] {
        response.events.filter {
            switch $0 {
            case .fixedCost, .cardPayment: true
            case .salary: false
            }
        }
    }
}

private struct CalendarPaymentRow: View {
    let event: CalendarEventDto

    var body: some View {
        HStack(spacing: 12) {
            Text(OniDateFormat.dayMonth(event.date))
                .font(DS.Typo.caption)
                .foregroundStyle(DS.Palette.textSub)
                .frame(width: 34, alignment: .leading)
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(DS.Typo.body.weight(.semibold))
                Text(subtitle)
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .lineLimit(1)
            }
            Spacer()
            Text(YenText.string(amount: event.amount))
                .font(DS.Typo.amountM)
            if case .cardPayment = event {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.Palette.textSub)
            }
        }
        .padding(.vertical, 9)
    }

    @ViewBuilder private var icon: some View {
        switch event {
        case .cardPayment:
            CreditCardMini()
        case .fixedCost(_, let name, _, _, _, _, let category):
            ServiceTile(initial: name, color: category?.color ?? DS.Chart.cat6)
        case .salary:
            ServiceTile(initial: "給", color: DS.Palette.teal)
        }
    }

    private var subtitle: String {
        switch event {
        case .fixedCost(_, _, _, _, _, let cardName, _):
            cardName.map { "\($0)カードから" } ?? "現金/口座"
        case .cardPayment(_, _, _, _, let fromExclusive, let toInclusive, _):
            "\(OniDateFormat.dayMonth(fromExclusive))〜\(OniDateFormat.dayMonth(toInclusive)) 利用分"
        case .salary:
            "自動計上"
        }
    }
}

extension DateFormatter {
    static let oniKeiriMonth: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Foundation.Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.dateFormat = "yyyy-MM"
        return formatter
    }()
}
