import SwiftUI

struct YenText: View {
    enum Style {
        case display
        case displayS
        case amountL
        case amountM
    }

    let amount: Int
    let style: Style
    let positive: Bool

    init(amount: Int, style: Style, positive: Bool = false) {
        self.amount = amount
        self.style = style
        self.positive = positive
    }

    var body: some View {
        Text(Self.string(amount: amount, positive: positive))
            .font(font)
            .foregroundStyle(color)
            .monospacedDigit()
    }

    static func string(amount: Int, positive: Bool = false) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "ja_JP")
        let formatted = formatter.string(from: NSNumber(value: abs(amount))) ?? "\(abs(amount))"
        if amount < 0 {
            return "-¥\(formatted)"
        }
        if positive {
            return "+¥\(formatted)"
        }
        return "¥\(formatted)"
    }

    private var font: Font {
        switch style {
        case .display: DS.Typo.display
        case .displayS: DS.Typo.displayS
        case .amountL: DS.Typo.amountL
        case .amountM: DS.Typo.amountM
        }
    }

    private var color: Color {
        if amount < 0 {
            DS.Palette.red
        } else if positive {
            DS.Palette.teal
        } else {
            DS.Palette.text
        }
    }
}
