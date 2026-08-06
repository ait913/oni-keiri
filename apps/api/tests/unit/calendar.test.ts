import { describe, expect, it } from "vitest";
import { buildCalendarEvents } from "../../src/lib/calendar.js";

describe("calendar events (§4.7)", () => {
  it("emits fixed costs, card payments, and salary, with cash-outflow payment totals", () => {
    const result = buildCalendarEvents({
      month: "2026-08",
      entries: [
        { id: "rent-entry", kind: "expense", amount: 80_000, date: "2026-08-01", note: "家賃", sourceRuleId: "rent-rule", cardId: null, category: "housing" },
        { id: "netflix-entry", kind: "card_expense", amount: 1_490, date: "2026-08-15", note: "Netflix", sourceRuleId: "netflix-rule", cardId: "card-1", category: "entertainment" },
        { id: "salary-entry", kind: "income", amount: 280_000, date: "2026-08-25", note: "給与", sourceRuleId: "salary-rule", cardId: null, category: null },
        { id: "manual-entry", kind: "expense", amount: 1_000, date: "2026-08-10", note: "manual", sourceRuleId: null, cardId: null, category: "food" },
      ],
      cardPayments: [{
        cardId: "card-1",
        cardName: "楽天カード",
        paymentDate: "2026-08-27",
        amount: 18_000,
        fromExclusive: "2026-06-30",
        toInclusive: "2026-07-31",
        closed: true,
      }],
      cardNamesById: { "card-1": "楽天カード" },
    });

    expect(result.events.map((e) => e.type)).toEqual(["fixed_cost", "fixed_cost", "salary", "card_payment"]);
    expect(result.events.map((e) => e.date)).toEqual(["2026-08-01", "2026-08-15", "2026-08-25", "2026-08-27"]);
    expect(result.paymentCount).toBe(3);
    expect(result.paymentTotal).toBe(98_000);
  });
});
