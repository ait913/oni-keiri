import { Hono } from "hono";
import { eq } from "drizzle-orm";
import { getDb } from "../db/index.js";
import { user } from "../db/auth-schema.js";
import type { AppVariables } from "../types.js";
import { getSettings, settingsDto } from "./helpers.js";
import type { SettingsDto } from "./schemas.js";

export const meRoutes = new Hono<{ Variables: AppVariables }>();

meRoutes.get("/", async (c) => {
  const currentUser = c.get("user");
  const settings = await getSettings(currentUser.id);
  return c.json({
    user: { id: currentUser.id, name: currentUser.name, email: currentUser.email },
    onboarded: settings !== null,
    settings: settings ? settingsDto(settings) : null,
  } satisfies { user: { id: string; name: string; email: string }; onboarded: boolean; settings: SettingsDto | null });
});

meRoutes.delete("/", async (c) => {
  await getDb().delete(user).where(eq(user.id, c.get("user").id));
  return c.body(null, 204);
});

