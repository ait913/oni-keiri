import { describe, expect, it, vi } from "vitest";
import { cardPaymentSchedule, cardUtilization, cycleRange } from "../../src/lib/cardSchedule.js";

describe("cardSchedule (§4.3)", () => {
  it("encodes E-1: lump-sum, closing 15, payment 10", () => {
    vi.setSystemTime(new Date("2026-08-20T03:00:00Z"));
    const card = { closingDay: 15, paymentDay: 10, revolvingAmount: null, carryoverBalance: 0, createdDate: "2026-08-01" };
    const expenses = [
      { date: "2026-08-10", amount: 3_000 },
      { date: "2026-08-20", amount: 5_000 },
    ];

    expect(cycleRange(card, "2026-09")).toEqual({ fromExclusive: "2026-07-15", toInclusive: "2026-08-15" });
    expect(cardPaymentSchedule(card, expenses, "2026-10")).toEqual([
      {
        month: "2026-09",
        paymentDate: "2026-09-10",
        amount: 3_000,
        fromExclusive: "2026-07-15",
        toInclusive: "2026-08-15",
        closed: true,
        balanceAfter: 0,
      },
      {
        month: "2026-10",
        paymentDate: "2026-10-10",
        amount: 5_000,
        fromExclusive: "2026-08-15",
        toInclusive: "2026-09-15",
        closed: false,
        balanceAfter: 0,
      },
    ]);
  });

  it("encodes E-2: revolving payment with carryover recurrence and utilization", () => {
    vi.setSystemTime(new Date("2026-08-20T03:00:00Z"));
    const card = { closingDay: 31, paymentDay: 27, revolvingAmount: 10_000, carryoverBalance: 25_000, createdDate: "2026-08-01" };
    const expenses = [{ date: "2026-08-05", amount: 8_000 }];

    expect(cardPaymentSchedule(card, expenses, "2026-12").map((p) => ({
      month: p.month,
      paymentDate: p.paymentDate,
      amount: p.amount,
      balanceAfter: p.balanceAfter,
    }))).toEqual([
      { month: "2026-09", paymentDate: "2026-09-27", amount: 10_000, balanceAfter: 23_000 },
      { month: "2026-10", paymentDate: "2026-10-27", amount: 10_000, balanceAfter: 13_000 },
      { month: "2026-11", paymentDate: "2026-11-27", amount: 10_000, balanceAfter: 3_000 },
      { month: "2026-12", paymentDate: "2026-12-27", amount: 3_000, balanceAfter: 0 },
    ]);
    expect(cardUtilization(card, expenses, "2026-08-20")).toBe(33_000);
  });

  it("clamps month-end closing/payment days, excludes pre-created closed cycles, and handles closed boundary", () => {
    vi.setSystemTime(new Date("2026-08-15T03:00:00Z"));
    const monthEnd = { closingDay: 31, paymentDay: 31, revolvingAmount: null, carryoverBalance: 0, createdDate: "2026-12-01" };
    expect(cycleRange(monthEnd, "2027-02")).toEqual({ fromExclusive: "2026-12-31", toInclusive: "2027-01-31" });
    expect(cardPaymentSchedule(monthEnd, [], "2027-02").at(-1)?.paymentDate).toBe("2027-02-28");

    const afterClosingCreation = { closingDay: 15, paymentDay: 10, revolvingAmount: null, carryoverBalance: 0, createdDate: "2026-08-18" };
    const schedule = cardPaymentSchedule(afterClosingCreation, [{ date: "2026-08-10", amount: 3_000 }], "2026-10");
    expect(schedule).toHaveLength(1);
    expect(schedule[0]).toMatchObject({ month: "2026-10", amount: 0 });

    const boundary = { closingDay: 15, paymentDay: 10, revolvingAmount: null, carryoverBalance: 0, createdDate: "2026-08-01" };
    expect(cardPaymentSchedule(boundary, [{ date: "2026-08-10", amount: 1_000 }], "2026-09")[0]?.closed).toBe(false);
    vi.setSystemTime(new Date("2026-08-16T00:00:00Z"));
    expect(cardPaymentSchedule(boundary, [{ date: "2026-08-10", amount: 1_000 }], "2026-09")[0]?.closed).toBe(true);
  });
});
