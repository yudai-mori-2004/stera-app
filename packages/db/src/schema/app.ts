import { relations, sql } from "drizzle-orm";
import {
  bigint,
  integer,
  jsonb,
  pgTable,
  primaryKey,
  text,
  timestamp,
  unique,
} from "drizzle-orm/pg-core";

import { user } from "./auth";

export const assets = pgTable(
  "assets",
  {
    id: text("id").notNull(),
    userId: text("user_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    storagePath: text("storage_path").notNull(),
    originalFilename: text("original_filename"),
    mimeType: text("mime_type"),
    durationSeconds: integer("duration_seconds"),
    fileSizeBytes: bigint("file_size_bytes", { mode: "bigint" }),
    metadata: jsonb("metadata"),
    thumbnail: text("thumbnail"),
    storageProvider: text("storage_provider").default("r2").notNull(),
    storageBucket: text("storage_bucket"),
    status: text("status").default("pending").notNull(),
    createdAt: timestamp("created_at", { withTimezone: true })
      .default(sql`now()`)
      .notNull(),
    updatedAt: timestamp("updated_at", { withTimezone: true })
      .default(sql`now()`)
      .$onUpdate(() => new Date())
      .notNull(),
  },
  (table) => [
    primaryKey({ columns: [table.userId, table.id] }),
    unique("assets_user_storage_path").on(table.userId, table.storagePath),
  ]
);

export const uploadSessions = pgTable(
  "upload_sessions",
  {
    id: text("id").primaryKey(),
    userId: text("user_id")
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    clientUploadId: text("client_upload_id").notNull(),
    uploadId: text("upload_id").notNull(),
    storageKey: text("storage_key").notNull(),
    assetId: text("asset_id").notNull(),
    contentType: text("content_type").notNull(),
    createdAt: timestamp("created_at", { withTimezone: true })
      .default(sql`now()`)
      .notNull(),
    updatedAt: timestamp("updated_at", { withTimezone: true })
      .default(sql`now()`)
      .$onUpdate(() => new Date())
      .notNull(),
  },
  (table) => [
    unique("upload_sessions_user_client_upload_id").on(
      table.userId,
      table.clientUploadId
    ),
  ]
);

export const assetsRelations = relations(assets, ({ one }) => ({
  user: one(user, {
    fields: [assets.userId],
    references: [user.id],
  }),
}));

export const uploadSessionsRelations = relations(uploadSessions, ({ one }) => ({
  user: one(user, {
    fields: [uploadSessions.userId],
    references: [user.id],
  }),
}));

export type Asset = typeof assets.$inferSelect;
export type UploadSession = typeof uploadSessions.$inferSelect;
