import { drizzle, type NodePgDatabase } from "drizzle-orm/node-postgres";
import pg from "pg";
import * as authSchema from "./auth-schema.js";
import * as businessSchema from "./schema.js";
import { getEnv } from "../env.js";

const schema = { ...authSchema, ...businessSchema };

export type Db = NodePgDatabase<typeof schema>;

let pool: pg.Pool | null = null;
let db: Db | null = null;

export function getDb(): Db {
  if (!db) {
    pool = new pg.Pool({ connectionString: getEnv().DATABASE_URL });
    db = drizzle(pool, { schema });
  }
  return db;
}

export async function resetDb(): Promise<void> {
  const currentPool = pool;
  pool = null;
  db = null;
  await currentPool?.end();
}
