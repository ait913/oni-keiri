import { z } from "zod";
import { isValidDate } from "../lib/money.js";

export const ENTRY_CATEGORIES = ["food", "daily", "transport", "entertainment", "housing", "business", "health", "other"] as const;
export const EMPLOYMENT_TYPES = ["employee", "freelance", "part_time", "contract"] as const;

const Amount = z.number().int().min(1).max(99_999_999);
export const DateString = z.string().refine((value) => {
  if (!isValidDate(value)) return false;
  return value >= "2020-01-01" && value <= "2035-12-31";
});
export const MonthString = z.string().regex(/^\d{4}-\d{2}$/).refine((value) => {
  const month = Number(value.slice(5, 7));
  return value >= "2020-01" && value <= "2035-12" && month >= 1 && month <= 12;
});

export const PutSettingsBody = z.object({
  employmentType: z.enum(EMPLOYMENT_TYPES),
  savingsGoal: Amount.nullish(),
});
export const CreateEntryBody = z.object({
  kind: z.enum(["expense", "card_expense", "income"]),
  amount: Amount,
  date: DateString,
  category: z.enum(ENTRY_CATEGORIES).nullish(),
  cardId: z.string().uuid().nullish(),
  incomeSource: z.enum(["salary", "other"]).nullish(),
  note: z.string().max(100).nullish(),
});
export const CreateSalaryBody = z.object({
  amount: Amount,
  date: DateString,
  note: z.string().max(100).nullish(),
  expenses: z.array(z.object({
    amount: Amount,
    note: z.string().max(100).nullish(),
  })).max(20).default([]),
});
export const UpdateEntryBody = z.object({
  amount: Amount.optional(),
  date: DateString.optional(),
  category: z.enum(ENTRY_CATEGORIES).nullish(),
  incomeSource: z.enum(["salary", "other"]).optional(),
  note: z.string().max(100).nullish(),
});
export const CreateCardBody = z.object({
  name: z.string().min(1).max(20),
  closingDay: z.number().int().min(1).max(31),
  paymentDay: z.number().int().min(1).max(31),
  revolvingAmount: z.number().int().min(1).nullish(),
  creditLimit: z.number().int().min(1).nullish(),
  carryoverBalance: z.number().int().min(0).default(0),
});
export const UpdateCardBody = CreateCardBody.partial().extend({ archived: z.boolean().optional() });
export const CreateRuleBody = z.object({
  direction: z.enum(["expense", "income"]),
  name: z.string().min(1).max(30),
  amount: Amount,
  dayOfMonth: z.number().int().min(1).max(31),
  cardId: z.string().uuid().nullish(),
  category: z.enum(ENTRY_CATEGORIES).nullish(),
});
export const UpdateRuleBody = CreateRuleBody.omit({ direction: true }).partial().extend({ active: z.boolean().optional() });

export type SettingsDto = { employmentType: (typeof EMPLOYMENT_TYPES)[number]; savingsGoal: number | null };
export type EntryDto = {
  id: string; kind: "expense" | "card_expense" | "income"; amount: number;
  date: string; yearMonth: string; category: string | null; cardId: string | null;
  incomeSource: "salary" | "other" | null;
  note: string | null; sourceRuleId: string | null; isManuallyEdited: boolean;
};
export type DailyPoint = { date: string; value: number; projected: boolean };
export type CategoryBreakdownItem = { category: string; amount: number };
export type CalendarEvent =
  | { type: "fixed_cost"; entryId: string; name: string; date: string; amount: number;
      cardId: string | null; cardName: string | null; category: string | null }
  | { type: "card_payment"; cardId: string; cardName: string; date: string; amount: number;
      fromExclusive: string; toInclusive: string; closed: boolean }
  | { type: "salary"; entryId: string; name: string; date: string; amount: number };
export type CalendarResponse = {
  month: string; today: string;
  events: CalendarEvent[];
  paymentCount: number; paymentTotal: number;
};
export type HomeResponse = {
  today: string; month: string;
  spendable: number; remaining: number; income: number; spending: number;
  cashExpense: number; cardPaymentDue: number; cardUsage: number;
  savingsGoal: number | null;
  dailySeries: DailyPoint[];
  minPoint: { date: string; value: number };
  upcomingPayments: CalendarEvent[];
  upcomingTotal: number;
  employmentType: (typeof EMPLOYMENT_TYPES)[number];
};
export type EntriesResponse = {
  entries: EntryDto[];
  breakdown: CategoryBreakdownItem[];
  quality: { fixed: number; variable: number; savingTip: number };
};
export type CardDto = {
  id: string; name: string; closingDay: number; paymentDay: number;
  revolvingAmount: number | null; creditLimit: number | null; carryoverBalance: number;
  archived: boolean;
  utilization: number;
  monthUsage: number;
  nextPayment: { month: string; paymentDate: string; amount: number; closed: boolean } | null;
};
export type CardDetailResponse = {
  card: CardDto;
  payments: { month: string; paymentDate: string; amount: number; fromExclusive: string; toInclusive: string; closed: boolean; balanceAfter: number }[];
  recentExpenses: EntryDto[];
  linkedRules: RecurringRuleDto[];
};
export type RecurringRuleDto = {
  id: string; direction: "expense" | "income"; name: string; amount: number; dayOfMonth: number;
  cardId: string | null; category: string | null; startMonth: string; active: boolean;
};
export type TaxEstimateResponse = {
  year: number; businessIncomeYtd: number; businessExpenseYtd: number;
  profitYtd: number; rate: number; estimatedTax: number;
  monthlySetAside: number; annualProjection: number;
};
