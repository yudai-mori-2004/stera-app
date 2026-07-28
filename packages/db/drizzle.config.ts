import dotenv from "dotenv";
import { defineConfig } from "drizzle-kit";

dotenv.config({
  path: "../../apps/server/.env",
});

const directUrl = process.env.DIRECT_URL;

if (!directUrl) {
  throw new Error(
    "DIRECT_URL is required. Set it in apps/server/.env (session pooler :5432)."
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
