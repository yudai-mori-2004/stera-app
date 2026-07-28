/**
 * The state ledger: `packages/brand/.applied.json`.
 *
 * This is what makes the engine re-runnable. After run 1 the string "stera" no
 * longer exists anywhere, so a grep-replace has nothing left to find. Recording
 * the brand that is *currently applied* turns every subsequent run into the
 * same operation as the first: rename `prev` to `next`.
 *
 * It also records a content hash per generated file, so run N can tell the
 * difference between "this file is as I left it" and "a human edited this and
 * is about to lose their work".
 */

import { join } from "node:path";

import type { Brand } from "./types.ts";

export const STATE_PATH = "packages/brand/.applied.json";

export interface AppliedState {
  engineVersion: number;
  /** The brand currently applied to the tree. Becomes `prev` on the next run. */
  brand: Brand;
  /** ISO timestamp, supplied by the caller (the engine never reads the clock). */
  appliedAt: string;
  /** HEAD at the time of the run, for `git diff` orientation after the fact. */
  gitCommit: string;
  /** Transform id -> outcome. */
  transforms: Record<string, "ok" | "skipped" | "no-op">;
  /** Repo-relative path -> sha256 of the contents this engine last wrote. */
  generatedHashes: Record<string, string>;
}

export const readState = async (root: string): Promise<AppliedState | null> => {
  const file = Bun.file(join(root, STATE_PATH));
  if (!(await file.exists())) {
    return null;
  }
  try {
    return (await file.json()) as AppliedState;
  } catch (cause) {
    throw new Error(
      `${STATE_PATH} is present but not valid JSON. Fix or delete it before re-running. (${
        cause instanceof Error ? cause.message : String(cause)
      })`
    );
  }
};

export const writeState = async (
  root: string,
  state: AppliedState
): Promise<void> => {
  await Bun.write(join(root, STATE_PATH), `${JSON.stringify(state, null, 2)}\n`);
};

export const hashContents = (contents: string | Uint8Array): string => {
  const hasher = new Bun.CryptoHasher("sha256");
  hasher.update(contents);
  return hasher.digest("hex");
};

/**
 * Generated files whose on-disk hash no longer matches what the engine last
 * wrote - i.e. someone hand-edited a `DO NOT EDIT` file. Re-running would
 * silently revert them, so the caller warns first.
 */
export const findHandEdited = async (
  root: string,
  state: AppliedState | null
): Promise<string[]> => {
  if (state === null) {
    return [];
  }
  const edited: string[] = [];
  for (const [path, expected] of Object.entries(state.generatedHashes)) {
    const file = Bun.file(join(root, path));
    if (!(await file.exists())) {
      edited.push(path);
      continue;
    }
    if (hashContents(await file.text()) !== expected) {
      edited.push(path);
    }
  }
  return edited;
};
