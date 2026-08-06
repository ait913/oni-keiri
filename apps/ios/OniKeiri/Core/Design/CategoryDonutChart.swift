import Charts
import SwiftUI

struct CategoryDonutChart: View {
    let breakdown: [CategoryBreakdownDto]

    init(breakdown: [CategoryBreakdownDto]) {
        self.breakdown = breakdown
    }

    var body: some View {
        ZStack {
            if breakdown.isEmpty {
                Circle()
                    .fill(DS.Chart.cat6.opacity(0.3))
                Text("記録が\nありません")
                    .font(DS.Typo.labelS)
                    .foregroundStyle(DS.Palette.textSub)
                    .multilineTextAlignment(.center)
            } else {
                Chart(breakdown) { item in
                    SectorMark(
                        angle: .value("金額", item.amount),
                        innerRadius: .ratio(0.72),
                        angularInset: 1.5
                    )
                    .foregroundStyle(item.category.color)
                }
                .chartLegend(.hidden)
            }
        }
        .frame(width: 104, height: 104)
    }
}

struct CategoryRankingList: View {
    let breakdown: [CategoryBreakdownDto]

    init(breakdown: [CategoryBreakdownDto]) {
        self.breakdown = breakdown
    }

    var body: some View {
        VStack(spacing: 9) {
            ForEach(breakdown) { item in
                VStack(spacing: 4) {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(item.category.color)
                            .frame(width: 7, height: 7)
                        Text(item.category.displayName)
                            .font(DS.Typo.caption.weight(.semibold))
                            .foregroundStyle(DS.Palette.text)
                        Spacer()
                        Text(YenText.string(amount: item.amount))
                            .font(DS.Typo.caption)
                            .foregroundStyle(DS.Palette.text)
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(DS.Palette.bgSoft)
                            Capsule()
                                .fill(item.category.color)
                                .frame(width: proxy.size.width * ratio(for: item))
                        }
                    }
                    .frame(height: 4)
                }
            }
        }
    }

    private func ratio(for item: CategoryBreakdownDto) -> CGFloat {
        guard let max = breakdown.first?.amount, max > 0 else { return 0 }
        return CGFloat(item.amount) / CGFloat(max)
    }
}
