import { beforeEach, describe, expect, it, vi } from "vitest";
import { apiJson, authHeaders, createTestUser, expectError, pool, postJson, putSettings, resetTestDb } from "../setup/api.js";

type EntryDto = {
  id: string;
  kind: "expense" | "card_expense" | "income";
  amount: number;
  date: string;
  yearMonth: string;
  category: string | null;
  cardId: string | null;
  incomeSource: "salary" | "other" | null;
  note: string | null;
  sourceRuleId: string | null;
  isManuallyEdited: boolean;
};
type EntriesResponse = { entries: EntryDto[]; breakdown: Array<{ category: string; amount: number }>; quality: { fixed: number; variable: number; savingTip: number } };

describe("B-ENT, B-SAL, and B-QUAL", () => {
  beforeEach(async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-08-20T03:00:00Z"));
    await resetTestDb();
  });

  it("creates manual entries, derives yearMonth, validates finite error codes, and deletes manual rows physically", async () => {
    const user = await createTestUser();
    await putSettings(user.token, "freelance");

    const created = await postJson("/api/entries", user.token, { kind: "expense", amount: 1_200, date: "2026-08-20", category: "food" });
    expect(created.status).toBe(201);
    const entry = (await created.json()) as EntryDto;
    expect(entry).toMatchObject({ kind: "expense", amount: 1_200, date: "2026-08-20", yearMonth: "2026-08", sourceRuleId: null, isManuallyEdited: false });

    for (const body of [
      { kind: "expense", amount: 0, date: "2026-08-20", category: "food" },
      { kind: "expense", amount: -1, date: "2026-08-20", category: "food" },
      { kind: "expense", amount: 100_000_000, date: "2026-08-20", category: "food" },
      { kind: "expense", amount: 1, date: "2026-02-30", category: "food" },
      { kind: "expense", amount: 1, date: "2019-12-31", category: "food" },
      { kind: "card_expense", amount: 1, date: "2026-08-20", category: "food" },
      { kind: "expense", amount: 1, date: "2026-08-20", cardId: "00000000-0000-0000-0000-000000000000", category: "food" },
      { kind: "income", amount: 1, date: "2026-08-20" },
      { kind: "expense", amount: 1, date: "2026-08-20", incomeSource: "other", category: "food" },
      { kind: "income", amount: 1, date: "2026-08-20", incomeSource: "other", category: "food" },
    ]) {
      await expectError(await postJson("/api/entries", user.token, body), 400, "VALIDATION_FAILED");
    }

    const employee = await createTestUser();
    await putSettings(employee.token, "employee");
    await expectError(await postJson("/api/entries", employee.token, { kind: "expense", amount: 1_000, date: "2026-08-20", category: "business" }), 403, "FREELANCE_REQUIRED");

    const removed = await apiJson(`/api/entries/${entry.id}`, { method: "DELETE", headers: authHeaders(user.token) });
    expect(removed.status).toBe(204);
    const rows = await pool.query("SELECT count(*)::int AS count FROM entry WHERE id = $1", [entry.id]);
    expect(rows.rows[0].count).toBe(0);
  });

  it("returns only requested month entries sorted by date and hides other users", async () => {
    const user = await createTestUser();
    const other = await createTestUser();
    await putSettings(user.token, "freelance");
    await putSettings(other.token, "freelance");

    const later = await postJson("/api/entries", user.token, { kind: "expense", amount: 2_000, date: "2026-08-20", category: "daily" });
    const earlier = await postJson("/api/entries", user.token, { kind: "expense", amount: 1_000, date: "2026-08-01", category: "food" });
    await postJson("/api/entries", user.token, { kind: "expense", amount: 9_000, date: "2026-07-31", category: "food" });
    expect(later.status).toBe(201);
    expect(earlier.status).toBe(201);
    const laterEntry = (await later.json()) as EntryDto;

    const listed = await apiJson("/api/entries?month=2026-08", { headers: authHeaders(user.token) });
    const body = (await listed.json()) as EntriesResponse;
    expect(body.entries.map((e) => e.date)).toEqual(["2026-08-01", "2026-08-20"]);

    await expectError(await apiJson(`/api/entries/${laterEntry.id}`, {
      method: "PATCH",
      headers: authHeaders(other.token),
      body: JSON.stringify({ amount: 3_000 }),
    }), 404, "NOT_FOUND");
    await expectError(await apiJson(`/api/entries/${laterEntry.id}`, { method: "DELETE", headers: authHeaders(other.token) }), 404, "NOT_FOUND");
  });

  it("creates salary plus business expenses transactionally and enforces freelance-only expense bundling", async () => {
    const freelancer = await createTestUser();
    await putSettings(freelancer.token, "freelance");

    const salary = await postJson("/api/entries/salary", freelancer.token, {
      amount: 300_000,
      date: "2026-08-20",
      expenses: [{ amount: 20_000 }, { amount: 5_000 }],
    });
    expect(salary.status).toBe(201);
    const rows = await pool.query("SELECT kind, amount, category, income_source FROM entry ORDER BY amount DESC");
    expect(rows.rows).toEqual([
      { kind: "income", amount: 300_000, category: null, income_source: "salary" },
      { kind: "expense", amount: 20_000, category: "business", income_source: null },
      { kind: "expense", amount: 5_000, category: "business", income_source: null },
    ]);

    const invalid = await postJson("/api/entries/salary", freelancer.token, {
      amount: 10_000,
      date: "2026-08-21",
      expenses: [{ amount: 1_000 }, { amount: 0 }],
    });
    await expectError(invalid, 400, "VALIDATION_FAILED");
    const afterInvalid = await pool.query("SELECT count(*)::int AS count FROM entry WHERE date = '2026-08-21'");
    expect(afterInvalid.rows[0].count).toBe(0);

    const employee = await createTestUser();
    await putSettings(employee.token, "employee");
    expect((await postJson("/api/entries/salary", employee.token, { amount: 100_000, date: "2026-08-20", expenses: [] })).status).toBe(201);
    await expectError(await postJson("/api/entries/salary", employee.token, { amount: 100_000, date: "2026-08-20", expenses: [{ amount: 1 }] }), 403, "FREELANCE_REQUIRED");
  });

  it("returns breakdown and quality from August spending only", async () => {
    const user = await createTestUser();
    await putSettings(user.token, "freelance");
    await postJson("/api/recurring-rules", user.token, { direction: "expense", name: "家賃", amount: 82_000, dayOfMonth: 1, category: "housing" });
    await postJson("/api/entries", user.token, { kind: "expense", amount: 20_000, date: "2026-08-02", category: "food" });
    await postJson("/api/entries", user.token, { kind: "expense", amount: 33_200, date: "2026-08-03" });
    await postJson("/api/entries", user.token, { kind: "income", amount: 300_000, date: "2026-08-25", incomeSource: "salary" });

    const res = await apiJson("/api/entries?month=2026-08", { headers: authHeaders(user.token) });
    const body = (await res.json()) as EntriesResponse;
    expect(body.breakdown).toEqual([
      { category: "housing", amount: 82_000 },
      { category: "other", amount: 33_200 },
      { category: "food", amount: 20_000 },
    ]);
    expect(body.quality).toEqual({ fixed: 82_000, variable: 53_200, savingTip: 5_320 });
  });
});
