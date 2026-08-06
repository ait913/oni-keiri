import { migrate } from "drizzle-orm/node-postgres/migrator";
import { getDb, resetDb } from "../../src/db/index.js";

export default async function globalSetup(): Promise<void> {
  await migrate(getDb(), { migrationsFolder: "./drizzle" });
  return async () => {
    await resetDb();
  };
}
