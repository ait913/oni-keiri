export type CalendarEvent =
  | { type: "fixed_cost"; entryId: string; name: string; date: string; amount: number; cardId: string | null; cardName: string | null; category: string | null }
  | { type: "card_payment"; cardId: string; cardName: string; date: string; amount: number; fromExclusive: string; toInclusive: string; closed: boolean }
  | { type: "salary"; entryId: string; name: string; date: string; amount: number };

export type EntryRow = {
  id: string;
  kind: "expense" | "card_expense" | "income";
  amount: number;
  date: string;
  category: string | null;
  cardId: string | null;
  incomeSource: "salary" | "other" | null;
  note: string | null;
  sourceRuleId: string | null;
};

export type CardPaymentRow = {
  cardId: string;
  cardName: string;
  paymentDate: string;
  amount: number;
  fromExclusive: string;
  toInclusive: string;
  closed: boolean;
};

const EVENT_TYPE_ORDER: Record<CalendarEvent["type"], number> = {
  fixed_cost: 0,
  salary: 1,
  card_payment: 2,
};

function eventId(event: CalendarEvent): string {
  return event.type === "card_payment" ? event.cardId : event.entryId;
}

export function buildCalendarEvents(input: {
  month: string;
  entries: EntryRow[];
  cardPayments: CardPaymentRow[];
  cardNamesById: Record<string, string>;
}): { events: CalendarEvent[]; paymentCount: number; paymentTotal: number } {
  const events: CalendarEvent[] = [];

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
        cardName: entry.cardId ? input.cardNamesById[entry.cardId] ?? null : null,
        category: entry.category,
      });
    }
  }

  for (const payment of input.cardPayments) {
    if (payment.paymentDate.slice(0, 7) === input.month && payment.amount > 0) {
      events.push({
        type: "card_payment",
        cardId: payment.cardId,
        cardName: payment.cardName,
        date: payment.paymentDate,
        amount: payment.amount,
        fromExclusive: payment.fromExclusive,
        toInclusive: payment.toInclusive,
        closed: payment.closed,
      });
    }
  }

  events.sort((a, b) => a.date.localeCompare(b.date)
    || EVENT_TYPE_ORDER[a.type] - EVENT_TYPE_ORDER[b.type]
    || eventId(a).localeCompare(eventId(b)));

  return { events, paymentCount: paymentCountOf(events), paymentTotal: paymentTotalOf(events) };
}

export function paymentCountOf(events: CalendarEvent[]): number {
  return events.filter((event) => event.type === "fixed_cost" || event.type === "card_payment").length;
}

export function paymentTotalOf(events: CalendarEvent[]): number {
  return events.reduce((sum, event) => {
    if (event.type === "salary") return sum;
    if (event.type === "fixed_cost" && event.cardId) return sum;
    return sum + event.amount;
  }, 0);
}
