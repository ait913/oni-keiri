import { Hono } from "hono";
import { eq } from "drizzle-orm";
import { getDb } from "../db/index.js";
import { userSettings } from "../db/schema.js";
import type { AppVariables } from "../types.js";
import { parseJson, requireSettings, settingsDto } from "./helpers.js";
import { PutSettingsBody, type SettingsDto } from "./schemas.js";

export const settingsRoutes = new Hono<{ Variables: AppVariables }>();

settingsRoutes.get("/", async (c) => {
  const settings = await requireSettings(c.get("user").id);
  return c.json(settingsDto(settings) satisfies SettingsDto);
});

settingsRoutes.put("/", async (c) => {
  const userId = c.get("user").id;
  const body = await parseJson(PutSettingsBody, c);
  const now = new Date();
  const rows = await getDb()
    .insert(userSettings)
    .values({
      userId,
      employmentType: body.employmentType,
      savingsGoal: body.savingsGoal ?? null,
      createdAt: now,
      updatedAt: now,
    })
    .onConflictDoUpdate({
      target: userSettings.userId,
      set: {
        employmentType: body.employmentType,
        savingsGoal: body.savingsGoal ?? null,
        updatedAt: now,
      },
    })
    .returning();
  return c.json(settingsDto(rows[0]));
});

