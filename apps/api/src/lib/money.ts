function isLeapYear(year: number): boolean {
  return year % 400 === 0 || (year % 4 === 0 && year % 100 !== 0);
}

export function daysInMonth(yearMonth: string): number {
  const year = Number(yearMonth.slice(0, 4));
  const month = Number(yearMonth.slice(5, 7));
  if (month === 2) return isLeapYear(year) ? 29 : 28;
  if ([4, 6, 9, 11].includes(month)) return 30;
  return 31;
}

export function clampDay(yearMonth: string, day: number): string {
  const clamped = Math.min(day, daysInMonth(yearMonth));
  return `${yearMonth}-${clamped.toString().padStart(2, "0")}`;
}

export function isValidDate(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const yearMonth = value.slice(0, 7);
  const month = Number(value.slice(5, 7));
  const day = Number(value.slice(8, 10));
  return month >= 1 && month <= 12 && day >= 1 && day <= daysInMonth(yearMonth);
}

export function yearMonthOf(date: string): string {
  return date.slice(0, 7);
}
