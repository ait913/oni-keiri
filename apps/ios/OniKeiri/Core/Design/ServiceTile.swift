import SwiftUI

struct ServiceTile: View {
    enum Size {
        case regular
        case small

        var side: CGFloat {
            switch self {
            case .regular: 36
            case .small: 24
            }
        }

        var radius: CGFloat {
            switch self {
            case .regular: 12
            case .small: 8
            }
        }

        var font: Font {
            switch self {
            case .regular: DS.Typo.body.weight(.semibold)
            case .small: DS.Typo.labelS
            }
        }
    }

    let initial: String
    let color: Color
    let size: Size

    init(initial: String, color: Color, size: Size = .regular) {
        self.initial = String(initial.prefix(1))
        self.color = color
        self.size = size
    }

    var body: some View {
        RoundedRectangle(cornerRadius: size.radius, style: .continuous)
            .fill(color)
            .frame(width: size.side, height: size.side)
            .overlay {
                Text(initial)
                    .font(size.font)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
    }
}
