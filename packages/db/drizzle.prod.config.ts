import dotenv from "dotenv";
import { defineConfig } from "drizzle-kit";

// Prod session-pooler URL for Drizzle Studio / migrations against the
// documented-but-unexecuted prod project. Copy apps/server/.env.prod.example
// → apps/server/.env.prod and fill DIRECT_URL (session pooler :5432).
dotenv.config({
  path: "../../apps/server/.env.prod",
});

const directUrl = process.env.DIRECT_URL;

if (!directUrl) {
  throw new Error(
    "DIRECT_URL is required. Copy apps/server/.env.prod.example to apps/server/.env.prod and set DIRECT_URL (session pooler :5432).",
  );
}

export default defineConfig({
  schema: "./src/schema",
  out: "./src/migrations",
  dialect: "postgresql",
  dbCredentials: {
    url: directUrl,
  },
});
