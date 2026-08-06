import { randomUUID } from "node:crypto";
import { Pool } from "pg";
import { expect } from "vitest";
import { app } from "../../src/app.js";

export const pool = new Pool({ connectionString: process.env.DATABASE_URL });

export type TestUser = { userId: string; token: string };

export async function resetTestDb(): Promise<void> {
  await pool.query(
    'TRUNCATE TABLE entry, recurring_rule, card, user_settings, session, account, verification, "user" RESTART IDENTITY CASCADE',
  );
}

export async function createTestUser(overrides: { token?: string; expiresAt?: Date } = {}): Promise<TestUser> {
  const userId = randomUUID();
  const token = overrides.token ?? `test-token-${randomUUID()}`;
  const expiresAt = overrides.expiresAt ?? new Date("2035-01-01T00:00:00.000Z");

  await pool.query(
    'INSERT INTO "user" (id, name, email, email_verified, image, created_at, updated_at) VALUES ($1, $2, $3, $4, $5, now(), now())',
    [userId, "Test User", `${userId}@example.test`, true, null],
  );
  await pool.query(
    'INSERT INTO session (id, token, user_id, expires_at, created_at, updated_at, ip_address, user_agent) VALUES ($1, $2, $3, $4, now(), now(), $5, $6)',
    [randomUUID(), token, userId, expiresAt, "127.0.0.1", "vitest"],
  );

  return { userId, token };
}

export function authHeaders(token: string): HeadersInit {
  return { Authorization: `Bearer ${token}` };
}

export async function apiJson(path: string, init: RequestInit = {}): Promise<Response> {
  return app.request(path, {
    ...init,
    headers: {
      "content-type": "application/json",
      ...(init.headers ?? {}),
    },
  });
}

export async function expectError(res: Response, status: number, code: string): Promise<void> {
  expect(res.status).toBe(status);
  await expect(res.json()).resolves.toMatchObject({ error: { code } });
}

export async function putSettings(token: string, employmentType = "freelance", savingsGoal: number | null = null): Promise<void> {
  const res = await apiJson("/api/settings", {
    method: "PUT",
    headers: authHeaders(token),
    body: JSON.stringify({ employmentType, savingsGoal }),
  });
  expect(res.status).toBe(200);
}

export async function postJson<T extends object>(path: string, token: string, body: T): Promise<Response> {
  return apiJson(path, {
    method: "POST",
    headers: authHeaders(token),
    body: JSON.stringify(body),
  });
}

export async function patchJson<T extends object>(path: string, token: string, body: T): Promise<Response> {
  return apiJson(path, {
    method: "PATCH",
    headers: authHeaders(token),
    body: JSON.stringify(body),
  });
}
