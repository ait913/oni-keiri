import { randomUUID } from "node:crypto";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { apiJson, authHeaders, createTestUser, expectError, pool, putSettings, resetTestDb } from "../setup/api.js";

type MeResponse = { onboarded: boolean; settings: { employmentType: string; savingsGoal: number | null } | null };

describe("B-AUTH and B-SET", () => {
  beforeEach(async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-08-20T03:00:00Z"));
    await resetTestDb();
  });

  it("returns 401 UNAUTHORIZED envelopes on protected routes without auth", async () => {
    const protectedRequests: Array<[string, RequestInit]> = [
      ["/api/me", {}],
      ["/api/settings", {}],
      ["/api/home", {}],
      ["/api/entries?month=2026-08", {}],
      ["/api/cards", {}],
      [`/api/cards/${randomUUID()}/detail`, {}],
      ["/api/recurring-rules", {}],
      ["/api/calendar?month=2026-08", {}],
      ["/api/tax/estimate", {}],
      ["/api/entries", { method: "POST", body: "{}" }],
      ["/api/entries/salary", { method: "POST", body: "{}" }],
      [`/api/entries/${randomUUID()}`, { method: "PATCH", body: "{}" }],
      [`/api/entries/${randomUUID()}`, { method: "DELETE" }],
      ["/api/cards", { method: "POST", body: "{}" }],
      [`/api/cards/${randomUUID()}`, { method: "PATCH", body: "{}" }],
      [`/api/cards/${randomUUID()}`, { method: "DELETE" }],
      ["/api/recurring-rules", { method: "POST", body: "{}" }],
      [`/api/recurring-rules/${randomUUID()}`, { method: "PATCH", body: "{}" }],
      [`/api/recurring-rules/${randomUUID()}`, { method: "DELETE" }],
      ["/api/settings", { method: "PUT", body: "{}" }],
      ["/api/me", { method: "DELETE" }],
    ];

    for (const [path, init] of protectedRequests) {
      await expectError(await apiJson(path, init), 401, "UNAUTHORIZED");
    }
  });

  it("accepts a raw session token from DB fallback, rejects missing/expired tokens, and deletes expired sessions", async () => {
    await expectError(await apiJson("/api/home", { headers: authHeaders("missing-token") }), 401, "UNAUTHORIZED");

    const valid = await createTestUser();
    await putSettings(valid.token, "employee");
    expect((await apiJson("/api/me", { headers: authHeaders(valid.token) })).status).toBe(200);

    const expired = await createTestUser({ expiresAt: new Date("2026-08-19T00:00:00Z") });
    await expectError(await apiJson("/api/home", { headers: authHeaders(expired.token) }), 401, "UNAUTHORIZED");
    const expiredRows = await pool.query("SELECT count(*)::int AS count FROM session WHERE token = $1", [expired.token]);
    expect(expiredRows.rows[0].count).toBe(0);
  });

  it("reports onboarding state, upserts settings, clears savingsGoal, and gates tax after employment changes", async () => {
    const user = await createTestUser();

    const initial = await apiJson("/api/me", { headers: authHeaders(user.token) });
    expect(initial.status).toBe(200);
    expect((await initial.json()) as MeResponse).toMatchObject({ onboarded: false, settings: null });
    await expectError(await apiJson("/api/settings", { headers: authHeaders(user.token) }), 404, "NOT_FOUND");

    const created = await apiJson("/api/settings", {
      method: "PUT",
      headers: authHeaders(user.token),
      body: JSON.stringify({ employmentType: "freelance" }),
    });
    expect(created.status).toBe(200);
    expect(await created.json()).toEqual({ employmentType: "freelance", savingsGoal: null });

    const onboarded = await apiJson("/api/me", { headers: authHeaders(user.token) });
    expect(((await onboarded.json()) as MeResponse).onboarded).toBe(true);

    const updated = await apiJson("/api/settings", {
      method: "PUT",
      headers: authHeaders(user.token),
      body: JSON.stringify({ employmentType: "freelance", savingsGoal: 100_000 }),
    });
    expect(await updated.json()).toEqual({ employmentType: "freelance", savingsGoal: 100_000 });

    const cleared = await apiJson("/api/settings", {
      method: "PUT",
      headers: authHeaders(user.token),
      body: JSON.stringify({ employmentType: "employee", savingsGoal: null }),
    });
    expect(await cleared.json()).toEqual({ employmentType: "employee", savingsGoal: null });
    await expectError(await apiJson("/api/tax/estimate", { headers: authHeaders(user.token) }), 403, "FREELANCE_REQUIRED");
  });

  it("DELETE /api/me cascades user-owned data and invalidates the same token", async () => {
    const user = await createTestUser();
    await putSettings(user.token, "freelance");
    const entry = await apiJson("/api/entries", {
      method: "POST",
      headers: authHeaders(user.token),
      body: JSON.stringify({ kind: "expense", amount: 1_200, date: "2026-08-20", category: "food" }),
    });
    expect(entry.status).toBe(201);

    const deleted = await apiJson("/api/me", { method: "DELETE", headers: authHeaders(user.token) });
    expect(deleted.status).toBe(204);
    await expectError(await apiJson("/api/home", { headers: authHeaders(user.token) }), 401, "UNAUTHORIZED");

    for (const table of ["entry", "recurring_rule", "card", "user_settings", "session"] as const) {
      const rows = await pool.query(`SELECT count(*)::int AS count FROM ${table}`);
      expect(rows.rows[0].count).toBe(0);
    }
  });
});
