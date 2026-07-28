import { z } from "zod";

// Recorder sessions emit scalars of every JSON type (counts, fps, flags,
// stringified JSON blobs, and nulls for absent fields), so accept all of them.
const metadataValue = z.union([
  z.string().max(8000),
  z.number(),
  z.boolean(),
  z.null(),
]);

export const createAssetBody = z.object({
  storagePath: z.string().min(1),
  originalFilename: z.string().min(1).max(255).optional(),
  mimeType: z.string().min(1).max(100).optional(),
  fileSizeBytes: z.number().int().min(0).max(137_438_953_472).optional(),
  durationSeconds: z.number().int().min(0).optional(),
  thumbnailUrl: z.string().url().startsWith("https://").optional(),
  thumbnail: z.string().min(1).optional(),
  metadata: z
    .record(z.string().max(128), metadataValue)
    .refine((record) => Object.keys(record).length <= 1000, {
      message: "Metadata may contain at most 1000 keys",
    })
    .optional(),
});

export type CreateAssetBody = z.infer<typeof createAssetBody>;
