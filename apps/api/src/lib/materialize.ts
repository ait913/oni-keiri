import { and, eq, gt, isNotNull, isNull } from "drizzle-orm";
import { entry, recurringRule } from "../db/schema.js";
import type { Db } from "../db/index.js";
import { addMonths, currentMonthJst, todayJst } from "./tz.js";
import { clampDay } from "./money.js";

export type MaterializedRule = typeof recurringRule.$inferSelect;

function materializedEntryFor(rule: MaterializedRule, yearMonth: string) {
  const date = clampDay(yearMonth, rule.dayOfMonth);
  if (rule.direction === "income") {
    return {
      userId: rule.userId,
      kind: "income" as const,
      amount: rule.amount,
      date,
      yearMonth,
      category: null,
      cardId: null,
      incomeSource: "salary" as const,
      note: rule.name,
      sourceRuleId: rule.id,
    };
  }

  return {
    userId: rule.userId,
    kind: rule.cardId ? "card_expense" as const : "expense" as const,
    amount: rule.amount,
    date,
    yearMonth,
    category: rule.category,
    cardId: rule.cardId,
    incomeSource: null,
    note: rule.name,
    sourceRuleId: rule.id,
  };
}

function windowMonths(now: Date): string[] {
  const currentMonth = currentMonthJst(now);
  return [currentMonth, addMonths(currentMonth, 1), addMonths(currentMonth, 2)];
}

async function insertMissingForRule(db: Db, rule: MaterializedRule, months: string[]): Promise<void> {
  for (const yearMonth of months) {
    if (yearMonth < rule.startMonth) continue;
    await db.insert(entry).values(materializedEntryFor(rule, yearMonth)).onConflictDoNothing();
  }
}

export async function ensureMaterializedForUser(db: Db, userId: string, now: Date = new Date()): Promise<void> {
  const rules = await db
    .select()
    .from(recurringRule)
    .where(and(eq(recurringRule.userId, userId), eq(recurringRule.active, true)));
  const months = windowMonths(now);

  for (const rule of rules) {
    await insertMissingForRule(db, rule, months);
  }
}

export async function rematerializeRule(db: Db, rule: MaterializedRule, now: Date = new Date()): Promise<void> {
  const today = todayJst(now);
  const months = windowMonths(now);

  await db.transaction(async (tx: any) => {
    await tx
      .delete(entry)
      .where(and(
        eq(entry.sourceRuleId, rule.id),
        gt(entry.date, today),
        eq(entry.isManuallyEdited, false),
        isNull(entry.deletedAt),
        isNotNull(entry.sourceRuleId),
      ));

    if (!rule.active) return;

    for (const yearMonth of months) {
      if (yearMonth < rule.startMonth) continue;
      const nextEntry = materializedEntryFor(rule, yearMonth);
      if (nextEntry.date <= today) continue;
      await tx.insert(entry).values(nextEntry).onConflictDoNothing();
    }
  });
}
