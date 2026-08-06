import { beforeEach, describe, expect, it, vi } from "vitest";
import { apiJson, authHeaders, createTestUser, expectError, pool, postJson, putSettings, resetTestDb } from "../setup/api.js";

type EntryDto = { id: string; kind: string; amount: number; date: string; note: string | null; sourceRuleId: string | null; isManuallyEdited: boolean; cardId: string | null; incomeSource: string | null; category: string | null };
type EntriesResponse = { entries: EntryDto[] };
type RecurringRuleDto = { id: string; direction: string; name: string; amount: number; dayOfMonth: number; cardId: string | null; category: string | null; active: boolean };

describe("B-MAT recurring rule materialization", () => {
  beforeEach(async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-08-20T03:00:00Z"));
    await resetTestDb();
  });

  async function entries(token: string, month: string): Promise<EntryDto[]> {
    const res = await apiJson(`/api/entries?month=${month}`, { headers: authHeaders(token) });
    expect(res.status).toBe(200);
    return ((await res.json()) as EntriesResponse).entries;
  }

  it("creates three-month expense and income windows, including past current-month dates", async () => {
    const user = await createTestUser();
    await putSettings(user.token, "freelance");

    const expenseRule = await postJson("/api/recurring-rules", user.token, { direction: "expense", name: "Netflix", amount: 1_490, dayOfMonth: 5, category: "entertainment" });
    expect(expenseRule.status).toBe(201);
    const rule = (await expenseRule.json()) as RecurringRuleDto;
    expect((await entries(user.token, "2026-08"))[0]).toMatchObject({ kind: "expense", amount: 1_490, date: "2026-08-05", note: "Netflix", sourceRuleId: rule.id });
    expect((await entries(user.token, "2026-09"))[0]).toMatchObject({ kind: "expense", amount: 1_490, date: "2026-09-05", sourceRuleId: rule.id });
    expect((await entries(user.token, "2026-10"))[0]).toMatchObject({ kind: "expense", amount: 1_490, date: "2026-10-05", sourceRuleId: rule.id });

    const incomeRule = await postJson("/api/recurring-rules", user.token, { direction: "income", name: "給与 (本業)", amount: 280_000, dayOfMonth: 25 });
    expect(incomeRule.status).toBe(201);
    const incomeEntries = await entries(user.token, "2026-08");
    expect(incomeEntries).toContainEqual(expect.objectContaining({ kind: "income", incomeSource: "salary", amount: 280_000, date: "2026-08-25", cardId: null, category: null }));
  });

  it("materializes card-linked fixed costs as card_expense and rejects invalid rule cross-fields", async () => {
    const user = await createTestUser();
    await putSettings(user.token, "freelance");
    const cardRes = await postJson("/api/cards", user.token, { name: "楽天カード", closingDay: 31, paymentDay: 27, carryoverBalance: 0 });
    expect(cardRes.status).toBe(201);
    const card = (await cardRes.json()) as { id: string };

    const ruleRes = await postJson("/api/recurring-rules", user.token, { direction: "expense", name: "Netflix", amount: 1_490, dayOfMonth: 15, cardId: card.id, category: "entertainment" });
    expect(ruleRes.status).toBe(201);
    expect((await entries(user.token, "2026-08"))[0]).toMatchObject({ kind: "card_expense", cardId: card.id });

    await expectError(await postJson("/api/recurring-rules", user.token, { direction: "income", name: "Bad", amount: 1, dayOfMonth: 1, cardId: card.id }), 400, "VALIDATION_FAILED");
    const employee = await createTestUser();
    await putSettings(employee.token, "employee");
    await expectError(await postJson("/api/recurring-rules", employee.token, { direction: "expense", name: "経費", amount: 1, dayOfMonth: 1, category: "business" }), 403, "FREELANCE_REQUIRED");
  });

  it("keeps generated ids stable across repeated GETs and does not double-generate", async () => {
    const user = await createTestUser();
    await putSettings(user.token, "freelance");
    await postJson("/api/recurring-rules", user.token, { direction: "expense", name: "Netflix", amount: 1_490, dayOfMonth: 5, category: "entertainment" });

    const first = await entries(user.token, "2026-09");
    const second = await entries(user.token, "2026-09");
    expect(second.map((e) => e.id)).toEqual(first.map((e) => e.id));
    const rows = await pool.query("SELECT year_month, count(*)::int AS count FROM entry GROUP BY year_month ORDER BY year_month");
    expect(rows.rows).toEqual([
      { year_month: "2026-08", count: 1 },
      { year_month: "2026-09", count: 1 },
      { year_month: "2026-10", count: 1 },
    ]);
  });

  it("rematerializes only future unedited entries and preserves manually edited/past entries", async () => {
    const user = await createTestUser();
    await putSettings(user.token, "freelance");
    const rule = (await (await postJson("/api/recurring-rules", user.token, { direction: "expense", name: "Netflix", amount: 1_490, dayOfMonth: 5, category: "entertainment" })).json()) as RecurringRuleDto;

    const patch1 = await apiJson(`/api/recurring-rules/${rule.id}`, { method: "PATCH", headers: authHeaders(user.token), body: JSON.stringify({ amount: 1_990 }) });
    expect(patch1.status).toBe(200);
    expect((await entries(user.token, "2026-08"))[0]).toMatchObject({ date: "2026-08-05", amount: 1_490 });
    expect((await entries(user.token, "2026-09"))[0]).toMatchObject({ date: "2026-09-05", amount: 1_990 });

    const september = (await entries(user.token, "2026-09"))[0];
    const edited = await apiJson(`/api/entries/${september.id}`, { method: "PATCH", headers: authHeaders(user.token), body: JSON.stringify({ amount: 990 }) });
    expect(edited.status).toBe(200);
    const patch2 = await apiJson(`/api/recurring-rules/${rule.id}`, { method: "PATCH", headers: authHeaders(user.token), body: JSON.stringify({ amount: 2_490 }) });
    expect(patch2.status).toBe(200);

    expect((await entries(user.token, "2026-09"))[0]).toMatchObject({ amount: 990, isManuallyEdited: true });
    expect((await entries(user.token, "2026-10"))[0]).toMatchObject({ amount: 2_490 });
  });

  it("soft-deletes generated entries without resurrection and rule delete detaches retained generated entries", async () => {
    const user = await createTestUser();
    await putSettings(user.token, "freelance");
    const rule = (await (await postJson("/api/recurring-rules", user.token, { direction: "expense", name: "Netflix", amount: 1_490, dayOfMonth: 5, category: "entertainment" })).json()) as RecurringRuleDto;
    const september = (await entries(user.token, "2026-09"))[0];
    expect((await apiJson(`/api/entries/${september.id}`, { method: "DELETE", headers: authHeaders(user.token) })).status).toBe(204);
    expect(await entries(user.token, "2026-09")).toEqual([]);
    expect(await entries(user.token, "2026-09")).toEqual([]);
    const soft = await pool.query("SELECT deleted_at IS NOT NULL AS deleted, is_manually_edited FROM entry WHERE id = $1", [september.id]);
    expect(soft.rows[0]).toEqual({ deleted: true, is_manually_edited: true });

    const august = (await entries(user.token, "2026-08"))[0];
    expect((await apiJson(`/api/recurring-rules/${rule.id}`, { method: "DELETE", headers: authHeaders(user.token) })).status).toBe(204);
    const retained = await pool.query("SELECT source_rule_id FROM entry WHERE id = $1", [august.id]);
    expect(retained.rows[0].source_rule_id).toBeNull();
    expect((await entries(user.token, "2026-10"))).toEqual([]);
  });

  it("handles active toggles, month-end clamp, and advancing materialization windows", async () => {
    const user = await createTestUser();
    await putSettings(user.token, "freelance");
    const rule = (await (await postJson("/api/recurring-rules", user.token, { direction: "expense", name: "Netflix", amount: 1_490, dayOfMonth: 5, category: "entertainment" })).json()) as RecurringRuleDto;
    expect((await apiJson(`/api/recurring-rules/${rule.id}`, { method: "PATCH", headers: authHeaders(user.token), body: JSON.stringify({ active: false }) })).status).toBe(200);
    expect((await entries(user.token, "2026-08")).map((e) => e.date)).toEqual(["2026-08-05"]);
    expect(await entries(user.token, "2026-09")).toEqual([]);
    expect((await apiJson(`/api/recurring-rules/${rule.id}`, { method: "PATCH", headers: authHeaders(user.token), body: JSON.stringify({ active: true }) })).status).toBe(200);
    expect((await entries(user.token, "2026-09"))[0]).toMatchObject({ date: "2026-09-05" });

    vi.setSystemTime(new Date("2026-09-01T03:00:00Z"));
    expect((await entries(user.token, "2026-11"))[0]).toMatchObject({ date: "2026-11-05" });

    await resetTestDb();
    vi.setSystemTime(new Date("2026-12-20T03:00:00Z"));
    const user2 = await createTestUser();
    await putSettings(user2.token, "freelance");
    await postJson("/api/recurring-rules", user2.token, { direction: "expense", name: "月末", amount: 1_000, dayOfMonth: 31, category: "daily" });
    expect((await entries(user2.token, "2027-02"))[0]).toMatchObject({ date: "2027-02-28" });
  });
});
