import { createPrivateKey, sign as cryptoSign } from "node:crypto";
import { betterAuth } from "better-auth";
import { drizzleAdapter } from "better-auth/adapters/drizzle";
import { bearer } from "better-auth/plugins/bearer";
import { getDb } from "./db/index.js";
import * as authSchema from "./db/auth-schema.js";
import { getEnv } from "./env.js";

type Auth = ReturnType<typeof betterAuth>;

export function normalizeApplePem(raw: string): string {
  const s = raw.trim();
  if (s.includes("BEGIN")) {
    return s.includes("\\n") ? s.replace(/\\n/g, "\n") : s;
  }
  return Buffer.from(s, "base64").toString("utf8");
}

export function buildAppleClientSecret(
  input: { teamId: string; keyId: string; privateKeyPem: string; clientId: string },
  now: Date = new Date(),
): string {
  const iat = Math.floor(now.getTime() / 1000);
  const exp = iat + 60 * 60 * 24 * 180;
  const b64url = (buffer: Buffer) => buffer.toString("base64url");
  const header = b64url(Buffer.from(JSON.stringify({ alg: "ES256", kid: input.keyId, typ: "JWT" })));
  const payload = b64url(Buffer.from(JSON.stringify({
    iss: input.teamId,
    iat,
    exp,
    aud: "https://appleid.apple.com",
    sub: input.clientId,
  })));
  const signingInput = `${header}.${payload}`;
  const key = createPrivateKey(normalizeApplePem(input.privateKeyPem));
  const signature = cryptoSign("sha256", Buffer.from(signingInput), { key, dsaEncoding: "ieee-p1363" });
  return `${signingInput}.${b64url(signature)}`;
}

function getAppleProviderConfig() {
  const env = getEnv();
  const clientId = env.APPLE_CLIENT_ID;
  const appBundleIdentifier = env.APPLE_APP_BUNDLE_ID ?? "net.appily.onikeiri";
  if (!clientId) return null;

  const clientSecret = env.APPLE_TEAM_ID && env.APPLE_KEY_ID && env.APPLE_PRIVATE_KEY
    ? buildAppleClientSecret({
        teamId: env.APPLE_TEAM_ID,
        keyId: env.APPLE_KEY_ID,
        privateKeyPem: env.APPLE_PRIVATE_KEY,
        clientId,
      })
    : null;
  if (!clientSecret) return null;

  return { clientId, clientSecret, appBundleIdentifier };
}

let authInstance: Auth | null = null;

export function resetAuth(): void {
  authInstance = null;
}

export function getAuth(): Auth {
  if (!authInstance) {
    const env = getEnv();
    const appleProviderConfig = getAppleProviderConfig();
    const created = betterAuth({
      database: drizzleAdapter(getDb(), { provider: "pg", schema: authSchema }),
      secret: env.BETTER_AUTH_SECRET,
      baseURL: env.BETTER_AUTH_URL,
      socialProviders: {
        ...(appleProviderConfig ? { apple: appleProviderConfig } : {}),
      },
      plugins: [bearer()],
      session: {
        expiresIn: 60 * 60 * 24 * 30,
        updateAge: 60 * 60 * 24,
      },
      advanced: {
        defaultCookieAttributes: {
          sameSite: "lax",
          secure: true,
          httpOnly: true,
        },
      },
      trustedOrigins: env.BETTER_AUTH_URL ? [env.BETTER_AUTH_URL] : [],
    });
    authInstance = created as unknown as Auth;
  }

  return authInstance;
}

export const auth = new Proxy({} as Auth, {
  get(_target, property, receiver) {
    return Reflect.get(getAuth(), property, receiver);
  },
  set(_target, property, value, receiver) {
    return Reflect.set(getAuth(), property, value, receiver);
  },
}) as Auth;
