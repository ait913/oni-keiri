import { addMonths, todayJst } from "./tz.js";
import { clampDay } from "./money.js";

export type CardCycleInput = {
  closingDay: number;
  paymentDay: number;
  revolvingAmount: number | null;
  carryoverBalance: number;
  createdDate: string;
};

type Expense = { date: string; amount: number };

function firstPaymentMonth(card: CardCycleInput): string {
  let closingMonth = card.createdDate.slice(0, 7);
  while (clampDay(closingMonth, card.closingDay) < card.createdDate) {
    closingMonth = addMonths(closingMonth, 1);
  }
  return addMonths(closingMonth, 1);
}

function compareYearMonth(a: string, b: string): number {
  return a === b ? 0 : a < b ? -1 : 1;
}

export function cycleRange(card: CardCycleInput, paymentMonth: string): { fromExclusive: string; toInclusive: string } {
  return {
    fromExclusive: clampDay(addMonths(paymentMonth, -2), card.closingDay),
    toInclusive: clampDay(addMonths(paymentMonth, -1), card.closingDay),
  };
}

export function cardPaymentSchedule(
  card: CardCycleInput,
  expenses: Expense[],
  throughMonth: string,
): { month: string; paymentDate: string; amount: number; fromExclusive: string; toInclusive: string; closed: boolean; balanceAfter: number }[] {
  const startMonth = firstPaymentMonth(card);
  if (compareYearMonth(startMonth, throughMonth) > 0) return [];

  const today = todayJst();
  const result: { month: string; paymentDate: string; amount: number; fromExclusive: string; toInclusive: string; closed: boolean; balanceAfter: number }[] = [];
  let balance = card.carryoverBalance;

  for (let month = startMonth; compareYearMonth(month, throughMonth) <= 0; month = addMonths(month, 1)) {
    const { fromExclusive, toInclusive } = cycleRange(card, month);
    const purchases = expenses
      .filter((expense) => expense.date > fromExclusive && expense.date <= toInclusive)
      .reduce((sum, expense) => sum + expense.amount, 0);
    const payable = balance + purchases;
    const amount = card.revolvingAmount === null ? payable : Math.min(card.revolvingAmount, payable);
    balance = payable - amount;

    result.push({
      month,
      paymentDate: clampDay(month, card.paymentDay),
      amount,
      fromExclusive,
      toInclusive,
      closed: today > clampDay(addMonths(month, -1), card.closingDay),
      balanceAfter: balance,
    });
  }

  return result;
}

export function cardUtilization(card: CardCycleInput, expenses: Expense[], today: string): number {
  const purchases = expenses
    .filter((expense) => expense.date <= today)
    .reduce((sum, expense) => sum + expense.amount, 0);
  const schedule = cardPaymentSchedule(card, expenses, today.slice(0, 7));
  const paid = schedule
    .filter((payment) => payment.paymentDate <= today)
    .reduce((sum, payment) => sum + payment.amount, 0);
  return Math.max(card.carryoverBalance + purchases - paid, 0);
}
