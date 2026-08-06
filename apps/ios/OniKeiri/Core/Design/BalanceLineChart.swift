import Charts
import SwiftUI

struct BalanceLineChart: View {
    let series: [DailyPointDto]
    let minPoint: MinPointDto
    let savingsGoal: Int?

    init(series: [DailyPointDto], minPoint: MinPointDto, savingsGoal: Int?) {
        self.series = series
        self.minPoint = minPoint
        self.savingsGoal = savingsGoal
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Chart {
                ForEach(actualPoints, id: \.date) { point in
                    AreaMark(
                        x: .value("日付", chartDate(point.date)),
                        y: .value("残高", point.value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [DS.Palette.ink.opacity(0.14), DS.Palette.ink.opacity(0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("日付", chartDate(point.date)),
                        y: .value("残高", point.value)
                    )
                    .foregroundStyle(DS.Palette.ink)
                    .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                }

                ForEach(projectedPoints, id: \.date) { point in
                    LineMark(
                        x: .value("日付", chartDate(point.date)),
                        y: .value("残高", point.value)
                    )
                    .foregroundStyle(DS.Chart.projected)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [4, 5]))
                }

                if let todayPoint = actualPoints.last {
                    RuleMark(x: .value("今日", chartDate(todayPoint.date)))
                        .foregroundStyle(DS.Palette.ink.opacity(0.12))
                    PointMark(
                        x: .value("今日", chartDate(todayPoint.date)),
                        y: .value("残高", todayPoint.value)
                    )
                    .symbolSize(42)
                    .foregroundStyle(.white)
                    .annotation(position: .overlay) {
                        Circle()
                            .stroke(DS.Palette.ink, lineWidth: 2)
                            .frame(width: 9, height: 9)
                    }
                }

                if let savingsGoal {
                    RuleMark(y: .value("貯金目標", savingsGoal))
                        .foregroundStyle(DS.Palette.teal.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .annotation(position: .top, alignment: .trailing) {
                            Text("貯金目標 \(YenText.string(amount: savingsGoal))")
                                .font(DS.Typo.labelS)
                                .foregroundStyle(DS.Palette.teal)
                        }
                }

                PointMark(
                    x: .value("最低残高", chartDate(minPoint.date)),
                    y: .value("最低残高", minPoint.value)
                )
                .symbolSize(36)
                .foregroundStyle(DS.Chart.minDot)
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                        .foregroundStyle(DS.Chart.grid)
                    AxisValueLabel()
                        .font(DS.Typo.labelS)
                        .foregroundStyle(DS.Palette.textSub)
                }
            }
            .frame(height: 128)
            .accessibilityIdentifier("balance-chart")

            HStack(spacing: 6) {
                Circle()
                    .fill(minPoint.value >= 0 ? DS.Palette.teal : DS.Palette.red)
                    .frame(width: 7, height: 7)
                Text("最低残高 \(shortDate(minPoint.date)) — \(statusText)")
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .lineLimit(2)
                Spacer(minLength: 8)
                YenText(amount: minPoint.value, style: .amountM)
            }
        }
    }

    private var actualPoints: [DailyPointDto] {
        series.filter { !$0.projected }
    }

    private var projectedPoints: [DailyPointDto] {
        let projected = series.filter(\.projected)
        guard !projected.isEmpty else { return [] }
        if let lastActual = actualPoints.last, lastActual.date != projected.first?.date {
            return [lastActual] + projected
        }
        return projected
    }

    private var statusText: String {
        minPoint.value >= 0 ? "支払いはすべて足りる見込み" : "支払いに足りない日があります"
    }

    private func chartDate(_ date: String) -> Date {
        DateFormatter.oniKeiriDay.date(from: date) ?? .distantPast
    }

    private func shortDate(_ date: String) -> String {
        let parts = date.split(separator: "-")
        guard parts.count == 3, let month = Int(parts[1]), let day = Int(parts[2]) else { return date }
        return "\(month)/\(day)"
    }
}
