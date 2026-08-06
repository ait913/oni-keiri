import Foundation
import SwiftUI

extension DateFormatter {
    static let oniKeiriDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

enum OniDateFormat {
    static func monthTitle(_ month: String) -> String {
        let parts = month.split(separator: "-")
        guard parts.count == 2, let year = Int(parts[0]), let month = Int(parts[1]) else { return month }
        return "\(year)年\(month)月"
    }

    static func dayMonth(_ date: String) -> String {
        let parts = date.split(separator: "-")
        guard parts.count == 3, let month = Int(parts[1]), let day = Int(parts[2]) else { return date }
        return "\(month)/\(day)"
    }

    static func dayHeading(_ date: String) -> String {
        guard let value = DateFormatter.oniKeiriDay.date(from: date) else { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.dateFormat = "M月d日 E"
        return formatter.string(from: value)
    }

    static func addMonths(_ month: String, by offset: Int) -> String {
        let parts = month.split(separator: "-")
        guard parts.count == 2, let year = Int(parts[0]), let monthNumber = Int(parts[1]) else { return month }
        var components = DateComponents()
        components.year = year
        components.month = monthNumber + offset
        components.day = 1
        let calendar = Calendar(identifier: .gregorian)
        guard let date = calendar.date(from: components) else { return month }
        let out = DateFormatter()
        out.calendar = calendar
        out.locale = Locale(identifier: "en_US_POSIX")
        out.dateFormat = "yyyy-MM"
        return out.string(from: date)
    }

    static func remainingDays(today: String) -> Int {
        guard let date = DateFormatter.oniKeiriDay.date(from: today) else { return 0 }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        guard let range = calendar.range(of: .day, in: .month, for: date) else { return 0 }
        let day = calendar.component(.day, from: date)
        return max(0, range.count - day)
    }
}

extension EntryCategory {
    var systemImage: String {
        switch self {
        case .food: "fork.knife"
        case .daily: "basket"
        case .transport: "tram"
        case .entertainment: "gamecontroller"
        case .housing: "house"
        case .business: "briefcase"
        case .health: "cross.case"
        case .other: "ellipsis.circle"
        }
    }
}

extension CalendarEventDto {
    var amount: Int {
        switch self {
        case .fixedCost(_, _, _, let amount, _, _, _), .cardPayment(_, _, _, let amount, _, _, _), .salary(_, _, _, let amount):
            amount
        }
    }

    var title: String {
        switch self {
        case .fixedCost(_, let name, _, _, _, _, _), .cardPayment(_, let name, _, _, _, _, _), .salary(_, let name, _, _):
            name
        }
    }
}

struct LoadingPlaceholderCard: View {
    let height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
            .fill(DS.Palette.bg)
            .frame(height: height)
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.card).stroke(DS.Palette.line))
            .overlay(ProgressView())
    }
}
