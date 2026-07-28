import { z } from "zod";

export const contentTypeSchema = z
  .string()
  .min(1)
  .max(100)
  .regex(
    /^[a-zA-Z0-9][a-zA-Z0-9!#$&\-^_]*\/[a-zA-Z0-9][a-zA-Z0-9!#$&\-^_.+]*$/
  );

export const filenameSchema = z.string().min(1).max(255);

export const uploadPresignBody = z.object({
  filename: filenameSchema,
  contentType: contentTypeSchema,
});

export const multipartStartBody = z.object({
  filename: filenameSchema,
  contentType: contentTypeSchema,
  clientUploadId: z.string().min(1).max(200).optional(),
});

export const multipartPartsBody = z
  .object({
    key: z.string().min(1),
    uploadId: z.string().min(1),
    partCount: z.number().int().min(1).max(10_000).optional(),
    partNumbers: z
      .array(z.number().int().min(1).max(10_000))
      .min(1)
      .max(10_000)
      .optional(),
  })
  .refine(
    (body) =>
      (body.partNumbers !== undefined && body.partNumbers.length > 0) ||
      (body.partCount !== undefined && body.partCount > 0),
    { message: "Provide either partCount or a non-empty partNumbers array" }
  );

export const multipartListPartsBody = z.object({
  key: z.string().min(1),
  uploadId: z.string().min(1),
});

export const multipartCompletePartSchema = z.object({
  ETag: z.string().min(1),
  PartNumber: z.number().int().min(1).max(10_000),
});

export const multipartCompleteBody = z.object({
  key: z.string().min(1),
  uploadId: z.string().min(1),
  parts: z.array(multipartCompletePartSchema).min(1).max(10_000),
});

export const multipartFinalizeBody = z.object({
  key: z.string().min(1),
  uploadId: z.string().min(1),
  partCount: z.number().int().min(1).max(10_000),
});

export const multipartAbortBody = z.object({
  key: z.string().min(1),
  uploadId: z.string().min(1),
});

export type UploadPresignBody = z.infer<typeof uploadPresignBody>;
export type MultipartStartBody = z.infer<typeof multipartStartBody>;
export type MultipartPartsBody = z.infer<typeof multipartPartsBody>;
export type MultipartListPartsBody = z.infer<typeof multipartListPartsBody>;
export type MultipartCompleteBody = z.infer<typeof multipartCompleteBody>;
export type MultipartFinalizeBody = z.infer<typeof multipartFinalizeBody>;
export type MultipartAbortBody = z.infer<typeof multipartAbortBody>;
