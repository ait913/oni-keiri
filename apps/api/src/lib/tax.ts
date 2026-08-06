export const TAX_BRACKETS: ReadonlyArray<{ maxProfit: number | null; rate: number }> = [
  { maxProfit: 1_000_000, rate: 0.15 },
  { maxProfit: 2_000_000, rate: 0.20 },
  { maxProfit: 4_000_000, rate: 0.25 },
  { maxProfit: 6_000_000, rate: 0.30 },
  { maxProfit: 10_000_000, rate: 0.35 },
  { maxProfit: null, rate: 0.40 },
];

export function taxEstimate(profitYtd: number): { rate: number; amount: number } {
  const taxableProfit = Math.max(profitYtd, 0);
  const bracket = TAX_BRACKETS.find((item) => item.maxProfit === null || taxableProfit <= item.maxProfit) ?? TAX_BRACKETS[0];
  return {
    rate: bracket.rate,
    amount: Math.floor(taxableProfit * bracket.rate),
  };
}
