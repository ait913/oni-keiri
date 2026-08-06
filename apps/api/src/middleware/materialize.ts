import type { MiddlewareHandler } from "hono";
import { getDb } from "../db/index.js";
import { ensureMaterializedForUser } from "../lib/materialize.js";
import type { AppVariables } from "../types.js";

export const ensureMaterialized: MiddlewareHandler<{ Variables: AppVariables }> = async (c, next) => {
  await ensureMaterializedForUser(getDb(), c.get("user").id);
  await next();
};
