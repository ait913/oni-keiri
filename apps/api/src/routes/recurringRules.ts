import { Hono } from "hono";
import { and, eq } from "drizzle-orm";
import { z } from "zod";
import { getDb } from "../db/index.js";
import { recurringRule } from "../db/schema.js";
import { AppError } from "../lib/appError.js";
import { ensureMaterializedForUser, rematerializeRule } from "../lib/materialize.js";
import { currentMonthJst } from "../lib/tz.js";
import type { AppVariables } from "../types.js";
import {
  assertFreelance,
  parseJson,
  parseQuery,
  recurringRuleDto,
  requireOwnedCard,
  requireOwnedRule,
} from "./helpers.js";
import { CreateRuleBody, UpdateRuleBody, type RecurringRuleDto } from "./schemas.js";

export const recurringRulesRoutes = new Hono<{ Variables: AppVariables }>();

function validationFailed(): never {
  throw new AppError(400, "VALIDATION_FAILED", "Validation failed");
}

async function validateRuleFields(userId: string, body: {
  direction: "expense" | "income";
  cardId?: string | null;
  category?: string | null;
}): Promise<void> {
  if (body.direction === "income" && (body.cardId || body.category)) validationFailed();
  if (body.direction === "expense" && body.cardId) await requireOwnedCard(body.cardId, userId);
  if (body.direction === "expense" && body.category === "business") await assertFreelance(userId);
}

recurringRulesRoutes.get("/", async (c) => {
  const userId = c.get("user").id;
  const { direction } = parseQuery(z.object({ direction: z.enum(["expense", "income"]).optional() }), { direction: c.req.query("direction") });
  const where = direction ? and(eq(recurringRule.userId, userId), eq(recurringRule.direction, direction)) : eq(recurringRule.userId, userId);
  const rows = await getDb().select().from(recurringRule).where(where);
  return c.json({ rules: rows.map(recurringRuleDto) });
});

recurringRulesRoutes.post("/", async (c) => {
  const userId = c.get("user").id;
  const body = await parseJson(CreateRuleBody, c);
  await validateRuleFields(userId, body);
  const rows = await getDb().insert(recurringRule).values({
    userId,
    direction: body.direction,
    name: body.name,
    amount: body.amount,
    dayOfMonth: body.dayOfMonth,
    cardId: body.direction === "expense" ? body.cardId ?? null : null,
    category: body.direction === "expense" ? body.category ?? null : null,
    startMonth: currentMonthJst(),
  }).returning();
  await ensureMaterializedForUser(getDb(), userId);
  return c.json(recurringRuleDto(rows[0]) satisfies RecurringRuleDto, 201);
});

recurringRulesRoutes.patch("/:id", async (c) => {
  const userId = c.get("user").id;
  const current = await requireOwnedRule(c.req.param("id"), userId);
  const body = await parseJson(UpdateRuleBody, c);
  const nextDirection = current.direction;
  await validateRuleFields(userId, {
    direction: nextDirection,
    cardId: body.cardId === undefined ? current.cardId : body.cardId,
    category: body.category === undefined ? current.category : body.category,
  });
  const rows = await getDb().update(recurringRule).set({
    name: body.name ?? current.name,
    amount: body.amount ?? current.amount,
    dayOfMonth: body.dayOfMonth ?? current.dayOfMonth,
    cardId: nextDirection === "expense" ? (body.cardId === undefined ? current.cardId : body.cardId ?? null) : null,
    category: nextDirection === "expense" ? (body.category === undefined ? current.category : body.category ?? null) : null,
    active: body.active ?? current.active,
    updatedAt: new Date(),
  }).where(and(eq(recurringRule.id, current.id), eq(recurringRule.userId, userId))).returning();
  await rematerializeRule(getDb(), rows[0]);
  return c.json(recurringRuleDto(rows[0]) satisfies RecurringRuleDto);
});

recurringRulesRoutes.delete("/:id", async (c) => {
  const userId = c.get("user").id;
  const current = await requireOwnedRule(c.req.param("id"), userId);
  await rematerializeRule(getDb(), { ...current, active: false });
  await getDb().delete(recurringRule).where(and(eq(recurringRule.id, current.id), eq(recurringRule.userId, userId)));
  return c.body(null, 204);
});
