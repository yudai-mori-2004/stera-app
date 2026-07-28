import { and, desc, eq, lt } from "@stera/db/orm";
import { assets } from "@stera/db/schema";
import { env } from "@stera/env/server";
import { createAssetBody } from "@stera/types";
import { Hono } from "hono";
import { z } from "zod";

import {
  assertOwnerStoragePath,
  extractAssetIdFromStoragePath,
  parseBody,
} from "../lib/http";
import { serializeAsset } from "../lib/serialize";
import type { AppEnv } from "../middleware/auth";

const listAssetsQuery = z.object({
  cursor: z.string().optional(),
  limit: z.coerce.number().int().min(1).max(100).default(20),
});

export const assetsRoute = new Hono<AppEnv>();

assetsRoute.post("/", async (c) => {
  const parsed = await parseBody(c, createAssetBody);
  if (parsed.error) {
    return parsed.error;
  }

  const db = c.get("db");
  const userId = c.get("userId");
  const body = parsed.data;
  const ownerError = assertOwnerStoragePath(c, userId, body.storagePath);
  if (ownerError) {
    return ownerError;
  }

  const assetId = extractAssetIdFromStoragePath(body.storagePath);
  if (!assetId) {
    return c.json(
      {
        error: {
          code: "bad_request",
          message: "Storage path must include an asset id segment",
        },
      },
      400
    );
  }

  const existingRows = await db
    .select()
    .from(assets)
    .where(
      and(eq(assets.userId, userId), eq(assets.storagePath, body.storagePath))
    )
    .limit(1);
  const [existing] = existingRows;

  if (existing) {
    return c.json({ data: serializeAsset(existing) });
  }

  const resolvedThumbnail = body.thumbnailUrl ?? body.thumbnail ?? null;

  const [created] = await db
    .insert(assets)
    .values({
      durationSeconds: body.durationSeconds ?? null,
      fileSizeBytes:
        body.fileSizeBytes === null || body.fileSizeBytes === undefined
          ? null
          : BigInt(body.fileSizeBytes),
      id: assetId,
      metadata: body.metadata ?? null,
      mimeType: body.mimeType ?? null,
      originalFilename: body.originalFilename ?? null,
      status: "pending",
      storageBucket: env.R2_BUCKET,
      storagePath: body.storagePath,
      storageProvider: "r2",
      thumbnail: resolvedThumbnail,
      userId,
    })
    .returning();

  if (!created) {
    throw new Error("Failed to create asset");
  }

  return c.json({ data: serializeAsset(created) }, 201);
});

assetsRoute.get("/", async (c) => {
  const db = c.get("db");
  const userId = c.get("userId");
  const query = listAssetsQuery.parse({
    cursor: c.req.query("cursor"),
    limit: c.req.query("limit"),
  });

  if (query.cursor) {
    const cursorDate = new Date(query.cursor);
    if (Number.isNaN(cursorDate.getTime())) {
      return c.json(
        {
          error: {
            code: "bad_request",
            message: "Cursor must be a valid ISO 8601 timestamp",
          },
        },
        400
      );
    }
  }

  const rows = await db
    .select()
    .from(assets)
    .where(
      query.cursor
        ? and(
            eq(assets.userId, userId),
            lt(assets.createdAt, new Date(query.cursor))
          )
        : eq(assets.userId, userId)
    )
    .orderBy(desc(assets.createdAt))
    .limit(query.limit + 1);

  const hasMore = rows.length > query.limit;
  const items = hasMore ? rows.slice(0, query.limit) : rows;
  const nextCursor = hasMore
    ? (rows[query.limit]?.createdAt.toISOString() ?? null)
    : null;

  return c.json({
    data: items.map(serializeAsset),
    pagination: { hasMore, nextCursor },
  });
});

assetsRoute.get("/:id", async (c) => {
  const db = c.get("db");
  const userId = c.get("userId");
  const assetId = c.req.param("id");

  const rows = await db
    .select()
    .from(assets)
    .where(and(eq(assets.userId, userId), eq(assets.id, assetId)))
    .limit(1);
  const [asset] = rows;

  if (!asset) {
    return c.json(
      {
        error: {
          code: "not_found",
          message: "Asset not found",
        },
      },
      404
    );
  }

  return c.json({ data: serializeAsset(asset) });
});
