import { Hono } from "hono";
import { getAuth } from "./auth.js";
import { AppError } from "./lib/appError.js";
import { ensureMaterialized } from "./middleware/materialize.js";
import { sessionMiddleware } from "./middleware/session.js";
import { calendarRoutes } from "./routes/calendar.js";
import { cardsRoutes } from "./routes/cards.js";
import { entriesRoutes } from "./routes/entries.js";
import { homeRoutes } from "./routes/home.js";
import { meRoutes } from "./routes/me.js";
import { recurringRulesRoutes } from "./routes/recurringRules.js";
import { settingsRoutes } from "./routes/settings.js";
import { taxRoutes } from "./routes/tax.js";
import type { AppVariables } from "./types.js";

export const app = new Hono<{ Variables: AppVariables }>();

app.get("/healthz", (c) => c.json({ ok: true }));
app.on(["POST", "GET"], "/api/auth/**", (c) => getAuth().handler(c.req.raw));

app.use("/api/*", async (c, next) => {
  if (c.req.path.startsWith("/api/auth/")) {
    await next();
    return;
  }
  await sessionMiddleware(c, next);
});

app.get("/api/home", ensureMaterialized);
app.get("/api/entries", ensureMaterialized);
app.get("/api/cards", ensureMaterialized);
app.get("/api/cards/:id/detail", ensureMaterialized);
app.get("/api/recurring-rules", ensureMaterialized);
app.get("/api/calendar", ensureMaterialized);
app.get("/api/tax/estimate", ensureMaterialized);

app.route("/api/me", meRoutes);
app.route("/api/settings", settingsRoutes);
app.route("/api/home", homeRoutes);
app.route("/api/entries", entriesRoutes);
app.route("/api/cards", cardsRoutes);
app.route("/api/recurring-rules", recurringRulesRoutes);
app.route("/api/calendar", calendarRoutes);
app.route("/api/tax", taxRoutes);

app.onError((error, c) => {
  if (error instanceof AppError) {
    return c.json({ error: { code: error.code, message: error.message } }, error.status as 400 | 401 | 403 | 404 | 409 | 500);
  }
  console.error(error);
  return c.json({ error: { code: "INTERNAL", message: "Internal server error" } }, 500);
});

