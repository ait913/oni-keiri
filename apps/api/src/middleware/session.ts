import { and, eq } from "drizzle-orm";
import type { MiddlewareHandler } from "hono";
import { getAuth } from "../auth.js";
import { getDb } from "../db/index.js";
import { session, user } from "../db/auth-schema.js";
import { AppError } from "../lib/appError.js";
import type { AppVariables } from "../types.js";

function readCookie(headers: Headers, name: string): string | null {
  const cookie = headers.get("Cookie");
  if (!cookie) return null;
  const match = cookie.split(";").map((part) => part.trim()).find((part) => part.startsWith(`${name}=`));
  if (!match) return null;
  return decodeURIComponent(match.slice(name.length + 1));
}

function readBearerToken(headers: Headers): string | null {
  const authorization = headers.get("Authorization");
  if (!authorization || authorization.slice(0, 7).toLowerCase() !== "bearer ") return null;
  const token = authorization.slice(7).trim();
  if (!token) return null;
  try {
    return decodeURIComponent(token);
  } catch {
    return token;
  }
}

export const sessionMiddleware: MiddlewareHandler<{ Variables: AppVariables }> = async (c, next) => {
  const auth = getAuth();
  const authSession = await auth.api.getSession({ headers: c.req.raw.headers });
  if (authSession?.user && authSession.session) {
    c.set("user", authSession.user as typeof user.$inferSelect);
    c.set("session", authSession.session as typeof session.$inferSelect);
    await next();
    return;
  }

  const token = readBearerToken(c.req.raw.headers) ?? readCookie(c.req.raw.headers, "better-auth.session_token");
  if (!token) throw new AppError(401, "UNAUTHORIZED", "Unauthorized");

  const db = getDb();
  const rows = await db
    .select({ session, user })
    .from(session)
    .innerJoin(user, eq(session.userId, user.id))
    .where(and(eq(session.token, token)))
    .limit(1);
  const row = rows[0];

  if (!row || row.session.expiresAt < new Date()) {
    if (row) await db.delete(session).where(eq(session.id, row.session.id));
    throw new AppError(401, "UNAUTHORIZED", "Unauthorized");
  }

  c.set("user", row.user);
  c.set("session", row.session);
  await next();
};
