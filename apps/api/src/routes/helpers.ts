import { and, eq, isNull } from "drizzle-orm";
import type { Context } from "hono";
import type { z } from "zod";
import { card, entry, recurringRule, userSettings } from "../db/schema.js";
import { getDb, type Db } from "../db/index.js";
import { AppError } from "../lib/appError.js";
import { addMonths, currentMonthJst, todayJst } from "../lib/tz.js";
import { cardPaymentSchedule, cardUtilization } from "../lib/cardSchedule.js";
import type { AppVariables } from "../types.js";
import type { CardDto, EntryDto, RecurringRuleDto, SettingsDto } from "./schemas.js";

export type AppContext = Context<{ Variables: AppVariables }>;

export function parseJson<T extends z.ZodType>(schema: T, c: AppContext): Promise<z.infer<T>> {
  return c.req.json()
    .catch(() => {
      throw new AppError(400, "VALIDATION_FAILED", "Validation failed");
    })
    .then((body) => parseSchema(schema, body));
}

export function parseQuery<T extends z.ZodType>(schema: T, value: unknown): z.infer<T> {
  return parseSchema(schema, value);
}

function parseSchema<T extends z.ZodType>(schema: T, value: unknown): z.infer<T> {
  const result = schema.safeParse(value);
  if (!result.success) throw new AppError(400, "VALIDATION_FAILED", "Validation failed");
  return result.data;
}

export function settingsDto(row: typeof userSettings.$inferSelect): SettingsDto {
  return { employmentType: row.employmentType, savingsGoal: row.savingsGoal };
}

export function entryDto(row: typeof entry.$inferSelect): EntryDto {
  return {
    id: row.id,
    kind: row.kind,
    amount: row.amount,
    date: row.date,
    yearMonth: row.yearMonth,
    category: row.category,
    cardId: row.cardId,
    incomeSource: row.incomeSource,
    note: row.note,
    sourceRuleId: row.sourceRuleId,
    isManuallyEdited: row.isManuallyEdited,
  };
}

export function recurringRuleDto(row: typeof recurringRule.$inferSelect): RecurringRuleDto {
  return {
    id: row.id,
    direction: row.direction,
    name: row.name,
    amount: row.amount,
    dayOfMonth: row.dayOfMonth,
    cardId: row.cardId,
    category: row.category,
    startMonth: row.startMonth,
    active: row.active,
  };
}

export async function requireSettings(userId: string): Promise<typeof userSettings.$inferSelect> {
  const row = await getDb().query.userSettings.findFirst({ where: eq(userSettings.userId, userId) });
  if (!row) throw new AppError(404, "NOT_FOUND", "Not found");
  return row;
}

export async function getSettings(userId: string): Promise<typeof userSettings.$inferSelect | null> {
  return await getDb().query.userSettings.findFirst({ where: eq(userSettings.userId, userId) }) ?? null;
}

export async function assertFreelance(userId: string): Promise<void> {
  const settings = await getSettings(userId);
  if (settings?.employmentType !== "freelance") {
    throw new AppError(403, "FREELANCE_REQUIRED", "Freelance employment type required");
  }
}

export async function requireOwnedCard(id: string, userId: string, options: { allowArchived?: boolean } = {}): Promise<typeof card.$inferSelect> {
  const row = await getDb().query.card.findFirst({ where: and(eq(card.id, id), eq(card.userId, userId)) });
  if (!row) throw new AppError(404, "NOT_FOUND", "Not found");
  if (row.archived && !options.allowArchived) throw new AppError(400, "VALIDATION_FAILED", "Validation failed");
  return row;
}

export async function requireOwnedEntry(id: string, userId: string): Promise<typeof entry.$inferSelect> {
  const row = await getDb().query.entry.findFirst({ where: and(eq(entry.id, id), eq(entry.userId, userId), isNull(entry.deletedAt)) });
  if (!row) throw new AppError(404, "NOT_FOUND", "Not found");
  return row;
}

export async function requireOwnedRule(id: string, userId: string): Promise<typeof recurringRule.$inferSelect> {
  const row = await getDb().query.recurringRule.findFirst({ where: and(eq(recurringRule.id, id), eq(recurringRule.userId, userId)) });
  if (!row) throw new AppError(404, "NOT_FOUND", "Not found");
  return row;
}

export async function listCards(userId: string): Promise<(typeof card.$inferSelect)[]> {
  return await getDb().select().from(card).where(eq(card.userId, userId));
}

export async function listLiveEntries(userId: string): Promise<(typeof entry.$inferSelect)[]> {
  return await getDb().select().from(entry).where(and(eq(entry.userId, userId), isNull(entry.deletedAt)));
}

export async function cardDto(row: typeof card.$inferSelect, entries: (typeof entry.$inferSelect)[] = [], now: Date = new Date()): Promise<CardDto> {
  const today = todayJst(now);
  const month = currentMonthJst(now);
  const expenses = entries
    .filter((item) => item.cardId === row.id && item.kind === "card_expense")
    .map((item) => ({ date: item.date, amount: item.amount }));
  const payments = cardPaymentSchedule(row, expenses, addMonths(month, 3));
  const next = payments.find((payment) => payment.paymentDate >= today) ?? null;
  const monthUsage = expenses.filter((item) => item.date.slice(0, 7) === month).reduce((sum, item) => sum + item.amount, 0);
  return {
    id: row.id,
    name: row.name,
    closingDay: row.closingDay,
    paymentDay: row.paymentDay,
    revolvingAmount: row.revolvingAmount,
    creditLimit: row.creditLimit,
    carryoverBalance: row.carryoverBalance,
    archived: row.archived,
    utilization: cardUtilization(row, expenses, today),
    monthUsage,
    nextPayment: next ? { month: next.month, paymentDate: next.paymentDate, amount: next.amount, closed: next.closed } : null,
  };
}

export async function allCardPaymentsForMonth(db: Db, userId: string, month: string): Promise<{ paymentDate: string; amount: number }[]> {
  const cards = await db.select().from(card).where(eq(card.userId, userId));
  const entries = await db.select().from(entry).where(and(eq(entry.userId, userId), isNull(entry.deletedAt)));
  return cards.flatMap((row) => {
    const expenses = entries
      .filter((item) => item.cardId === row.id && item.kind === "card_expense")
      .map((item) => ({ date: item.date, amount: item.amount }));
    return cardPaymentSchedule(row, expenses, month)
      .filter((payment) => payment.month === month)
      .map((payment) => ({ paymentDate: payment.paymentDate, amount: payment.amount }));
  });
}
