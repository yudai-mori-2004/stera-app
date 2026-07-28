import { createDb } from "@stera/db";
import * as schema from "@stera/db/schema";
import { env, trustedOrigins } from "@stera/env/server";
import { betterAuth } from "better-auth";
import { drizzleAdapter } from "better-auth/adapters/drizzle";

import { mintAppleClientSecret } from "./apple-client-secret";

type AuthInstance = ReturnType<typeof betterAuth>;

let authInstance: AuthInstance | undefined;
let authInit: Promise<AuthInstance> | undefined;

const createAuthSync = (appleClientSecret: string): AuthInstance => {
  const db = createDb();

  return betterAuth({
    advanced: {
      defaultCookieAttributes: {
        httpOnly: true,
        // Same-origin HTTPS. Always secure so cookies never travel
        // over plain HTTP even when NODE_ENV is mis-set locally.
        sameSite: "lax",
        secure: true,
      },
    },
    baseURL: env.BETTER_AUTH_URL,
    database: drizzleAdapter(db, {
      provider: "pg",
      schema,
    }),
    // Social sign-in only. Credential login is deliberately not enabled:
    // unverified email/password signup lets anyone mint accounts, and an
    // attacker registering an address before its owner's first social sign-in
    // is a pre-registration takeover risk.
    secret: env.BETTER_AUTH_SECRET,
    socialProviders: {
      apple: {
        appBundleIdentifier: env.APPLE_APP_BUNDLE_IDENTIFIER,
        // Native Apple id tokens are audienced to the app's bundle id. Device
        // builds signed with a borrowed profile carry a different one, so it is
        // accepted alongside the real bundle id while that workaround lasts.
        audience: [
          env.APPLE_APP_BUNDLE_IDENTIFIER,
          ...(env.APPLE_DEV_BUNDLE_IDENTIFIER
            ? [env.APPLE_DEV_BUNDLE_IDENTIFIER]
            : []),
        ],
        clientId: env.APPLE_CLIENT_ID,
        clientSecret: appleClientSecret,
      },
      google: {
        // Web + iOS only. Android ID tokens are audienced to the web client
        // (serverClientId); the Android OAuth client is never an audience.
        clientId: [env.GOOGLE_CLIENT_ID, env.GOOGLE_IOS_CLIENT_ID],
        clientSecret: env.GOOGLE_CLIENT_SECRET,
      },
    },
    trustedOrigins,
    user: {
      deleteUser: {
        enabled: true,
      },
    },
  }) as AuthInstance;
};

/** Eager init used by the request path. Safe to call repeatedly. */
// oxlint-disable-next-line eslint/func-style -- factory required by monorepo contract
export function createAuth(): AuthInstance {
  if (authInstance) {
    return authInstance;
  }

  throw new Error(
    "Auth not initialized. Call await initAuth() during process startup."
  );
}

/** Mint the Apple client-secret JWT and memoize the Better Auth instance. */
export const initAuth = (): Promise<AuthInstance> => {
  if (authInstance) {
    return Promise.resolve(authInstance);
  }

  authInit ??= (async () => {
    const appleClientSecret = await mintAppleClientSecret();
    authInstance = createAuthSync(appleClientSecret);
    return authInstance;
  })();

  return authInit;
};

export type Auth = AuthInstance;
