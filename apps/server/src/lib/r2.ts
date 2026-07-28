import {
  AbortMultipartUploadCommand,
  CompleteMultipartUploadCommand,
  CreateMultipartUploadCommand,
  HeadObjectCommand,
  ListPartsCommand,
  PutObjectCommand,
  S3Client,
  UploadPartCommand,
} from "@aws-sdk/client-s3";
import type { ListPartsCommandOutput } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import { env } from "@stera/env/server";

const r2 = new S3Client({
  credentials: {
    accessKeyId: env.R2_ACCESS_KEY_ID,
    secretAccessKey: env.R2_SECRET_ACCESS_KEY,
  },
  endpoint: env.R2_ENDPOINT,
  region: "auto",
  requestChecksumCalculation: "WHEN_REQUIRED",
  responseChecksumValidation: "WHEN_REQUIRED",
});

export const getPresignedUploadUrl = (
  key: string,
  contentType: string
): Promise<string> => {
  const command = new PutObjectCommand({
    Bucket: env.R2_BUCKET,
    ContentType: contentType,
    Key: key,
  });

  return getSignedUrl(r2, command, {
    expiresIn: env.UPLOAD_URL_EXPIRY_SECONDS,
  });
};

export const startMultipartUpload = async (
  key: string,
  contentType: string
): Promise<string> => {
  const command = new CreateMultipartUploadCommand({
    Bucket: env.R2_BUCKET,
    ContentType: contentType,
    Key: key,
  });
  const { UploadId } = await r2.send(command);

  if (!UploadId) {
    throw new Error("Storage provider did not return an upload ID");
  }

  return UploadId;
};

export type PresignedPart = {
  expiresAt: string;
  partNumber: number;
  url: string;
};

export type MultipartPartUrls = {
  expiresInSeconds: number;
  parts: PresignedPart[];
};

export const getMultipartPartUrls = async (
  key: string,
  uploadId: string,
  partNumbers: number[]
): Promise<MultipartPartUrls> => {
  const expiresInSeconds = env.UPLOAD_URL_EXPIRY_SECONDS;
  const expiresAt = new Date(
    Date.now() + expiresInSeconds * 1000
  ).toISOString();

  const parts = await Promise.all(
    partNumbers.map(async (partNumber) => {
      const command = new UploadPartCommand({
        Bucket: env.R2_BUCKET,
        Key: key,
        PartNumber: partNumber,
        UploadId: uploadId,
      });
      const url = await getSignedUrl(r2, command, {
        expiresIn: expiresInSeconds,
      });

      return { expiresAt, partNumber, url };
    })
  );

  return { expiresInSeconds, parts };
};

const isNoSuchUpload = (error: unknown): boolean => {
  const name = (error as { Code?: string; name?: string })?.name;
  const code = (error as { Code?: string })?.Code;

  return name === "NoSuchUpload" || code === "NoSuchUpload";
};

const isNotFound = (error: unknown): boolean => {
  const candidate = error as {
    $metadata?: { httpStatusCode?: number };
    Code?: string;
    name?: string;
  };

  return (
    candidate?.name === "NotFound" ||
    candidate?.name === "NoSuchKey" ||
    candidate?.Code === "NoSuchKey" ||
    candidate?.$metadata?.httpStatusCode === 404
  );
};

export type UploadedPartInfo = {
  etag: string;
  partNumber: number;
  size: number;
};

export const listMultipartParts = async (
  key: string,
  uploadId: string
): Promise<{ parts: UploadedPartInfo[] }> => {
  const parts: UploadedPartInfo[] = [];
  let partNumberMarker: string | undefined;

  for (let page = 0; page < 16; page++) {
    const out: ListPartsCommandOutput = await r2.send(
      new ListPartsCommand({
        Bucket: env.R2_BUCKET,
        Key: key,
        PartNumberMarker: partNumberMarker,
        UploadId: uploadId,
      })
    );

    for (const part of out.Parts ?? []) {
      if (part.PartNumber === null || part.PartNumber === undefined) {
        continue;
      }

      parts.push({
        etag: (part.ETag ?? "").replaceAll(/"/g, ""),
        partNumber: part.PartNumber,
        size: part.Size ?? 0,
      });
    }

    if (!out.IsTruncated) {
      break;
    }

    partNumberMarker = out.NextPartNumberMarker;
  }

  return { parts };
};

export const checkObjectExists = async (
  key: string
): Promise<{ exists: boolean; size?: number }> => {
  try {
    const out = await r2.send(
      new HeadObjectCommand({ Bucket: env.R2_BUCKET, Key: key })
    );

    return { exists: true, size: out.ContentLength };
  } catch (error) {
    if (isNotFound(error)) {
      return { exists: false };
    }

    throw error;
  }
};

export const isNoSuchUploadError = (error: unknown): boolean =>
  isNoSuchUpload(error);

export const completeMultipartUpload = async (
  key: string,
  uploadId: string,
  parts: { ETag: string; PartNumber: number }[]
): Promise<{ alreadyComplete: boolean }> => {
  try {
    await r2.send(
      new CompleteMultipartUploadCommand({
        Bucket: env.R2_BUCKET,
        Key: key,
        MultipartUpload: { Parts: parts },
        UploadId: uploadId,
      })
    );

    return { alreadyComplete: false };
  } catch (error) {
    if (!isNoSuchUpload(error)) {
      throw error;
    }

    const head = await checkObjectExists(key);
    if (head.exists) {
      return { alreadyComplete: true };
    }

    throw error;
  }
};

export const finalizeIfReady = async (
  key: string,
  uploadId: string,
  expectedPartCount: number
): Promise<{ completed: boolean; uploadedParts: number }> => {
  const parts: { ETag: string; PartNumber: number }[] = [];
  let partNumberMarker: string | undefined;

  try {
    for (let page = 0; page < 16; page++) {
      const out: ListPartsCommandOutput = await r2.send(
        new ListPartsCommand({
          Bucket: env.R2_BUCKET,
          Key: key,
          PartNumberMarker: partNumberMarker,
          UploadId: uploadId,
        })
      );

      for (const part of out.Parts ?? []) {
        if (
          part.PartNumber === null ||
          part.PartNumber === undefined ||
          part.ETag === null ||
          part.ETag === undefined
        ) {
          continue;
        }

        parts.push({ ETag: part.ETag, PartNumber: part.PartNumber });
      }

      if (!out.IsTruncated) {
        break;
      }

      partNumberMarker = out.NextPartNumberMarker;
    }
  } catch (error) {
    if (!isNoSuchUpload(error)) {
      throw error;
    }

    const head = await checkObjectExists(key);
    return {
      completed: head.exists,
      uploadedParts: head.exists ? expectedPartCount : 0,
    };
  }

  if (parts.length < expectedPartCount) {
    return { completed: false, uploadedParts: parts.length };
  }

  parts.sort((left, right) => left.PartNumber - right.PartNumber);
  await completeMultipartUpload(key, uploadId, parts);

  return { completed: true, uploadedParts: parts.length };
};

export const abortMultipartUpload = async (
  key: string,
  uploadId: string
): Promise<void> => {
  await r2.send(
    new AbortMultipartUploadCommand({
      Bucket: env.R2_BUCKET,
      Key: key,
      UploadId: uploadId,
    })
  );
};

export const buildStorageKey = (
  userId: string,
  assetId: string,
  filename: string
): string => {
  const sanitized = filename.replaceAll(/[^a-zA-Z0-9._-]/g, "_");
  return `${userId}/${assetId}/${sanitized}`;
};

export const buildThumbnailKey = (userId: string, assetId: string): string =>
  `${userId}/${assetId}/thumbnail.jpg`;
