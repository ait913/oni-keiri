import { Hono } from "hono";
import { and, eq, isNull } from "drizzle-orm";
import { getDb } from "../db/index.js";
import { card, entry } from "../db/schema.js";
import { buildCalendarEvents } from "../lib/calendar.js";
import { todayJst } from "../lib/tz.js";
import type { AppVariables } from "../types.js";
import { parseQuery } from "./helpers.js";
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
  const result = buildCalendarEvents({
    month,
    entries,
    cards,
    cardExpenses: entries
      .filter((row) => row.kind === "card_expense" && row.cardId)
      .map((row) => ({ cardId: row.cardId as string, date: row.date, amount: row.amount })),
  });
  return c.json({ month, today: todayJst(), ...result } satisfies CalendarResponse);
});

