import { createAuth } from "@stera/auth";
import { createDb } from "@stera/db";
import { createMiddleware } from "hono/factory";

import { apiError } from "../lib/http";

export type AppEnv = {
  Variables: {
    db: ReturnType<typeof createDb>;
    requestId: string;
    userId: string;
  };
};

export const requireAuth = createMiddleware<AppEnv>(async (c, next) => {
  const session = await createAuth().api.getSession({
    headers: c.req.raw.headers,
  });

  if (!session) {
    return apiError(c, 401, "unauthenticated", "Authentication required");
  }

  c.set("userId", session.user.id);
  c.set("db", createDb());

  return next();
});
