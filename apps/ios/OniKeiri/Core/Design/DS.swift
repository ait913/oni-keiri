import SwiftUI

enum DS {
    enum Palette {
        static let bg = Color(hex: 0xFFFFFF)
        static let bgSoft = Color(hex: 0xF5F6F5)
        static let line = Color(hex: 0xEFEFF1)
        static let cell = Color(hex: 0xF4F4F5)
        static let text = Color(hex: 0x17181A)
        static let textSub = Color(hex: 0x8E9097)
        static let ink = Color(hex: 0x121316)
        static let teal = Color(hex: 0x2E9E8F)
        static let tealSoft = Color(hex: 0xE7F3F0)
        static let red = Color(hex: 0xE60033)
        static let heroTeal = Color(hex: 0x6FD3C5)
    }

    enum Chart {
        static let cat1 = Color(hex: 0xE60033)
        static let cat2 = Color(hex: 0xFF9500)
        static let cat3 = Color(hex: 0x5856D6)
        static let cat4 = Color(hex: 0x34C759)
        static let cat5 = Color(hex: 0x00A8C6)
        static let cat6 = Color(hex: 0x8E8E93)
        static let cat7 = Color(hex: 0xAF52DE)
        static let cat8 = Color(hex: 0xA2845E)
        static let grid = Color(hex: 0xEEEEF0)
        static let projected = Color(hex: 0xB9BCC4)
        static let minDot = Color(hex: 0xFF9500)
    }

    enum Typo {
        static let display = Font.system(size: 40, weight: .bold).monospacedDigit()
        static let displayS = Font.system(size: 34, weight: .bold).monospacedDigit()
        static let amountL = Font.system(size: 26, weight: .bold).monospacedDigit()
        static let amountM = Font.system(size: 17, weight: .semibold).monospacedDigit()
        static let title = Font.system(size: 19, weight: .bold).monospacedDigit()
        static let heading = Font.system(size: 14, weight: .semibold).monospacedDigit()
        static let body = Font.system(size: 15, weight: .regular).monospacedDigit()
        static let caption = Font.system(size: 12, weight: .medium).monospacedDigit()
        static let labelS = Font.system(size: 11, weight: .medium).monospacedDigit()
    }

    enum Radius {
        static let hero: CGFloat = 24
        static let card: CGFloat = 18
        static let tile: CGFloat = 12
    }

    enum Spacing {
        static let screenMargin: CGFloat = 16
        static let cardPadding: CGFloat = 16
        static let gridGap: CGFloat = 10
        static let sectionGap: CGFloat = 14
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

private struct InkSurfaceModifier: ViewModifier {
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    LinearGradient(
                        colors: [Color(hex: 0x17181C), Color(hex: 0x26272C)],
                        startPoint: UnitPoint(x: 0.15, y: 0),
                        endPoint: UnitPoint(x: 0.85, y: 1)
                    )
                    RadialGradient(
                        colors: [Color.white.opacity(0.10), Color.white.opacity(0)],
                        center: UnitPoint(x: 0.82, y: 0.18),
                        startRadius: 0,
                        endRadius: 220
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

extension View {
    func dsInkSurface(radius: CGFloat = DS.Radius.hero) -> some View {
        modifier(InkSurfaceModifier(radius: radius))
    }
}

extension EntryCategory {
    var displayName: String {
        switch self {
        case .food: "食費"
        case .daily: "日用品"
        case .transport: "交通"
        case .entertainment: "娯楽"
        case .housing: "住居"
        case .business: "経費"
        case .health: "医療"
        case .other: "その他"
        }
    }

    var color: Color {
        switch self {
        case .food: DS.Chart.cat1
        case .daily: DS.Chart.cat8
        case .transport: DS.Chart.cat2
        case .entertainment: DS.Chart.cat4
        case .housing: DS.Chart.cat3
        case .business: DS.Chart.cat5
        case .health: DS.Chart.cat7
        case .other: DS.Chart.cat6
        }
    }
}
