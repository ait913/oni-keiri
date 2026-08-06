import { beforeEach, describe, expect, it, vi } from "vitest";
import { apiJson, authHeaders, createTestUser, expectError, postJson, putSettings, resetTestDb } from "../setup/api.js";

type CardDto = {
  id: string;
  name: string;
  utilization: number;
  monthUsage: number;
  archived: boolean;
  nextPayment: { month: string; paymentDate: string; amount: number; closed: boolean } | null;
};
type CardDetailResponse = {
  card: CardDto;
  payments: Array<{ month: string; paymentDate: string; amount: number; fromExclusive: string; toInclusive: string; closed: boolean; balanceAfter: number }>;
  recentExpenses: Array<{ id: string; date: string; amount: number; cardId: string | null }>;
  linkedRules: Array<{ id: string; cardId: string | null; active: boolean }>;
};

describe("B-CARD", () => {
  beforeEach(async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-08-20T03:00:00Z"));
    await resetTestDb();
  });

  it("returns E-1 detail payments for lump-sum cards", async () => {
    const user = await createTestUser();
    await putSettings(user.token, "freelance");
    vi.setSystemTime(new Date("2026-08-01T03:00:00Z"));
    const card = (await (await postJson("/api/cards", user.token, { name: "一括", closingDay: 15, paymentDay: 10, carryoverBalance: 0 })).json()) as CardDto;
    vi.setSystemTime(new Date("2026-08-10T03:00:00Z"));
    await postJson("/api/entries", user.token, { kind: "card_expense", amount: 3_000, date: "2026-08-10", category: "daily", cardId: card.id });
    vi.setSystemTime(new Date("2026-08-20T03:00:00Z"));
    await postJson("/api/entries", user.token, { kind: "card_expense", amount: 5_000, date: "2026-08-20", category: "daily", cardId: card.id });

    const detail = (await (await apiJson(`/api/cards/${card.id}/detail?months=3`, { headers: authHeaders(user.token) })).json()) as CardDetailResponse;
    expect(detail.payments.map((p) => ({ month: p.month, paymentDate: p.paymentDate, amount: p.amount, closed: p.closed, balanceAfter: p.balanceAfter }))).toEqual([
      { month: "2026-09", paymentDate: "2026-09-10", amount: 3_000, closed: true, balanceAfter: 0 },
      { month: "2026-10", paymentDate: "2026-10-10", amount: 5_000, closed: false, balanceAfter: 0 },
      { month: "2026-11", paymentDate: "2026-11-10", amount: 0, closed: false, balanceAfter: 0 },
    ]);
  });

  it("returns E-2 revolving schedule and utilization", async () => {
    const user = await createTestUser();
    await putSettings(user.token, "freelance");
    const card = (await (await postJson("/api/cards", user.token, { name: "リボ", closingDay: 31, paymentDay: 27, revolvingAmount: 10_000, carryoverBalance: 25_000 })).json()) as CardDto;
    await postJson("/api/entries", user.token, { kind: "card_expense", amount: 8_000, date: "2026-08-05", category: "daily", cardId: card.id });

    const detail = (await (await apiJson(`/api/cards/${card.id}/detail?months=3`, { headers: authHeaders(user.token) })).json()) as CardDetailResponse;
    expect(detail.card.utilization).toBe(33_000);
    expect(detail.payments.map((p) => ({ month: p.month, amount: p.amount, balanceAfter: p.balanceAfter }))).toEqual([
      { month: "2026-09", amount: 10_000, balanceAfter: 23_000 },
      { month: "2026-10", amount: 10_000, balanceAfter: 13_000 },
      { month: "2026-11", amount: 10_000, balanceAfter: 3_000 },
    ]);
  });

  it("clamps month-end payment dates and ignores backdated expenses before the first eligible cycle", async () => {
    const user = await createTestUser();
    await putSettings(user.token, "freelance");
    vi.setSystemTime(new Date("2026-12-20T03:00:00Z"));
    const card = (await (await postJson("/api/cards", user.token, { name: "月末", closingDay: 31, paymentDay: 31, carryoverBalance: 0 })).json()) as CardDto;
    const feb = (await (await apiJson(`/api/cards/${card.id}/detail?months=3`, { headers: authHeaders(user.token) })).json()) as CardDetailResponse;
    expect(feb.payments.find((p) => p.month === "2027-02")).toMatchObject({
      paymentDate: "2027-02-28",
      fromExclusive: "2026-12-31",
      toInclusive: "2027-01-31",
    });

    vi.setSystemTime(new Date("2026-08-20T03:00:00Z"));
    const lateCreated = (await (await postJson("/api/cards", user.token, { name: "後作成", closingDay: 15, paymentDay: 10, carryoverBalance: 0 })).json()) as CardDto;
    await postJson("/api/entries", user.token, { kind: "card_expense", amount: 3_000, date: "2026-08-10", category: "daily", cardId: lateCreated.id });
    const detail = (await (await apiJson(`/api/cards/${lateCreated.id}/detail?months=1`, { headers: authHeaders(user.token) })).json()) as CardDetailResponse;
    expect(detail.payments[0]).toMatchObject({ month: "2026-10", amount: 0 });
  });

  it("returns CardDto nextPayment/monthUsage, recentExpenses, and linked active rules", async () => {
    const user = await createTestUser();
    await putSettings(user.token, "freelance");
    const card = (await (await postJson("/api/cards", user.token, { name: "楽天カード", closingDay: 31, paymentDay: 27, carryoverBalance: 0 })).json()) as CardDto;
    await postJson("/api/recurring-rules", user.token, { direction: "expense", name: "Netflix", amount: 1_490, dayOfMonth: 15, cardId: card.id, category: "entertainment" });
    for (let day = 1; day <= 11; day += 1) {
      await postJson("/api/entries", user.token, { kind: "card_expense", amount: day * 100, date: `2026-08-${String(day).padStart(2, "0")}`, category: "daily", cardId: card.id });
    }

    const cards = (await (await apiJson("/api/cards", { headers: authHeaders(user.token) })).json()) as { cards: CardDto[] };
    expect(cards.cards[0]).toMatchObject({ id: card.id, monthUsage: 8_090 });
    expect(cards.cards[0].nextPayment).toMatchObject({ month: "2026-09", paymentDate: "2026-09-27" });

    const detail = (await (await apiJson(`/api/cards/${card.id}/detail?months=3`, { headers: authHeaders(user.token) })).json()) as CardDetailResponse;
    expect(detail.recentExpenses).toHaveLength(10);
    expect(detail.recentExpenses.map((e) => e.date)).toEqual(["2026-08-15", "2026-08-11", "2026-08-10", "2026-08-09", "2026-08-08", "2026-08-07", "2026-08-06", "2026-08-05", "2026-08-04", "2026-08-03"]);
    expect(detail.linkedRules).toHaveLength(1);
    expect(detail.linkedRules[0]?.cardId).toBe(card.id);
  });

  it("rejects months outside 1..3, protects referenced cards from delete, and blocks new archived-card references", async () => {
    const user = await createTestUser();
    await putSettings(user.token, "freelance");
    const card = (await (await postJson("/api/cards", user.token, { name: "楽天カード", closingDay: 31, paymentDay: 27, carryoverBalance: 0 })).json()) as CardDto;
    await expectError(await apiJson(`/api/cards/${card.id}/detail?months=4`, { headers: authHeaders(user.token) }), 400, "VALIDATION_FAILED");

    await postJson("/api/entries", user.token, { kind: "card_expense", amount: 1_000, date: "2026-08-20", category: "daily", cardId: card.id });
    await expectError(await apiJson(`/api/cards/${card.id}`, { method: "DELETE", headers: authHeaders(user.token) }), 409, "CARD_IN_USE");

    const archived = await apiJson(`/api/cards/${card.id}`, { method: "PATCH", headers: authHeaders(user.token), body: JSON.stringify({ archived: true }) });
    expect(archived.status).toBe(200);
    await expectError(await postJson("/api/entries", user.token, { kind: "card_expense", amount: 1_000, date: "2026-08-20", category: "daily", cardId: card.id }), 400, "VALIDATION_FAILED");
    await expectError(await postJson("/api/recurring-rules", user.token, { direction: "expense", name: "Archived", amount: 1_000, dayOfMonth: 20, category: "daily", cardId: card.id }), 400, "VALIDATION_FAILED");
  });
});
