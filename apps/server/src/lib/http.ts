import type { Context } from "hono";
import type { ContentfulStatusCode } from "hono/utils/http-status";
import type { ZodError, ZodType } from "zod";

export type ErrorCode =
  | "validation"
  | "unauthenticated"
  | "forbidden"
  | "not_found"
  | "conflict"
  | "internal"
  | "bad_request";

export const getRequestId = (c: Context): string =>
  c.get("requestId") ?? crypto.randomUUID();

export const apiError = (
  c: Context,
  status: ContentfulStatusCode,
  code: ErrorCode,
  message: string
) =>
  c.json(
    {
      error: {
        code,
        message,
        requestId: getRequestId(c),
      },
    },
    status
  );

const formatZodError = (error: ZodError): string => {
  const [issue] = error.issues;
  if (!issue) {
    return "Invalid request body";
  }

  const path = issue.path.join(".");
  return path ? `${path}: ${issue.message}` : issue.message;
};

export const parseBody = async <T>(
  c: Context,
  schema: ZodType<T>
): Promise<{ data: T; error: null } | { data: null; error: Response }> => {
  let raw: unknown;

  try {
    raw = await c.req.json();
  } catch {
    return {
      data: null,
      error: apiError(c, 400, "validation", "Request body must be valid JSON"),
    };
  }

  const parsed = schema.safeParse(raw);
  if (!parsed.success) {
    return {
      data: null,
      error: apiError(c, 400, "validation", formatZodError(parsed.error)),
    };
  }

  return { data: parsed.data, error: null };
};

export const firstRow = <T>(rows: T[]): T => {
  const [row] = rows;
  if (!row) {
    throw new Error("Query expected to return at least one row");
  }

  return row;
};

export const assertOwnerKey = (
  c: Context,
  userId: string,
  key: string
): Response | null => {
  if (!key.startsWith(`${userId}/`) || key.includes("..")) {
    return apiError(c, 403, "forbidden", "Key does not belong to this account");
  }

  return null;
};

export const assertOwnerStoragePath = (
  c: Context,
  userId: string,
  storagePath: string
): Response | null => {
  if (!storagePath.startsWith(`${userId}/`) || storagePath.includes("..")) {
    return apiError(
      c,
      400,
      "bad_request",
      "Storage path does not belong to this account"
    );
  }

  return null;
};

export const extractAssetIdFromStoragePath = (
  storagePath: string
): string | null => {
  const [, assetId] = storagePath.split("/");
  return assetId && assetId.length > 0 ? assetId : null;
};
