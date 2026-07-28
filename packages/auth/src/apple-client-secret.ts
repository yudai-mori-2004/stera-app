import { env } from "@stera/env/server";
import { SignJWT, importPKCS8 } from "jose";

const APPLE_AUDIENCE = "https://appleid.apple.com";
const MAX_APPLE_SECRET_TTL_SECONDS = 180 * 24 * 60 * 60;

let cachedSecret: { value: string; expiresAtMs: number } | undefined;

const normalizeApplePrivateKey = (rawKey: string): string =>
  rawKey.includes("\\n") ? rawKey.replaceAll(/\\n/g, "\n") : rawKey;

export const mintAppleClientSecret = async (): Promise<string> => {
  const nowMs = Date.now();

  if (cachedSecret && cachedSecret.expiresAtMs > nowMs + 60_000) {
    return cachedSecret.value;
  }

  const issuedAtSeconds = Math.floor(nowMs / 1000);
  const expiresAtSeconds = issuedAtSeconds + MAX_APPLE_SECRET_TTL_SECONDS;
  const privateKey = await importPKCS8(
    normalizeApplePrivateKey(env.APPLE_PRIVATE_KEY),
    "ES256"
  );

  const secret = await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: env.APPLE_KEY_ID })
    .setIssuer(env.APPLE_TEAM_ID)
    .setAudience(APPLE_AUDIENCE)
    .setSubject(env.APPLE_CLIENT_ID)
    .setIssuedAt(issuedAtSeconds)
    .setExpirationTime(expiresAtSeconds)
    .sign(privateKey);

  cachedSecret = {
    value: secret,
    expiresAtMs: expiresAtSeconds * 1000,
  };

  return secret;
};
