import { describe, expect, it } from "vitest";
import { taxEstimate } from "../../src/lib/tax.js";

describe("taxEstimate (§4.5)", () => {
  it.each([
    [-1, 0.15, 0],
    [0, 0.15, 0],
    [1_000_000, 0.15, 150_000],
    [1_000_001, 0.20, 200_000],
    [2_000_000, 0.20, 400_000],
    [2_000_001, 0.25, 500_000],
    [4_000_000, 0.25, 1_000_000],
    [4_000_001, 0.30, 1_200_000],
    [6_000_000, 0.30, 1_800_000],
    [6_000_001, 0.35, 2_100_000],
    [10_000_000, 0.35, 3_500_000],
    [10_000_001, 0.40, 4_000_000],
    [99_999_999, 0.40, 39_999_999],
  ])("uses the lower bracket boundary for profit %i", (profit, rate, amount) => {
    expect(taxEstimate(profit)).toEqual({ rate, amount });
  });
});
