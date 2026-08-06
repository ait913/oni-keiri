import { Hono } from "hono";
import { and, eq, isNull } from "drizzle-orm";
import { getDb } from "../db/index.js";
import { card, entry } from "../db/schema.js";
import { buildCalendarEvents } from "../lib/calendar.js";
import { todayJst } from "../lib/tz.js";
import type { AppVariables } from "../types.js";
import { cardPaymentRowsForMonth, parseQuery } from "./helpers.js";
import { MonthString, type CalendarResponse } from "./schemas.js";

export const calendarRoutes = new Hono<{ Variables: AppVariables }>();

calendarRoutes.get("/", async (c) => {
  const userId = c.get("user").id;
  const { month } = parseQuery(MonthString.transform((month) => ({ month })), c.req.query("month"));
  const db = getDb();
  const [entries, cards] = await Promise.all([
    db.select().from(entry).where(and(eq(entry.userId, userId), isNull(entry.deletedAt))),
    db.select().from(card).where(eq(card.userId, userId)),
  ]);
  const monthEntries = entries.filter((row) => row.yearMonth === month);
  const cardPayments = await cardPaymentRowsForMonth(cards, entries, month);
  const cardNamesById = Object.fromEntries(cards.map((row) => [row.id, row.name]));
  const result = buildCalendarEvents({
    month,
    entries: monthEntries,
    cardPayments,
    cardNamesById,
  });
  return c.json({ month, today: todayJst(), ...result } satisfies CalendarResponse);
});
