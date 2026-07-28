import { env } from "@stera/env/server";
import { drizzle } from "drizzle-orm/postgres-js";
import postgres from "postgres";

import * as schema from "./schema";

let db: ReturnType<typeof drizzle<typeof schema>> | undefined;

// oxlint-disable-next-line eslint/func-style -- factory required by monorepo contract
export function createDb() {
  if (!db) {
    const client = postgres(env.DATABASE_URL);
    db = drizzle(client, { schema });
  }

  return db;
}

export type Db = ReturnType<typeof createDb>;
