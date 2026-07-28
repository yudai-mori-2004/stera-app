import { createHash, randomUUID } from "node:crypto";

import { and, eq } from "@stera/db/orm";
import { uploadSessions } from "@stera/db/schema";
import {
  multipartAbortBody,
  multipartCompleteBody,
  multipartFinalizeBody,
  multipartListPartsBody,
  multipartPartsBody,
  multipartStartBody,
  uploadPresignBody,
} from "@stera/types";
import { Hono } from "hono";

import { apiError, assertOwnerKey, parseBody } from "../lib/http";
import {
  abortMultipartUpload,
  buildStorageKey,
  buildThumbnailKey,
  checkObjectExists,
  completeMultipartUpload,
  finalizeIfReady,
  getMultipartPartUrls,
  getPresignedUploadUrl,
  isNoSuchUploadError,
  listMultipartParts,
  startMultipartUpload,
} from "../lib/r2";
import type { AppEnv } from "../middleware/auth";

const UPLOAD_CAPABILITIES = [
  "presign-batch",
  "presign-expiry",
  "list-parts",
  "complete-idempotent",
  "start-idempotent",
  "server-finalize",
  "thumbnail-presign",
] as const;

const UUID_PATTERN =
  "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$";
const UUID_RE = new RegExp(UUID_PATTERN);
const CLIENT_UPLOAD_ID_NAMESPACE = "6f0c8d6e-1b2a-4c3d-8e4f-9a0b1c2d3e4f";
const IDEMPOTENCY_FRESHNESS_MS = 7 * 24 * 60 * 60 * 1000;

const normalizeClientUploadId = (raw: string): string => {
  if (UUID_RE.test(raw)) {
    return raw.toLowerCase();
  }

  const namespace = Buffer.from(
    CLIENT_UPLOAD_ID_NAMESPACE.replaceAll(/-/g, ""),
    "hex"
  );
  const hash = createHash("sha1")
    .update(namespace)
    .update(Buffer.from(raw, "utf-8"))
    .digest();
  const bytes = hash.subarray(0, 16);
  if (bytes.length < 16) {
    throw new Error("Unexpected hash length for client upload id");
  }
  const byte6 = bytes.at(6);
  const byte8 = bytes.at(8);
  if (byte6 === undefined || byte8 === undefined) {
    throw new Error("Unexpected hash length for client upload id");
  }
  bytes[6] = (byte6 & 0x0f) | 0x50;
  bytes[8] = (byte8 & 0x3f) | 0x80;
  const hex = bytes.toString("hex");

  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
};

export const uploadRoute = new Hono<AppEnv>();

uploadRoute.post("/presign", async (c) => {
  const parsed = await parseBody(c, uploadPresignBody);
  if (parsed.error) {
    return parsed.error;
  }

  const userId = c.get("userId");
  const { contentType, filename } = parsed.data;
  const assetId = randomUUID();
  const key = buildStorageKey(userId, assetId, filename);
  const uploadUrl = await getPresignedUploadUrl(key, contentType);

  return c.json({ data: { assetId, key, uploadUrl } });
});

uploadRoute.post("/multipart/start", async (c) => {
  const parsed = await parseBody(c, multipartStartBody);
  if (parsed.error) {
    return parsed.error;
  }

  const db = c.get("db");
  const userId = c.get("userId");
  const {
    clientUploadId: rawClientUploadId,
    contentType,
    filename,
  } = parsed.data;
  const clientUploadId = rawClientUploadId
    ? normalizeClientUploadId(rawClientUploadId)
    : undefined;

  if (clientUploadId) {
    try {
      const existingRows = await db
        .select()
        .from(uploadSessions)
        .where(
          and(
            eq(uploadSessions.userId, userId),
            eq(uploadSessions.clientUploadId, clientUploadId)
          )
        )
        .limit(1);
      const [existing] = existingRows;

      if (
        existing &&
        Date.now() - existing.updatedAt.getTime() < IDEMPOTENCY_FRESHNESS_MS
      ) {
        let stillAlive = true;

        try {
          await listMultipartParts(existing.storageKey, existing.uploadId);
        } catch (error) {
          if (isNoSuchUploadError(error)) {
            stillAlive = false;
          } else {
            throw error;
          }
        }

        if (stillAlive) {
          return c.json({
            data: {
              assetId: existing.assetId,
              capabilities: UPLOAD_CAPABILITIES,
              idempotentReplay: true,
              key: existing.storageKey,
              thumbnailPutUrl: await getPresignedUploadUrl(
                buildThumbnailKey(userId, existing.assetId),
                "image/jpeg"
              ),
              uploadId: existing.uploadId,
            },
          });
        }
      }
    } catch {
      // Degrade to a fresh start when the idempotency table is unavailable.
    }
  }

  const assetId = randomUUID();
  const key = buildStorageKey(userId, assetId, filename);
  const uploadId = await startMultipartUpload(key, contentType);

  if (clientUploadId) {
    try {
      await db
        .insert(uploadSessions)
        .values({
          assetId,
          clientUploadId,
          contentType,
          id: randomUUID(),
          storageKey: key,
          uploadId,
          userId,
        })
        .onConflictDoUpdate({
          set: {
            assetId,
            contentType,
            storageKey: key,
            updatedAt: new Date(),
            uploadId,
          },
          target: [uploadSessions.userId, uploadSessions.clientUploadId],
        });
    } catch {
      // Replay disabled for this upload when persistence fails.
    }
  }

  return c.json({
    data: {
      assetId,
      capabilities: UPLOAD_CAPABILITIES,
      key,
      thumbnailPutUrl: await getPresignedUploadUrl(
        buildThumbnailKey(userId, assetId),
        "image/jpeg"
      ),
      uploadId,
    },
  });
});

uploadRoute.post("/multipart/parts", async (c) => {
  const parsed = await parseBody(c, multipartPartsBody);
  if (parsed.error) {
    return parsed.error;
  }

  const userId = c.get("userId");
  const { key, partCount, partNumbers, uploadId } = parsed.data;
  const ownerError = assertOwnerKey(c, userId, key);
  if (ownerError) {
    return ownerError;
  }

  let requestedParts: number[] | null = null;
  if (partNumbers && partNumbers.length > 0) {
    requestedParts = partNumbers;
  } else if (partCount) {
    requestedParts = Array.from({ length: partCount }, (_, index) => index + 1);
  }

  if (!requestedParts) {
    return apiError(
      c,
      400,
      "bad_request",
      "Provide either partCount or a non-empty partNumbers array"
    );
  }

  const { expiresInSeconds, parts } = await getMultipartPartUrls(
    key,
    uploadId,
    requestedParts
  );

  return c.json({
    data: {
      expiresAt: parts[0]?.expiresAt ?? null,
      expiresInSeconds,
      parts,
      urls: parts.map((part) => part.url),
    },
  });
});

uploadRoute.post("/multipart/list-parts", async (c) => {
  const parsed = await parseBody(c, multipartListPartsBody);
  if (parsed.error) {
    return parsed.error;
  }

  const userId = c.get("userId");
  const { key, uploadId } = parsed.data;
  const ownerError = assertOwnerKey(c, userId, key);
  if (ownerError) {
    return ownerError;
  }

  try {
    const { parts } = await listMultipartParts(key, uploadId);
    return c.json({ data: { parts, uploadExists: true } });
  } catch (error) {
    if (!isNoSuchUploadError(error)) {
      throw error;
    }

    const object = await checkObjectExists(key);
    return c.json({
      data: {
        objectExists: object.exists,
        parts: [],
        uploadExists: false,
      },
    });
  }
});

uploadRoute.post("/multipart/complete", async (c) => {
  const parsed = await parseBody(c, multipartCompleteBody);
  if (parsed.error) {
    return parsed.error;
  }

  const userId = c.get("userId");
  const { key, parts, uploadId } = parsed.data;
  const ownerError = assertOwnerKey(c, userId, key);
  if (ownerError) {
    return ownerError;
  }

  try {
    const { alreadyComplete } = await completeMultipartUpload(
      key,
      uploadId,
      parts
    );
    return c.json({ data: { alreadyComplete, message: "Upload complete" } });
  } catch (error) {
    if (isNoSuchUploadError(error)) {
      return apiError(
        c,
        409,
        "conflict",
        "Multipart upload no longer exists; restart the upload"
      );
    }

    throw error;
  }
});

uploadRoute.post("/multipart/finalize", async (c) => {
  const parsed = await parseBody(c, multipartFinalizeBody);
  if (parsed.error) {
    return parsed.error;
  }

  const userId = c.get("userId");
  const { key, partCount, uploadId } = parsed.data;
  const ownerError = assertOwnerKey(c, userId, key);
  if (ownerError) {
    return ownerError;
  }

  const result = await finalizeIfReady(key, uploadId, partCount);
  return c.json({ data: result });
});

uploadRoute.post("/multipart/abort", async (c) => {
  const parsed = await parseBody(c, multipartAbortBody);
  if (parsed.error) {
    return parsed.error;
  }

  const userId = c.get("userId");
  const { key, uploadId } = parsed.data;
  const ownerError = assertOwnerKey(c, userId, key);
  if (ownerError) {
    return ownerError;
  }

  await abortMultipartUpload(key, uploadId);
  return c.json({ data: { message: "Upload aborted" } });
});
