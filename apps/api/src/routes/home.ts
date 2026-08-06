import { Hono } from "hono";
import { and, eq, isNull } from "drizzle-orm";
import { z } from "zod";
import { getDb } from "../db/index.js";
import { card, entry } from "../db/schema.js";
import { buildCalendarEvents } from "../lib/calendar.js";
import { buildHomeSummary } from "../lib/homeSummary.js";
import { currentMonthJst, todayJst } from "../lib/tz.js";
import type { AppVariables } from "../types.js";
import { parseQuery, requireSettings } from "./helpers.js";
import { MonthString, type HomeResponse } from "./schemas.js";

export const homeRoutes = new Hono<{ Variables: AppVariables }>();

homeRoutes.get("/", async (c) => {
  const userId = c.get("user").id;
  const { month } = parseQuery(z.object({ month: MonthString.optional() }), { month: c.req.query("month") });
  const targetMonth = month ?? currentMonthJst();
  const today = todayJst();
  const db = getDb();
  const [settings, entries, cards] = await Promise.all([
    requireSettings(userId),
    db.select().from(entry).where(and(eq(entry.userId, userId), isNull(entry.deletedAt))),
    db.select().from(card).where(eq(card.userId, userId)),
  ]);
  const calendar = buildCalendarEvents({
    month: targetMonth,
    entries,
    cards,
    cardExpenses: entries
      .filter((row) => row.kind === "card_expense" && row.cardId)
      .map((row) => ({ cardId: row.cardId as string, date: row.date, amount: row.amount })),
  });
  const cardPayments = calendar.events
    .filter((event): event is Extract<typeof event, { type: "card_payment" }> => event.type === "card_payment")
    .map((event) => ({ paymentDate: event.date, amount: event.amount }));
  const upcomingPayments = calendar.events.filter((event) => event.type !== "salary" && event.date > today);
  return c.json(buildHomeSummary({
    today,
    month: targetMonth,
    entries,
    cardPayments,
    savingsGoal: settings.savingsGoal,
    upcomingPayments,
    employmentType: settings.employmentType,
  }) as HomeResponse);
});

