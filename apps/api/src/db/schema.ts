import { boolean, date, index, integer, pgEnum, pgTable, text, timestamp, uniqueIndex, uuid } from "drizzle-orm/pg-core";
import { sql } from "drizzle-orm";
import { user } from "./auth-schema.js";

export const entryKindEnum = pgEnum("entry_kind", ["expense", "card_expense", "income"]);
export const incomeSourceEnum = pgEnum("income_source", ["salary", "other"]);
export const entryCategoryEnum = pgEnum("entry_category", ["food", "daily", "transport", "entertainment", "housing", "business", "health", "other"]);
export const employmentTypeEnum = pgEnum("employment_type", ["employee", "freelance", "part_time", "contract"]);
export const ruleDirectionEnum = pgEnum("rule_direction", ["expense", "income"]);

export const userSettings = pgTable("user_settings", {
  userId: text("user_id").primaryKey().references(() => user.id, { onDelete: "cascade" }),
  employmentType: employmentTypeEnum("employment_type").notNull(),
  savingsGoal: integer("savings_goal"),
  // 将来の精密税計算は additive カラムとしてここに足す
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
});

export const card = pgTable("card", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: text("user_id").notNull().references(() => user.id, { onDelete: "cascade" }),
  name: text("name").notNull(),
  closingDay: integer("closing_day").notNull(),
  paymentDay: integer("payment_day").notNull(),
  revolvingAmount: integer("revolving_amount"),
  creditLimit: integer("credit_limit"),
  carryoverBalance: integer("carryover_balance").notNull().default(0),
  createdDate: date("created_date", { mode: "string" }).notNull(),
  archived: boolean("archived").notNull().default(false),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
}, (t) => [index("card_user_idx").on(t.userId)]);

export const recurringRule = pgTable("recurring_rule", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: text("user_id").notNull().references(() => user.id, { onDelete: "cascade" }),
  direction: ruleDirectionEnum("direction").notNull(),
  name: text("name").notNull(),
  amount: integer("amount").notNull(),
  dayOfMonth: integer("day_of_month").notNull(),
  cardId: uuid("card_id").references(() => card.id, { onDelete: "restrict" }),
  category: entryCategoryEnum("category"),
  startMonth: text("start_month").notNull(),
  active: boolean("active").notNull().default(true),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
}, (t) => [index("recurring_rule_user_idx").on(t.userId)]);

export const entry = pgTable("entry", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: text("user_id").notNull().references(() => user.id, { onDelete: "cascade" }),
  kind: entryKindEnum("kind").notNull(),
  amount: integer("amount").notNull(),
  date: date("date", { mode: "string" }).notNull(),
  yearMonth: text("year_month").notNull(),
  category: entryCategoryEnum("category"),
  cardId: uuid("card_id").references(() => card.id, { onDelete: "restrict" }),
  incomeSource: incomeSourceEnum("income_source"),
  note: text("note"),
  sourceRuleId: uuid("source_rule_id").references(() => recurringRule.id, { onDelete: "set null" }),
  isManuallyEdited: boolean("is_manually_edited").notNull().default(false),
  deletedAt: timestamp("deleted_at", { withTimezone: true }),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
}, (t) => [
  uniqueIndex("entry_rule_month_uq").on(t.sourceRuleId, t.yearMonth).where(sql`${t.sourceRuleId} is not null`),
  index("entry_user_month_idx").on(t.userId, t.yearMonth),
  index("entry_user_card_date_idx").on(t.userId, t.cardId, t.date),
]);
