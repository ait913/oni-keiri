import { Hono } from "hono";
import { and, eq, isNull } from "drizzle-orm";
import { z } from "zod";
import { getDb } from "../db/index.js";
import { card, entry } from "../db/schema.js";
import { buildCalendarEvents, paymentTotalOf } from "../lib/calendar.js";
import { buildDailySeries, buildHomeSummary } from "../lib/homeSummary.js";
import { currentMonthJst, todayJst } from "../lib/tz.js";
import type { AppVariables } from "../types.js";
import { cardPaymentRowsForMonth, parseQuery, requireSettings } from "./helpers.js";
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
  const monthEntries = entries.filter((row) => row.yearMonth === targetMonth);
  const cardPayments = await cardPaymentRowsForMonth(cards, entries, targetMonth);
  const cardNamesById = Object.fromEntries(cards.map((row) => [row.id, row.name]));
  const calendar = buildCalendarEvents({
    month: targetMonth,
    entries: monthEntries,
    cardPayments,
    cardNamesById,
  });
  const upcomingPayments = calendar.events.filter((event) => event.type !== "salary" && event.date > today);
  const summary = buildHomeSummary({
    entries: monthEntries,
    cardPayments,
    savingsGoal: settings.savingsGoal,
  });
  const { series: dailySeries, minPoint } = buildDailySeries({
    month: targetMonth,
    today,
    entries: monthEntries.filter((row): row is typeof row & { kind: "expense" | "income" } => row.kind !== "card_expense"),
    cardPayments,
  });
  return c.json({
    today,
    month: targetMonth,
    ...summary,
    savingsGoal: settings.savingsGoal,
    dailySeries,
    minPoint,
    upcomingPayments,
    upcomingTotal: paymentTotalOf(upcomingPayments),
    employmentType: settings.employmentType,
  } satisfies HomeResponse);
});
