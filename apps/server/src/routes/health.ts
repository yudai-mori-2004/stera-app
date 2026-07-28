import { Hono } from "hono";

import packageJson from "../../package.json" with { type: "json" };

export const healthRoute = new Hono();

healthRoute.get("/", (c) =>
  c.json({
    ok: true,
    version: packageJson.version,
  }),
);
