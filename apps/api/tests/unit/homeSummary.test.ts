import { describe, expect, it } from "vitest";
import { buildBreakdown, buildDailySeries, buildQuality } from "../../src/lib/homeSummary.js";

describe("homeSummary (§4.2/§4.6/§4.7)", () => {
  it("builds dailySeries with final value equal to remaining, projection boundary, and earliest min tie", () => {
    const result = buildDailySeries({
      month: "2026-08",
      today: "2026-08-20",
      entries: [
        { kind: "income", amount: 300_000, date: "2026-08-25" },
        { kind: "expense", amount: 1_490, date: "2026-08-27" },
      ],
      cardPayments: [{ paymentDate: "2026-08-10", amount: 18_000 }],
    });

    expect(result.series).toHaveLength(31);
    expect(result.series[0]).toEqual({ date: "2026-08-01", value: 0, projected: false });
    expect(result.series[9]).toEqual({ date: "2026-08-10", value: -18_000, projected: false });
    expect(result.series[19]).toEqual({ date: "2026-08-20", value: -18_000, projected: false });
    expect(result.series[20]).toEqual({ date: "2026-08-21", value: -18_000, projected: true });
    expect(result.series[24]).toEqual({ date: "2026-08-25", value: 282_000, projected: true });
    expect(result.series[26]).toEqual({ date: "2026-08-27", value: 280_510, projected: true });
    expect(result.series.at(-1)).toEqual({ date: "2026-08-31", value: 280_510, projected: true });
    expect(result.minPoint).toEqual({ date: "2026-08-10", value: -18_000 });
  });

  it("marks all points non-projected in past months and projected in future months", () => {
    expect(buildDailySeries({ month: "2026-07", today: "2026-08-20", entries: [], cardPayments: [] }).series.every((p) => !p.projected)).toBe(true);
    expect(buildDailySeries({ month: "2026-09", today: "2026-08-20", entries: [], cardPayments: [] }).series.every((p) => p.projected)).toBe(true);
  });

  it("merges null category into other, excludes income, and sorts descending", () => {
    expect(buildBreakdown([
      { kind: "expense", amount: 1_200, category: "food", date: "2026-08-01", sourceRuleId: null },
      { kind: "card_expense", amount: 2_000, category: null, date: "2026-08-02", sourceRuleId: null },
      { kind: "expense", amount: 3_000, category: "food", date: "2026-08-03", sourceRuleId: "rule-1" },
      { kind: "income", amount: 300_000, category: null, date: "2026-08-25", sourceRuleId: null },
      { kind: "expense", amount: 1_500, category: "other", date: "2026-08-04", sourceRuleId: null },
    ])).toEqual([
      { category: "food", amount: 4_200 },
      { category: "other", amount: 3_500 },
    ]);
  });

  it("splits quality by sourceRuleId and computes savingTip from variable spending", () => {
    expect(buildQuality([
      { kind: "expense", amount: 82_000, category: "housing", date: "2026-08-01", sourceRuleId: "rule-1" },
      { kind: "expense", amount: 20_000, category: "food", date: "2026-08-02", sourceRuleId: null },
      { kind: "card_expense", amount: 33_200, category: "daily", date: "2026-08-03", sourceRuleId: null },
      { kind: "income", amount: 300_000, category: null, date: "2026-08-25", sourceRuleId: "salary-rule" },
    ])).toEqual({ fixed: 82_000, variable: 53_200, savingTip: 5_320 });
  });
});
