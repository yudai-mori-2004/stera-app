import { createAuth } from "@stera/auth";
import { createDb } from "@stera/db";
import { eq } from "@stera/db/orm";
import { user } from "@stera/db/schema";
import { Hono } from "hono";

import { apiError } from "../lib/http";
import type { AppEnv } from "../middleware/auth";

export const usersRoute = new Hono<AppEnv>();

usersRoute.get("/me", async (c) => {
  const auth = createAuth();
  const session = await auth.api.getSession({
    headers: c.req.raw.headers,
  });

  if (!session) {
    return apiError(c, 401, "unauthenticated", "Authentication required");
  }

  return c.json({
    data: {
      avatarUrl: session.user.image ?? null,
      createdAt: session.user.createdAt.toISOString(),
      email: session.user.email,
      fullName: session.user.name,
      id: session.user.id,
    },
  });
});

usersRoute.delete("/me", async (c) => {
  const userId = c.get("userId");
  const db = createDb();

  // Social-only accounts have no password, so Better Auth's deleteUser flow
  // (which may require one) is bypassed. Cascades wipe sessions, accounts,
  // assets, and upload_sessions via FK onDelete.
  await db.delete(user).where(eq(user.id, userId));

  return c.body(null, 204);
});
