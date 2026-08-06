import { daysInMonth, yearMonthOf } from "./money.js";

export type SummaryEntry = {
  kind: "expense" | "card_expense" | "income";
  amount: number;
  date: string;
  category?: string | null;
  sourceRuleId?: string | null;
};

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

export function buildBreakdown(entries: SummaryEntry[]): { category: string; amount: number }[] {
  const totals = new Map<string, number>();
  for (const entry of entries) {
    if (entry.kind === "income") continue;
    const category = entry.category ?? "other";
    totals.set(category, (totals.get(category) ?? 0) + entry.amount);
  }
  return [...totals.entries()]
    .filter(([, amount]) => amount > 0)
    .map(([category, amount]) => ({ category, amount }))
    .sort((a, b) => b.amount - a.amount);
}

export function buildQuality(entries: SummaryEntry[]): { fixed: number; variable: number; savingTip: number } {
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
  today: string;
  month: string;
  entries: SummaryEntry[];
  cardPayments: CardPayment[];
  savingsGoal: number | null;
  upcomingPayments: { amount: number; cardId?: string | null }[];
  employmentType: "employee" | "freelance" | "part_time" | "contract";
}): {
  today: string;
  month: string;
  spendable: number;
  remaining: number;
  income: number;
  spending: number;
  cashExpense: number;
  cardPaymentDue: number;
  cardUsage: number;
  savingsGoal: number | null;
  dailySeries: { date: string; value: number; projected: boolean }[];
  minPoint: { date: string; value: number };
  upcomingPayments: { amount: number; cardId?: string | null }[];
  upcomingTotal: number;
  employmentType: "employee" | "freelance" | "part_time" | "contract";
} {
  const monthEntries = input.entries.filter((entry) => yearMonthOf(entry.date) === input.month);
  const income = monthEntries.filter((entry) => entry.kind === "income").reduce((sum, entry) => sum + entry.amount, 0);
  const cashExpense = monthEntries.filter((entry) => entry.kind === "expense").reduce((sum, entry) => sum + entry.amount, 0);
  const cardUsage = monthEntries.filter((entry) => entry.kind === "card_expense").reduce((sum, entry) => sum + entry.amount, 0);
  const cardPaymentDue = input.cardPayments.reduce((sum, payment) => sum + payment.amount, 0);
  const spending = cashExpense + cardPaymentDue;
  const remaining = income - spending;
  const spendable = remaining - (input.savingsGoal ?? 0);
  const { series: dailySeries, minPoint } = buildDailySeries({
    month: input.month,
    today: input.today,
    entries: monthEntries.filter((entry): entry is SummaryEntry & { kind: "expense" | "income" } => entry.kind !== "card_expense"),
    cardPayments: input.cardPayments,
  });

  return {
    today: input.today,
    month: input.month,
    spendable,
    remaining,
    income,
    spending,
    cashExpense,
    cardPaymentDue,
    cardUsage,
    savingsGoal: input.savingsGoal,
    dailySeries,
    minPoint,
    upcomingPayments: input.upcomingPayments,
    upcomingTotal: input.upcomingPayments.reduce((sum, event) => sum + (event.cardId ? 0 : event.amount), 0),
    employmentType: input.employmentType,
  };
}
