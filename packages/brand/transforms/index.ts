/**
 * The transform registry, in execution order.
 *
 * Order is the contract. Directory moves must precede the content rewrites that
 * reference the new paths; lockfile regeneration must come after everything
 * that touches a manifest; state is written last so a crash leaves the ledger
 * pointing at the brand that is actually on disk.
 */

import { assets } from "./assets.ts";
import { envDeploy, finish, lockfiles } from "./deploy.ts";
import { mcapCompat } from "./mcap.ts";
import { backup, preflight } from "./preflight.ts";
import { movePaths, rewriteContent } from "./rename.ts";
import { attribution, copy, theme } from "./seams.ts";
import type { Transform } from "../lib/types.ts";

export const REGISTRY: readonly Transform[] = [
  preflight,
  backup,
  movePaths,
  rewriteContent,
  mcapCompat,
  theme,
  copy,
  assets,
  attribution,
  envDeploy,
  lockfiles,
  finish,
];

export const transformIds = (): string[] => REGISTRY.map((t) => t.id);
