import { Hono } from "hono";
import { and, asc, eq, isNull } from "drizzle-orm";
import { getDb } from "../db/index.js";
import { card, entry } from "../db/schema.js";
import { AppError } from "../lib/appError.js";
import { buildBreakdown, buildQuality } from "../lib/homeSummary.js";
import { rematerializeRule } from "../lib/materialize.js";
import { yearMonthOf } from "../lib/money.js";
import type { AppVariables } from "../types.js";
import {
  assertFreelance,
  entryDto,
  getSettings,
  parseJson,
  parseQuery,
  requireOwnedCard,
  requireOwnedEntry,
} from "./helpers.js";
import { CreateEntryBody, CreateSalaryBody, MonthString, UpdateEntryBody, type EntriesResponse, type EntryDto } from "./schemas.js";

export const entriesRoutes = new Hono<{ Variables: AppVariables }>();

function validationFailed(): never {
  throw new AppError(400, "VALIDATION_FAILED", "Validation failed");
}

async function validateEntryFields(userId: string, body: {
  kind: "expense" | "card_expense" | "income";
  cardId?: string | null;
  incomeSource?: "salary" | "other" | null;
  category?: string | null;
}): Promise<void> {
  if ((body.kind === "card_expense") !== Boolean(body.cardId)) validationFailed();
  if (body.kind !== "card_expense" && body.cardId) validationFailed();
  if ((body.kind === "income") !== Boolean(body.incomeSource)) validationFailed();
  if (body.kind !== "income" && body.incomeSource) validationFailed();
  if (body.kind === "income" && body.category) validationFailed();
  if (body.category === "business") await assertFreelance(userId);
  if (body.cardId) await requireOwnedCard(body.cardId, userId);
}

entriesRoutes.get("/", async (c) => {
  const userId = c.get("user").id;
  const { month } = parseQuery(MonthString.transform((month) => ({ month })), c.req.query("month"));
  const rows = await getDb()
    .select()
    .from(entry)
    .where(and(eq(entry.userId, userId), eq(entry.yearMonth, month), isNull(entry.deletedAt)))
    .orderBy(asc(entry.date), asc(entry.createdAt));
  const entries = rows.map(entryDto);
  return c.json({
    entries,
    breakdown: buildBreakdown(entries),
    quality: buildQuality(entries),
  } satisfies EntriesResponse);
});

entriesRoutes.post("/", async (c) => {
  const userId = c.get("user").id;
  const body = await parseJson(CreateEntryBody, c);
  await validateEntryFields(userId, body);
  const rows = await getDb().insert(entry).values({
    userId,
    kind: body.kind,
    amount: body.amount,
    date: body.date,
    yearMonth: yearMonthOf(body.date),
    category: body.category ?? null,
    cardId: body.cardId ?? null,
    incomeSource: body.incomeSource ?? null,
    note: body.note ?? null,
  }).returning();
  return c.json(entryDto(rows[0]) satisfies EntryDto, 201);
});

entriesRoutes.post("/salary", async (c) => {
  const userId = c.get("user").id;
  const body = await parseJson(CreateSalaryBody, c);
  const settings = await getSettings(userId);
  if (body.expenses.length > 0 && settings?.employmentType !== "freelance") {
    throw new AppError(403, "FREELANCE_REQUIRED", "Freelance employment type required");
  }
  const yearMonth = yearMonthOf(body.date);
  const result = await getDb().transaction(async (tx) => {
    const [income] = await tx.insert(entry).values({
      userId,
      kind: "income",
      amount: body.amount,
      date: body.date,
      yearMonth,
      category: null,
      cardId: null,
      incomeSource: "salary",
      note: body.note ?? null,
    }).returning();
    const expenses = body.expenses.length === 0 ? [] : await tx.insert(entry).values(body.expenses.map((expenseBody) => ({
      userId,
      kind: "expense" as const,
      amount: expenseBody.amount,
      date: body.date,
      yearMonth,
      category: "business" as const,
      cardId: null,
      incomeSource: null,
      note: expenseBody.note ?? null,
    }))).returning();
    return { income, expenses };
  });
  return c.json({ income: entryDto(result.income), expenses: result.expenses.map(entryDto) }, 201);
});

entriesRoutes.patch("/:id", async (c) => {
  const userId = c.get("user").id;
  const current = await requireOwnedEntry(c.req.param("id"), userId);
  const body = await parseJson(UpdateEntryBody, c);

  if (current.kind === "income" && body.category) validationFailed();
  if (current.kind !== "income" && body.incomeSource) validationFailed();
  if (body.category === "business") await assertFreelance(userId);
  if (current.sourceRuleId && body.date && yearMonthOf(body.date) !== current.yearMonth) validationFailed();

  const nextDate = body.date ?? current.date;
  const rows = await getDb().update(entry).set({
    amount: body.amount ?? current.amount,
    date: nextDate,
    yearMonth: yearMonthOf(nextDate),
    category: body.category === undefined ? current.category : body.category ?? null,
    incomeSource: body.incomeSource === undefined ? current.incomeSource : body.incomeSource,
    note: body.note === undefined ? current.note : body.note ?? null,
    isManuallyEdited: current.sourceRuleId ? true : current.isManuallyEdited,
    updatedAt: new Date(),
  }).where(and(eq(entry.id, current.id), eq(entry.userId, userId))).returning();
  return c.json(entryDto(rows[0]) satisfies EntryDto);
});

entriesRoutes.delete("/:id", async (c) => {
  const userId = c.get("user").id;
  const current = await requireOwnedEntry(c.req.param("id"), userId);
  if (current.sourceRuleId) {
    await getDb().update(entry).set({ deletedAt: new Date(), isManuallyEdited: true, updatedAt: new Date() }).where(eq(entry.id, current.id));
  } else {
    await getDb().delete(entry).where(eq(entry.id, current.id));
  }
  return c.body(null, 204);
});
