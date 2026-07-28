import path from "node:path";

import { createEnv } from "@t3-oss/env-core";
import dotenv from "dotenv";
import { z } from "zod";

const packageDir = import.meta.dirname;

dotenv.config({
  path: path.resolve(packageDir, "../../../apps/server/.env"),
});

export const parseCommaSeparated = (value: string): string[] =>
  value
    .split(",")
    .map((entry) => entry.trim())
    .filter((entry) => entry.length > 0);

export const env = createEnv({
  emptyStringAsUndefined: true,
  runtimeEnv: process.env,
  skipValidation: !!process.env.SKIP_ENV_VALIDATION,
  server: {
    NODE_ENV: z.enum(["development", "production", "test"]),
    PORT: z.coerce.number().default(3010),
    BETTER_AUTH_URL: z.url(),
    BETTER_AUTH_SECRET: z.string().min(32),
    TRUSTED_ORIGINS: z.string(),
    CORS_ALLOWED_ORIGINS: z.string(),
    DATABASE_URL: z.string().min(1),
    DIRECT_URL: z.string().min(1),
    GOOGLE_CLIENT_ID: z.string().min(1),
    GOOGLE_IOS_CLIENT_ID: z.string().min(1),
    GOOGLE_CLIENT_SECRET: z.string().min(1),
    APPLE_CLIENT_ID: z.string().min(1),
    APPLE_TEAM_ID: z.string().min(1),
    APPLE_KEY_ID: z.string().min(1),
    APPLE_PRIVATE_KEY: z.string().min(1),
    APPLE_APP_BUNDLE_IDENTIFIER: z.string().min(1),
    // Temporary: extra bundle id accepted as an Apple id-token audience while
    // device builds are signed with a borrowed profile. Unset in production.
    APPLE_DEV_BUNDLE_IDENTIFIER: z.string().optional(),
    R2_ACCOUNT_ID: z.string().min(1),
    R2_ENDPOINT: z.url(),
    R2_BUCKET: z.string().min(1),
    R2_ACCESS_KEY_ID: z.string().min(1),
    R2_SECRET_ACCESS_KEY: z.string().min(1),
    UPLOAD_URL_EXPIRY_SECONDS: z.coerce.number().default(86_400),
    DOCS_USERNAME: z.string().optional(),
    DOCS_PASSWORD: z.string().optional(),
    R2_PUBLIC_URL: z.string().url().optional(),
    LOG_LEVEL: z.string().optional(),
    SENTRY_DSN: z.string().optional(),
  },
});

export const trustedOrigins = parseCommaSeparated(env.TRUSTED_ORIGINS);
export const corsAllowedOrigins = parseCommaSeparated(env.CORS_ALLOWED_ORIGINS);
