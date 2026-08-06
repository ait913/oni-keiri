import { serve } from "@hono/node-server";
import { migrate } from "drizzle-orm/node-postgres/migrator";
import { app } from "./app.js";
import { getDb } from "./db/index.js";
import { getEnv } from "./env.js";

await migrate(getDb(), { migrationsFolder: "./drizzle" });

const { PORT } = getEnv();

serve({
  fetch: app.fetch,
  port: PORT,
  hostname: "::",
});

console.log(`oni-keiri api listening on [::]:${PORT}`);
