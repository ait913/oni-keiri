import type { session, user } from "./db/auth-schema.js";

export type AppVariables = {
  user: typeof user.$inferSelect;
  session: typeof session.$inferSelect;
};
