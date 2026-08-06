import type { CardCycleInput } from "./cardSchedule.js";
import { cardPaymentSchedule } from "./cardSchedule.js";

export type CalendarEvent =
  | { type: "fixed_cost"; entryId: string; name: string; date: string; amount: number; cardId: string | null; cardName: string | null; category: string | null }
  | { type: "card_payment"; cardId: string; cardName: string; date: string; amount: number; fromExclusive: string; toInclusive: string; closed: boolean }
  | { type: "salary"; entryId: string; name: string; date: string; amount: number };

export function buildCalendarEvents(input: {
  month: string;
  entries: {
    id: string;
    kind: "expense" | "card_expense" | "income";
    amount: number;
    date: string;
    note: string | null;
    sourceRuleId: string | null;
    cardId: string | null;
    category: string | null;
  }[];
  cards: (CardCycleInput & { id: string; name: string })[];
  cardExpenses: { cardId: string; date: string; amount: number }[];
}): { events: CalendarEvent[]; paymentCount: number; paymentTotal: number } {
  const events: CalendarEvent[] = [];
  const cardNameById = new Map(input.cards.map((card) => [card.id, card.name]));

  for (const entry of input.entries) {
    if (!entry.sourceRuleId || entry.date.slice(0, 7) !== input.month) continue;
    if (entry.kind === "income") {
      events.push({ type: "salary", entryId: entry.id, name: entry.note ?? "", date: entry.date, amount: entry.amount });
    } else {
      events.push({
        type: "fixed_cost",
        entryId: entry.id,
        name: entry.note ?? "",
        date: entry.date,
        amount: entry.amount,
        cardId: entry.cardId,
        cardName: entry.cardId ? cardNameById.get(entry.cardId) ?? null : null,
        category: entry.category,
      });
    }
  }

  for (const card of input.cards) {
    const expenses = input.cardExpenses
      .filter((expense) => expense.cardId === card.id)
      .map((expense) => ({ date: expense.date, amount: expense.amount }));
    const payment = cardPaymentSchedule(card, expenses, input.month).find((item) => item.month === input.month);
    if (payment && payment.amount > 0) {
      events.push({
        type: "card_payment",
        cardId: card.id,
        cardName: card.name,
        date: payment.paymentDate,
        amount: payment.amount,
        fromExclusive: payment.fromExclusive,
        toInclusive: payment.toInclusive,
        closed: payment.closed,
      });
    }
  }

  events.sort((a, b) => a.date.localeCompare(b.date));
  const payableEvents = events.filter((event) => event.type !== "salary");
  const paymentTotal = payableEvents.reduce((sum, event) => {
    if (event.type === "fixed_cost" && event.cardId) return sum;
    return sum + event.amount;
  }, 0);

  return { events, paymentCount: payableEvents.length, paymentTotal };
}
