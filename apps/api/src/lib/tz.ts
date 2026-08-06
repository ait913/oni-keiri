export const APP_TZ = "Asia/Tokyo";

const ymdFormatter = new Intl.DateTimeFormat("en-CA", {
  timeZone: APP_TZ,
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
});

export function todayJst(now: Date = new Date()): string {
  const parts = Object.fromEntries(ymdFormatter.formatToParts(now).map((part) => [part.type, part.value]));
  return `${parts.year}-${parts.month}-${parts.day}`;
}

export function currentMonthJst(now: Date = new Date()): string {
  return todayJst(now).slice(0, 7);
}

export function addMonths(yearMonth: string, n: number): string {
  const year = Number(yearMonth.slice(0, 4));
  const monthIndex = Number(yearMonth.slice(5, 7)) - 1 + n;
  const nextYear = year + Math.floor(monthIndex / 12);
  const nextMonth = ((monthIndex % 12) + 12) % 12;
  return `${nextYear.toString().padStart(4, "0")}-${(nextMonth + 1).toString().padStart(2, "0")}`;
}
