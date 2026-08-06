import SwiftUI

struct StackedQualityBar: View {
    let fixed: Int
    let variable: Int

    init(fixed: Int, variable: Int) {
        self.fixed = fixed
        self.variable = variable
    }

    var body: some View {
        if total > 0 {
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    DS.Palette.ink
                        .frame(width: proxy.size.width * CGFloat(fixed) / CGFloat(total))
                    DS.Palette.teal
                }
                .clipShape(Capsule())
            }
            .frame(height: 12)
        }
    }

    private var total: Int { fixed + variable }
}
