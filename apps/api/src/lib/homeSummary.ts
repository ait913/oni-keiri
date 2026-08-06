import { daysInMonth } from "./money.js";
import type { CardPaymentRow, EntryRow } from "./calendar.js";

export type CardPayment = { paymentDate: string; amount: number };

export function buildDailySeries(input: {
  month: string;
  today: string;
  entries: { kind: "expense" | "income"; amount: number; date: string }[];
  cardPayments: CardPayment[];
}): { series: { date: string; value: number; projected: boolean }[]; minPoint: { date: string; value: number } } {
  let value = 0;
  const series: { date: string; value: number; projected: boolean }[] = [];
  let minPoint: { date: string; value: number } | null = null;

  for (let day = 1; day <= daysInMonth(input.month); day += 1) {
    const date = `${input.month}-${day.toString().padStart(2, "0")}`;
    for (const entry of input.entries.filter((item) => item.date === date)) {
      value += entry.kind === "income" ? entry.amount : -entry.amount;
    }
    for (const payment of input.cardPayments.filter((item) => item.paymentDate === date)) {
      value -= payment.amount;
    }
    const point = { date, value, projected: date > input.today };
    series.push(point);
    if (!minPoint || point.value < minPoint.value) {
      minPoint = { date: point.date, value: point.value };
    }
  }

  return { series, minPoint: minPoint ?? { date: `${input.month}-01`, value: 0 } };
}

const CATEGORY_ORDER = ["food", "daily", "transport", "entertainment", "housing", "business", "health", "other"] as const;

export function buildBreakdown(entries: EntryRow[]): { category: string; amount: number }[] {
  const totals = new Map<string, number>();
  for (const entry of entries) {
    if (entry.kind === "income") continue;
    const category = entry.category ?? "other";
    totals.set(category, (totals.get(category) ?? 0) + entry.amount);
  }
  return [...totals.entries()]
    .filter(([, amount]) => amount > 0)
    .map(([category, amount]) => ({ category, amount }))
    .sort((a, b) => b.amount - a.amount || CATEGORY_ORDER.indexOf(a.category as (typeof CATEGORY_ORDER)[number]) - CATEGORY_ORDER.indexOf(b.category as (typeof CATEGORY_ORDER)[number]));
}

export function buildQuality(entries: EntryRow[]): { fixed: number; variable: number; savingTip: number } {
  let fixed = 0;
  let variable = 0;
  for (const entry of entries) {
    if (entry.kind === "income") continue;
    if (entry.sourceRuleId) fixed += entry.amount;
    else variable += entry.amount;
  }
  return { fixed, variable, savingTip: Math.floor(variable / 10) };
}

export function buildHomeSummary(input: {
  entries: EntryRow[];
  cardPayments: CardPaymentRow[];
  savingsGoal: number | null;
}): {
  income: number;
  cashExpense: number;
  cardPaymentDue: number;
  cardUsage: number;
  spending: number;
  remaining: number;
  spendable: number;
} {
  const monthEntries = input.entries;
  const income = monthEntries.filter((entry) => entry.kind === "income").reduce((sum, entry) => sum + entry.amount, 0);
  const cashExpense = monthEntries.filter((entry) => entry.kind === "expense").reduce((sum, entry) => sum + entry.amount, 0);
  const cardUsage = monthEntries.filter((entry) => entry.kind === "card_expense").reduce((sum, entry) => sum + entry.amount, 0);
  const cardPaymentDue = input.cardPayments.reduce((sum, payment) => sum + payment.amount, 0);
  const spending = cashExpense + cardPaymentDue;
  const remaining = income - spending;
  const spendable = remaining - (input.savingsGoal ?? 0);

  return {
    income,
    cashExpense,
    cardPaymentDue,
    cardUsage,
    spending,
    remaining,
    spendable,
  };
}
