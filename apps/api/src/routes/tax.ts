import { Hono } from "hono";
import { and, eq, gte, isNull, lte } from "drizzle-orm";
import { z } from "zod";
import { getDb } from "../db/index.js";
import { entry } from "../db/schema.js";
import { AppError } from "../lib/appError.js";
import { taxEstimate } from "../lib/tax.js";
import { todayJst } from "../lib/tz.js";
import type { AppVariables } from "../types.js";
import { assertFreelance, parseQuery } from "./helpers.js";
import type { TaxEstimateResponse } from "./schemas.js";

export const taxRoutes = new Hono<{ Variables: AppVariables }>();

taxRoutes.get("/estimate", async (c) => {
  const userId = c.get("user").id;
  await assertFreelance(userId);
  const today = todayJst();
  const currentYear = Number(today.slice(0, 4));
  const parsed = parseQuery(z.object({ year: z.coerce.number().int().min(2020).max(2035).optional() }), { year: c.req.query("year") });
  const year = parsed.year ?? currentYear;
  if (year > currentYear) throw new AppError(400, "VALIDATION_FAILED", "Validation failed");

  const from = `${year}-01-01`;
  const to = year === currentYear ? today : `${year}-12-31`;
  const rows = await getDb().select().from(entry).where(and(
    eq(entry.userId, userId),
    isNull(entry.deletedAt),
    gte(entry.date, from),
    lte(entry.date, to),
  ));
  const businessIncomeYtd = rows
    .filter((row) => row.kind === "income" && row.incomeSource === "salary")
    .reduce((sum, row) => sum + row.amount, 0);
  const businessExpenseYtd = rows
    .filter((row) => row.kind !== "income" && row.category === "business")
    .reduce((sum, row) => sum + row.amount, 0);
  const profitYtd = businessIncomeYtd - businessExpenseYtd;
  const estimated = taxEstimate(profitYtd);
  const monthsElapsed = year === currentYear ? Number(today.slice(5, 7)) : 12;
  return c.json({
    year,
    businessIncomeYtd,
    businessExpenseYtd,
    profitYtd,
    rate: estimated.rate,
    estimatedTax: estimated.amount,
    monthlySetAside: Math.ceil(estimated.amount / monthsElapsed),
    annualProjection: Math.ceil((estimated.amount / monthsElapsed) * 12),
  } satisfies TaxEstimateResponse);
});
