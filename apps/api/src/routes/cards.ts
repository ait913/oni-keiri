import { Hono } from "hono";
import { and, eq } from "drizzle-orm";
import { getDb } from "../db/index.js";
import { card, entry, recurringRule } from "../db/schema.js";
import { AppError } from "../lib/appError.js";
import { cardPaymentSchedule, cycleRange } from "../lib/cardSchedule.js";
import { addMonths, currentMonthJst, todayJst } from "../lib/tz.js";
import { clampDay } from "../lib/money.js";
import type { AppVariables } from "../types.js";
import {
  cardDto,
  entryDto,
  listLiveEntries,
  parseJson,
  parseQuery,
  recurringRuleDto,
  requireOwnedCard,
} from "./helpers.js";
import { CreateCardBody, UpdateCardBody, type CardDetailResponse } from "./schemas.js";
import { z } from "zod";

export const cardsRoutes = new Hono<{ Variables: AppVariables }>();

function firstPaymentMonth(row: typeof card.$inferSelect): string {
  let closingMonth = row.createdDate.slice(0, 7);
  while (clampDay(closingMonth, row.closingDay) < row.createdDate) {
    closingMonth = addMonths(closingMonth, 1);
  }
  return addMonths(closingMonth, 1);
}

cardsRoutes.get("/", async (c) => {
  const userId = c.get("user").id;
  const [cards, entries] = await Promise.all([
    getDb().select().from(card).where(eq(card.userId, userId)),
    listLiveEntries(userId),
  ]);
  return c.json({ cards: await Promise.all(cards.map((row) => cardDto(row, entries))) });
});

cardsRoutes.post("/", async (c) => {
  const userId = c.get("user").id;
  const body = await parseJson(CreateCardBody, c);
  const rows = await getDb().insert(card).values({
    userId,
    name: body.name,
    closingDay: body.closingDay,
    paymentDay: body.paymentDay,
    revolvingAmount: body.revolvingAmount ?? null,
    creditLimit: body.creditLimit ?? null,
    carryoverBalance: body.carryoverBalance,
    createdDate: todayJst(),
  }).returning();
  return c.json(await cardDto(rows[0], []), 201);
});

cardsRoutes.patch("/:id", async (c) => {
  const userId = c.get("user").id;
  const current = await requireOwnedCard(c.req.param("id"), userId, { allowArchived: true });
  const body = await parseJson(UpdateCardBody, c);
  const rows = await getDb().update(card).set({
    name: body.name ?? current.name,
    closingDay: body.closingDay ?? current.closingDay,
    paymentDay: body.paymentDay ?? current.paymentDay,
    revolvingAmount: body.revolvingAmount === undefined ? current.revolvingAmount : body.revolvingAmount ?? null,
    creditLimit: body.creditLimit === undefined ? current.creditLimit : body.creditLimit ?? null,
    carryoverBalance: body.carryoverBalance ?? current.carryoverBalance,
    archived: body.archived ?? current.archived,
    updatedAt: new Date(),
  }).where(and(eq(card.id, current.id), eq(card.userId, userId))).returning();
  return c.json(await cardDto(rows[0], await listLiveEntries(userId)));
});

cardsRoutes.delete("/:id", async (c) => {
  const userId = c.get("user").id;
  const current = await requireOwnedCard(c.req.param("id"), userId, { allowArchived: true });
  const [usedEntry] = await getDb().select({ id: entry.id }).from(entry).where(and(eq(entry.userId, userId), eq(entry.cardId, current.id))).limit(1);
  const [usedRule] = await getDb().select({ id: recurringRule.id }).from(recurringRule).where(and(eq(recurringRule.userId, userId), eq(recurringRule.cardId, current.id))).limit(1);
  if (usedEntry || usedRule) throw new AppError(409, "CARD_IN_USE", "Card is in use");
  await getDb().delete(card).where(and(eq(card.id, current.id), eq(card.userId, userId)));
  return c.body(null, 204);
});

cardsRoutes.get("/:id/detail", async (c) => {
  const userId = c.get("user").id;
  const current = await requireOwnedCard(c.req.param("id"), userId, { allowArchived: true });
  const { months } = parseQuery(z.object({ months: z.coerce.number().int().min(1).max(3).default(3) }), { months: c.req.query("months") });
  const entries = await listLiveEntries(userId);
  const expenses = entries
    .filter((item) => item.cardId === current.id && item.kind === "card_expense")
    .map((item) => ({ date: item.date, amount: item.amount }));
  const currentMonth = currentMonthJst();
  const firstMonth = firstPaymentMonth(current);
  const startMonth = currentMonth > firstMonth ? currentMonth : firstMonth;
  const targetMonths = Array.from({ length: months }, (_, i) => addMonths(startMonth, i));
  const allPayments = cardPaymentSchedule(current, expenses, targetMonths[targetMonths.length - 1]);
  const today = todayJst();
  const recentExpenses = entries
    .filter((item) => item.cardId === current.id && item.kind === "card_expense" && item.date <= today)
    .sort((a, b) => b.date.localeCompare(a.date))
    .slice(0, 10)
    .map(entryDto);
  const linkedRules = await getDb()
    .select()
    .from(recurringRule)
    .where(and(eq(recurringRule.userId, userId), eq(recurringRule.cardId, current.id), eq(recurringRule.direction, "expense"), eq(recurringRule.active, true)));
  return c.json({
    card: await cardDto(current, entries),
    payments: targetMonths.map((month) => {
      const existing = allPayments.find((payment) => payment.month === month);
      if (existing) return existing;
      const range = cycleRange(current, month);
      return {
        month,
        paymentDate: clampDay(month, current.paymentDay),
        amount: 0,
        fromExclusive: range.fromExclusive,
        toInclusive: range.toInclusive,
        closed: today > range.toInclusive,
        balanceAfter: current.carryoverBalance,
      };
    }),
    recentExpenses,
    linkedRules: linkedRules.map(recurringRuleDto),
  } satisfies CardDetailResponse);
});
