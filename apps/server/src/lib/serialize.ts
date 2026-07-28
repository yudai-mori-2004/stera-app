import type { Asset } from "@stera/db/schema";

export const serializeAsset = (row: Asset) => ({
  createdAt: row.createdAt.toISOString(),
  durationSeconds: row.durationSeconds,
  fileSizeBytes:
    row.fileSizeBytes === null || row.fileSizeBytes === undefined
      ? null
      : row.fileSizeBytes.toString(),
  id: row.id,
  metadata: row.metadata ?? null,
  mimeType: row.mimeType,
  originalFilename: row.originalFilename,
  status: row.status,
  storagePath: row.storagePath,
  thumbnailUrl: row.thumbnail ?? null,
  updatedAt: row.updatedAt.toISOString(),
});
