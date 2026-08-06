import { randomUUID } from "node:crypto";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { apiJson, authHeaders, createTestUser, expectError, pool, postJson, putSettings, resetTestDb } from "../setup/api.js";

type HomeResponse = {
  today: string; month: string; spendable: number; remaining: number; income: number; spending: number;
  cashExpense: number; cardPaymentDue: number; cardUsage: number; savingsGoal: number | null;
  dailySeries: Array<{ date: string; value: number; projected: boolean }>;
  minPoint: { date: string; value: number };
  upcomingPayments: Array<{ type: string; date: string; amount: number; cardId?: string | null }>;
  upcomingTotal: number; employmentType: string;
};
type CalendarResponse = { month: string; today: string; events: Array<{ type: string; date: string; amount: number; cardName?: string | null }>; paymentCount: number; paymentTotal: number };
type TaxEstimateResponse = { year: number; businessIncomeYtd: number; businessExpenseYtd: number; profitYtd: number; rate: number; estimatedTax: number; monthlySetAside: number; annualProjection: number };

describe("B-HOME, B-CHART, B-CAL, B-TAX, and B-TZ", () => {
  beforeEach(async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-08-20T03:00:00Z"));
    await resetTestDb();
  });

  it("returns the empty home shape and default zero series", async () => {
    const user = await createTestUser();
    await putSettings(user.token, "employee");
    const res = await apiJson("/api/home?month=2026-08", { headers: authHeaders(user.token) });
    expect(res.status).toBe(200);
    const home = (await res.json()) as HomeResponse;
    expect(home).toMatchObject({ today: "2026-08-20", month: "2026-08", spendable: 0, remaining: 0, upcomingPayments: [], upcomingTotal: 0 });
    expect(home.dailySeries).toHaveLength(31);
    expect(home.dailySeries.every((p) => p.value === 0)).toBe(true);
  });

  it("computes E-3 remaining/spendable and keeps card usage out of remaining", async () => {
    const user = await createTestUser();
    await putSettings(user.token, "freelance", 100_000);
    await postJson("/api/entries", user.token, { kind: "income", amount: 300_000, date: "2026-08-01", incomeSource: "salary" });
    await postJson("/api/entries", user.token, { kind: "expense", amount: 45_000, date: "2026-08-02", category: "food" });

    const cardId = randomUUID();
    await pool.query(
      "INSERT INTO card (id, user_id, name, closing_day, payment_day, revolving_amount, credit_limit, carryover_balance, created_date, archived, created_at, updated_at) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,false,now(),now())",
      [cardId, user.userId, "楽天カード", 31, 10, null, null, 18_000, "2026-07-01"],
    );
    await postJson("/api/entries", user.token, { kind: "card_expense", amount: 99_999, date: "2026-08-03", category: "daily", cardId });

    const home = (await (await apiJson("/api/home?month=2026-08", { headers: authHeaders(user.token) })).json()) as HomeResponse;
    expect(home).toMatchObject({
      income: 300_000,
      cashExpense: 45_000,
      cardPaymentDue: 18_000,
      cardUsage: 99_999,
      spending: 63_000,
      remaining: 237_000,
      spendable: 137_000,
      savingsGoal: 100_000,
    });
    expect(home.dailySeries.at(-1)?.value).toBe(home.remaining);
  });

  it("builds B-CHART-3 series, projection boundaries, minPoint, and soft-delete recalculation", async () => {
    const user = await createTestUser();
    await putSettings(user.token, "freelance");
    await postJson("/api/recurring-rules", user.token, { direction: "income", name: "給与", amount: 300_000, dayOfMonth: 25 });
    const fixedRule = await postJson("/api/recurring-rules", user.token, { direction: "expense", name: "定額", amount: 1_490, dayOfMonth: 27, category: "daily" });
    expect(fixedRule.status).toBe(201);
    const cardId = randomUUID();
    await pool.query(
      "INSERT INTO card (id, user_id, name, closing_day, payment_day, revolving_amount, credit_limit, carryover_balance, created_date, archived, created_at, updated_at) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,false,now(),now())",
      [cardId, user.userId, "カード", 31, 10, null, null, 18_000, "2026-07-01"],
    );

    const home = (await (await apiJson("/api/home?month=2026-08", { headers: authHeaders(user.token) })).json()) as HomeResponse;
    expect(home.dailySeries).toHaveLength(31);
    expect(home.dailySeries[9]).toEqual({ date: "2026-08-10", value: -18_000, projected: false });
    expect(home.dailySeries[24]).toEqual({ date: "2026-08-25", value: 282_000, projected: true });
    expect(home.dailySeries[26]).toEqual({ date: "2026-08-27", value: 280_510, projected: true });
    expect(home.minPoint).toEqual({ date: "2026-08-10", value: -18_000 });

    const fixedEntry = home.upcomingPayments.find((p) => p.type === "fixed_cost" && p.date === "2026-08-27");
    expect(fixedEntry).toBeDefined();
    const entries = await apiJson("/api/entries?month=2026-08", { headers: authHeaders(user.token) });
    const entryBody = (await entries.json()) as { entries: Array<{ id: string; date: string; amount: number }> };
    const generated = entryBody.entries.find((e) => e.date === "2026-08-27" && e.amount === 1_490);
    expect(generated).toBeDefined();
    expect((await apiJson(`/api/entries/${generated?.id}`, { method: "DELETE", headers: authHeaders(user.token) })).status).toBe(204);

    const recalculated = (await (await apiJson("/api/home?month=2026-08", { headers: authHeaders(user.token) })).json()) as HomeResponse;
    expect(recalculated.dailySeries[26]).toEqual({ date: "2026-08-27", value: 282_000, projected: true });
  });

  it("calendar events include fixed/card/salary rows and exclude card-linked fixed costs from paymentTotal", async () => {
    const user = await createTestUser();
    await putSettings(user.token, "freelance");
    const cardId = randomUUID();
    await pool.query(
      "INSERT INTO card (id, user_id, name, closing_day, payment_day, revolving_amount, credit_limit, carryover_balance, created_date, archived, created_at, updated_at) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,false,now(),now())",
      [cardId, user.userId, "楽天カード", 31, 27, null, null, 0, "2026-07-01"],
    );
    await postJson("/api/recurring-rules", user.token, { direction: "expense", name: "家賃", amount: 80_000, dayOfMonth: 1, category: "housing" });
    await postJson("/api/recurring-rules", user.token, { direction: "expense", name: "Netflix", amount: 1_490, dayOfMonth: 15, cardId, category: "entertainment" });
    await postJson("/api/recurring-rules", user.token, { direction: "income", name: "給与", amount: 280_000, dayOfMonth: 25 });
    await postJson("/api/entries", user.token, { kind: "card_expense", amount: 18_000, date: "2026-07-20", category: "daily", cardId });
    await postJson("/api/entries", user.token, { kind: "expense", amount: 1_000, date: "2026-08-10", category: "food" });

    const res = await apiJson("/api/calendar?month=2026-08", { headers: authHeaders(user.token) });
    const body = (await res.json()) as CalendarResponse;
    expect(body.events.map((e) => [e.type, e.date, e.cardName ?? null])).toEqual([
      ["fixed_cost", "2026-08-01", null],
      ["fixed_cost", "2026-08-15", "楽天カード"],
      ["salary", "2026-08-25", null],
      ["card_payment", "2026-08-27", "楽天カード"],
    ]);
    // paymentCount = 家賃 + Netflix + card_payment. paymentTotal = 80,000 cash fixed cost + 18,000 card payment; Netflix is card-linked and already included in card withdrawal.
    expect(body.paymentCount).toBe(3);
    expect(body.paymentTotal).toBe(98_000);
    await expectError(await apiJson("/api/calendar", { headers: authHeaders(user.token) }), 400, "VALIDATION_FAILED");
  });

  it("estimates freelance tax from YTD salary income and business expenses only", async () => {
    const user = await createTestUser();
    await putSettings(user.token, "freelance");
    await postJson("/api/entries", user.token, { kind: "income", amount: 1_800_000, date: "2026-08-20", incomeSource: "salary" });
    await postJson("/api/entries", user.token, { kind: "income", amount: 900_000, date: "2026-08-20", incomeSource: "other" });
    await postJson("/api/entries", user.token, { kind: "expense", amount: 100_000, date: "2026-08-20", category: "food" });
    await postJson("/api/entries", user.token, { kind: "income", amount: 1_000_000, date: "2026-08-25", incomeSource: "salary" });

    const estimate = (await (await apiJson("/api/tax/estimate", { headers: authHeaders(user.token) })).json()) as TaxEstimateResponse;
    expect(estimate).toMatchObject({
      year: 2026,
      businessIncomeYtd: 1_800_000,
      businessExpenseYtd: 0,
      profitYtd: 1_800_000,
      rate: 0.20,
      estimatedTax: 360_000,
      monthlySetAside: 45_000,
      annualProjection: 540_000,
    });

    await postJson("/api/entries", user.token, { kind: "expense", amount: 800_000, date: "2026-08-20", category: "business" });
    const boundary = (await (await apiJson("/api/tax/estimate", { headers: authHeaders(user.token) })).json()) as TaxEstimateResponse;
    expect(boundary).toMatchObject({ profitYtd: 1_000_000, rate: 0.15 });

    const employee = await createTestUser();
    await putSettings(employee.token, "employee");
    await expectError(await apiJson("/api/tax/estimate", { headers: authHeaders(employee.token) }), 403, "FREELANCE_REQUIRED");
    await expectError(await apiJson("/api/tax/estimate?year=2027", { headers: authHeaders(user.token) }), 400, "VALIDATION_FAILED");
  });

  it("uses JST for default month/today, materialization windows, and new tax years", async () => {
    vi.setSystemTime(new Date("2026-08-31T22:00:00Z"));
    const user = await createTestUser();
    await putSettings(user.token, "freelance");
    await postJson("/api/recurring-rules", user.token, { direction: "expense", name: "月初", amount: 1_000, dayOfMonth: 1, category: "daily" });

    const home = (await (await apiJson("/api/home", { headers: authHeaders(user.token) })).json()) as HomeResponse;
    expect(home).toMatchObject({ today: "2026-09-01", month: "2026-09" });
    const months = await pool.query("SELECT year_month FROM entry ORDER BY year_month");
    expect(months.rows.map((r: { year_month: string }) => r.year_month)).toEqual(["2026-09", "2026-10", "2026-11"]);

    vi.setSystemTime(new Date("2026-12-31T16:00:00Z"));
    const tax = (await (await apiJson("/api/tax/estimate", { headers: authHeaders(user.token) })).json()) as TaxEstimateResponse;
    expect(tax).toMatchObject({ year: 2027, businessIncomeYtd: 0, businessExpenseYtd: 0, profitYtd: 0, monthlySetAside: 0, annualProjection: 0 });
  });
});
