import { createAuth, initAuth } from "@stera/auth";
import { env, corsAllowedOrigins } from "@stera/env/server";
import { Hono } from "hono";
import { cors } from "hono/cors";
import { logger } from "hono/logger";

import { requireAuth } from "./middleware/auth";
import type { AppEnv } from "./middleware/auth";
import { assetsRoute } from "./routes/assets";
import { healthRoute } from "./routes/health";
import { uploadRoute } from "./routes/upload";
import { usersRoute } from "./routes/users";

await initAuth();

const app = new Hono<AppEnv>();

app.use("*", async (c, next) => {
  c.set("requestId", crypto.randomUUID());
  await next();
});

// oxlint-disable-next-line promise/prefer-await-to-callbacks -- Hono's error hook is callback-based
app.onError((error, c) => {
  console.error(`Unhandled error on ${c.req.method} ${c.req.path}:`, error);
  return c.json(
    {
      error: {
        code: "internal",
        message: "Internal server error",
        requestId: c.get("requestId"),
      },
    },
    500
  );
});

app.use(logger());
app.use(
  "/*",
  cors({
    allowHeaders: ["Content-Type", "Authorization"],
    allowMethods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    credentials: true,
    origin: corsAllowedOrigins,
  })
);

app.route("/health", healthRoute);
app.on(["GET", "POST"], "/api/auth/*", (c) => {
  const auth = createAuth();
  return auth.handler(c.req.raw);
});

app.use("/api/v1/*", requireAuth);
app.route("/api/v1/upload", uploadRoute);
app.route("/api/v1/assets", assetsRoute);
app.route("/api/v1/users", usersRoute);

const port = env.PORT;

// Named exports only — a default export would make `bun run dist/index.mjs`
// auto-serve the app *and* hit the Bun.serve below (EADDRINUSE on PORT).
export const { fetch } = app;
export { port };

console.log(`stera-open server listening on http://localhost:${port}`);
Bun.serve({ fetch: app.fetch, port });
