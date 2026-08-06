import { describe, expect, it } from "vitest";
import { addMonths, currentMonthJst, todayJst } from "../../src/lib/tz.js";
import { clampDay } from "../../src/lib/money.js";

describe("tz and money helpers (§4.1)", () => {
  it("derives business dates from JST, not UTC", () => {
    expect(todayJst(new Date("2026-08-06T14:59:00Z"))).toBe("2026-08-06");
    expect(todayJst(new Date("2026-08-06T15:00:00Z"))).toBe("2026-08-07");
    expect(todayJst(new Date("2026-08-31T22:00:00Z"))).toBe("2026-09-01");
    expect(currentMonthJst(new Date("2026-08-31T22:00:00Z"))).toBe("2026-09");
  });

  it("adds months across year boundaries", () => {
    expect(addMonths("2026-12", 2)).toBe("2027-02");
    expect(addMonths("2027-01", -2)).toBe("2026-11");
  });

  it("clamps invalid month-end days including leap February", () => {
    expect(clampDay("2027-02", 31)).toBe("2027-02-28");
    expect(clampDay("2028-02", 31)).toBe("2028-02-29");
    expect(clampDay("2026-04", 31)).toBe("2026-04-30");
    expect(clampDay("2026-08", 15)).toBe("2026-08-15");
  });
});
