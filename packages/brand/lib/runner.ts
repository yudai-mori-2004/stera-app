/**
 * Executes a transform registry.
 *
 * The contract that makes this safe: **transforms only read.** Each one returns
 * a `Change[]` describing what it wants done. The runner collects the whole
 * plan, checks it for conflicts, and only then touches the disk. Three things
 * fall out of that:
 *
 * - `--dry-run` is not a special code path, it is just "stop before commit".
 * - Two transforms fighting over one file is a hard error at plan time instead
 *   of a silent last-writer-wins that you discover three commits later.
 * - Each transform is a pure function you can unit-test against a fixture tree.
 *
 * Changes are applied in collection order, which is what lets a transform move
 * a directory and then write rewritten contents to the new paths.
 */

import { dirname, join, relative } from "node:path";
import { mkdir, readdir, rename, rm, rmdir, stat } from "node:fs/promises";

import type { Change, Ctx, Logger, Transform } from "./types.ts";

export class TransformError extends Error {
  readonly transformId: string;
  /**
   * Which half of the run failed. A "plan" failure happened before anything
   * touched the disk, so the tree is untouched; a "commit" failure means the
   * rebrand is half-applied. The two need very different advice.
   */
  readonly phase: "plan" | "commit";

  constructor(transformId: string, cause: unknown, phase: "plan" | "commit") {
    const detail = cause instanceof Error ? cause.message : String(cause);
    super(`transform ${transformId} failed: ${detail}`);
    this.name = "TransformError";
    this.transformId = transformId;
    this.phase = phase;
    if (cause instanceof Error) {
      this.stack = cause.stack;
    }
  }
}

export class PlanConflictError extends Error {
  constructor(conflicts: readonly string[]) {
    super(`plan has ${conflicts.length} conflict(s):\n  ${conflicts.join("\n  ")}`);
    this.name = "PlanConflictError";
  }
}

export interface PlannedChange {
  transformId: string;
  change: Change;
}

export interface RunResult {
  planned: PlannedChange[];
  /** Transform id -> outcome, recorded into `.applied.json`. */
  outcomes: Map<string, "ok" | "skipped" | "no-op">;
  committed: boolean;
}

// ---------------------------------------------------------------------------
// Logging
// ---------------------------------------------------------------------------

const DIM = "\u001B[2m";
const RED = "\u001B[31m";
const YELLOW = "\u001B[33m";
const GREEN = "\u001B[32m";
const RESET = "\u001B[0m";

export const createLogger = (verbose = false): Logger => ({
  info: (message) => console.log(message),
  warn: (message) => console.warn(`${YELLOW}warn${RESET}  ${message}`),
  error: (message) => console.error(`${RED}error${RESET} ${message}`),
  debug: (message) => {
    if (verbose) {
      console.log(`${DIM}${message}${RESET}`);
    }
  },
});

// ---------------------------------------------------------------------------
// Selection
// ---------------------------------------------------------------------------

/**
 * `--only` / `--skip` filtering, with dependency validation. A transform whose
 * `needs` are not satisfied by the selection is an error rather than a silent
 * partial run - the Dart and native halves of the recorder rename, for one,
 * must never run apart.
 */
export const selectTransforms = (
  registry: readonly Transform[],
  only: readonly string[] | null,
  skip: readonly string[]
): Transform[] => {
  const known = new Set(registry.map((t) => t.id));
  for (const id of [...(only ?? []), ...skip]) {
    if (!known.has(id)) {
      throw new Error(
        `unknown transform id "${id}". Known ids: ${registry.map((t) => t.id).join(", ")}`
      );
    }
  }

  const selected = registry.filter(
    (t) => (only === null || only.includes(t.id)) && !skip.includes(t.id)
  );
  const selectedIds = new Set(selected.map((t) => t.id));

  for (const transform of selected) {
    for (const need of transform.needs ?? []) {
      if (!selectedIds.has(need)) {
        throw new Error(
          `transform "${transform.id}" needs "${need}", which is not in the selection. ` +
            `These two must run together.`
        );
      }
    }
  }

  return selected;
};

// ---------------------------------------------------------------------------
// Conflict detection
// ---------------------------------------------------------------------------

export const findConflicts = (planned: readonly PlannedChange[]): string[] => {
  const conflicts: string[] = [];
  const writers = new Map<string, string>();
  const moveSources = new Map<string, string>();
  const moveTargets = new Map<string, string>();

  for (const { transformId, change } of planned) {
    if (change.kind === "write") {
      const previous = writers.get(change.path);
      if (previous !== undefined) {
        conflicts.push(
          `${change.path}: written by both "${previous}" and "${transformId}"`
        );
      }
      writers.set(change.path, transformId);
    } else if (change.kind === "move") {
      const previousSource = moveSources.get(change.from);
      if (previousSource !== undefined) {
        conflicts.push(
          `${change.from}: moved by both "${previousSource}" and "${transformId}"`
        );
      }
      moveSources.set(change.from, transformId);

      const previousTarget = moveTargets.get(change.to);
      if (previousTarget !== undefined) {
        conflicts.push(
          `${change.to}: two moves target it ("${previousTarget}" and "${transformId}")`
        );
      }
      moveTargets.set(change.to, transformId);
    }
  }

  // A file written and then moved away loses the write. Ordering makes this
  // legal in principle, but in practice it is always a mistake.
  for (const [path, writer] of writers) {
    const mover = moveSources.get(path);
    if (mover !== undefined) {
      conflicts.push(
        `${path}: written by "${writer}" but moved away by "${mover}" - the write would be lost or misplaced`
      );
    }
  }

  return conflicts;
};

// ---------------------------------------------------------------------------
// Dry-run reporting
// ---------------------------------------------------------------------------

const countChangedLines = (before: string, after: string): number => {
  const a = before.split("\n");
  const b = after.split("\n");
  const max = Math.max(a.length, b.length);
  let changed = 0;
  for (let i = 0; i < max; i += 1) {
    if (a[i] !== b[i]) {
      changed += 1;
    }
  }
  return changed;
};

const sampleChangedLines = (
  before: string,
  after: string,
  limit: number
): Array<{ line: number; before: string; after: string }> => {
  const a = before.split("\n");
  const b = after.split("\n");
  const max = Math.max(a.length, b.length);
  const samples: Array<{ line: number; before: string; after: string }> = [];
  for (let i = 0; i < max && samples.length < limit; i += 1) {
    if (a[i] !== b[i]) {
      samples.push({ line: i + 1, before: a[i] ?? "", after: b[i] ?? "" });
    }
  }
  return samples;
};

export const reportPlan = async (
  root: string,
  planned: readonly PlannedChange[],
  log: Logger,
  sampleLimit = 3
): Promise<void> => {
  let currentTransform = "";

  for (const { transformId, change } of planned) {
    if (transformId !== currentTransform) {
      currentTransform = transformId;
      log.info(`\n${DIM}── ${transformId}${RESET}`);
    }

    switch (change.kind) {
      case "write": {
        const absolute = join(root, change.path);
        const exists = await Bun.file(absolute).exists();
        if (!exists) {
          log.info(`  ${GREEN}create${RESET} ${change.path}`);
          break;
        }
        if (typeof change.contents !== "string") {
          log.info(`  ${YELLOW}binary${RESET} ${change.path}`);
          break;
        }
        const before = await Bun.file(absolute).text();
        if (before === change.contents) {
          break;
        }
        const changed = countChangedLines(before, change.contents);
        log.info(`  ${YELLOW}modify${RESET} ${change.path} ${DIM}(${changed} lines)${RESET}`);
        for (const sample of sampleChangedLines(before, change.contents, sampleLimit)) {
          log.info(`    ${DIM}${sample.line}${RESET} ${RED}-${RESET} ${sample.before.trim().slice(0, 120)}`);
          log.info(`    ${DIM}${" ".repeat(String(sample.line).length)}${RESET} ${GREEN}+${RESET} ${sample.after.trim().slice(0, 120)}`);
        }
        break;
      }
      case "move":
        log.info(`  ${YELLOW}move${RESET}   ${change.from} ${DIM}->${RESET} ${change.to}`);
        break;
      case "delete":
        log.info(`  ${RED}delete${RESET} ${change.path}`);
        break;
      case "exec":
        log.info(`  ${DIM}exec${RESET}   ${change.cmd.join(" ")} ${DIM}(${change.why})${RESET}`);
        break;
      default:
        break;
    }
  }
};

// ---------------------------------------------------------------------------
// Commit
// ---------------------------------------------------------------------------

const pathExists = async (absolute: string): Promise<boolean> => {
  try {
    await stat(absolute);
    return true;
  } catch {
    return false;
  }
};

const run = async (
  cmd: readonly string[],
  cwd: string
): Promise<{ code: number; stdout: string; stderr: string }> => {
  const proc = Bun.spawn([...cmd], { cwd, stdout: "pipe", stderr: "pipe" });
  const [stdout, stderr, code] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
    proc.exited,
  ]);
  return { code, stdout, stderr };
};

/**
 * Moves a tracked path with `git mv`, falling back to a plain rename for paths
 * git does not know about.
 *
 * `git mv` is preferred because it keeps the index consistent - the diff then
 * shows a rename rather than a delete plus an add, which is the difference
 * between a reviewable rebrand commit and an unreadable one - and because it
 * refuses to clobber, where `fs.rename` would happily overwrite.
 */
export const movePath = async (
  root: string,
  from: string,
  to: string,
  log: Logger
): Promise<void> => {
  const absoluteFrom = join(root, from);
  const absoluteTo = join(root, to);

  if (!(await pathExists(absoluteFrom))) {
    throw new Error(`cannot move "${from}": it does not exist`);
  }
  if (await pathExists(absoluteTo)) {
    throw new Error(`cannot move "${from}" to "${to}": the target already exists`);
  }

  await mkdir(dirname(absoluteTo), { recursive: true });

  const result = await run(["git", "mv", from, to], root);
  if (result.code === 0) {
    log.debug(`git mv ${from} -> ${to}`);
    return;
  }

  log.debug(`git mv declined (${result.stderr.trim()}); falling back to rename`);
  await rename(absoluteFrom, absoluteTo);
};

/**
 * Removes directories left empty by a move, walking upward. Stops at the first
 * non-empty directory and never escapes `stopAt`.
 */
export const pruneEmptyDirs = async (
  root: string,
  startDir: string,
  stopAt: string
): Promise<void> => {
  let current = join(root, startDir);
  const boundary = join(root, stopAt);

  while (current.startsWith(boundary) && current !== boundary) {
    let entries: string[];
    try {
      entries = await readdir(current);
    } catch {
      return;
    }
    if (entries.length > 0) {
      return;
    }
    try {
      // `rm` refuses a directory unless `recursive` is set, and `recursive`
      // would defeat the point of only removing empty ones. `rmdir` is the
      // operation that actually fails loudly if the directory is not empty.
      await rmdir(current);
    } catch {
      return;
    }
    current = dirname(current);
  }
};

export const commitChanges = async (
  root: string,
  planned: readonly PlannedChange[],
  log: Logger
): Promise<void> => {
  for (const { transformId, change } of planned) {
    try {
      switch (change.kind) {
        case "write": {
          const absolute = join(root, change.path);
          await mkdir(dirname(absolute), { recursive: true });
          await Bun.write(absolute, change.contents);
          break;
        }
        case "move": {
          await movePath(root, change.from, change.to, log);
          // Moving `kotlin/open/fpvlabs/stera` out leaves `open/fpvlabs/`
          // behind. An empty package chain is harmless to the build but makes
          // `git status` noisy and confuses the "package matches directory"
          // check in verify.ts, so it goes now.
          const sourceParent = dirname(change.from);
          if (sourceParent !== "." && sourceParent !== "") {
            await pruneEmptyDirs(root, sourceParent, ".");
          }
          break;
        }
        case "delete":
          await rm(join(root, change.path), { recursive: true, force: true });
          break;
        case "exec": {
          log.info(`  ${DIM}$ ${change.cmd.join(" ")}${RESET}`);
          const result = await run(change.cmd, change.cwd);
          if (result.code !== 0) {
            throw new Error(
              `command failed (exit ${result.code}): ${change.cmd.join(" ")}\n${result.stderr.trim() || result.stdout.trim()}`
            );
          }
          break;
        }
        default:
          break;
      }
    } catch (cause) {
      throw new TransformError(transformId, cause, "commit");
    }
  }
};

// ---------------------------------------------------------------------------
// Orchestration
// ---------------------------------------------------------------------------

export const runTransforms = async (
  ctx: Ctx,
  registry: readonly Transform[]
): Promise<RunResult> => {
  const selected = selectTransforms(registry, ctx.flags.only, ctx.flags.skip);
  const planned: PlannedChange[] = [];
  const outcomes = new Map<string, "ok" | "skipped" | "no-op">();

  // Ownership is resolved across the whole selection before anything plans, so
  // the sweep knows which files to leave to a specialist transform.
  ctx.owned.clear();
  for (const transform of selected) {
    for (const path of transform.owns?.(ctx.prev, ctx.next) ?? []) {
      ctx.owned.add(path);
    }
  }

  for (const transform of selected) {
    if (transform.enabled && !transform.enabled(ctx)) {
      ctx.log.debug(`skip ${transform.id} (disabled)`);
      outcomes.set(transform.id, "skipped");
      continue;
    }

    let changes: Change[];
    try {
      changes = await transform.plan(ctx);
    } catch (cause) {
      throw new TransformError(transform.id, cause, "plan");
    }

    if (changes.length === 0) {
      outcomes.set(transform.id, "no-op");
      continue;
    }

    outcomes.set(transform.id, "ok");
    for (const change of changes) {
      planned.push({ transformId: transform.id, change });
    }
  }

  // Drop writes whose content already matches disk.
  //
  // The generated-file transforms emit their output unconditionally - that is
  // what makes them idempotent by construction - but a write is still a write,
  // and re-running with an unchanged brand.json would rewrite a dozen identical
  // files and leave `git status` dirty. Filtering here means every transform
  // gets change-detection for free instead of each remembering to implement it.
  const effective: PlannedChange[] = [];
  for (const entry of planned) {
    if (entry.change.kind === "write") {
      const absolute = join(ctx.root, entry.change.path);
      const file = Bun.file(absolute);
      if (await file.exists()) {
        const current =
          typeof entry.change.contents === "string"
            ? await file.text()
            : new Uint8Array(await file.arrayBuffer());
        const same =
          typeof entry.change.contents === "string"
            ? current === entry.change.contents
            : Buffer.compare(
                Buffer.from(current as Uint8Array),
                Buffer.from(entry.change.contents)
              ) === 0;
        if (same) {
          continue;
        }
      }
    }
    effective.push(entry);
  }
  planned.length = 0;
  planned.push(...effective);

  const conflicts = findConflicts(planned);
  if (conflicts.length > 0) {
    throw new PlanConflictError(conflicts);
  }

  if (ctx.flags.dryRun) {
    await reportPlan(ctx.root, planned, ctx.log);
    return { planned, outcomes, committed: false };
  }

  await commitChanges(ctx.root, planned, ctx.log);
  return { planned, outcomes, committed: true };
};

/** Helper for transforms: a `write` change, skipped when content is unchanged. */
export const writeIfChanged = async (
  ctx: Ctx,
  path: string,
  contents: string,
  why?: string
): Promise<Change[]> => {
  const absolute = join(ctx.root, path);
  if (await Bun.file(absolute).exists()) {
    const before = await Bun.file(absolute).text();
    if (before === contents) {
      return [];
    }
  }
  return [{ kind: "write", path, contents, ...(why === undefined ? {} : { why }) }];
};

/** Repo-relative path, normalised to forward slashes. */
export const rel = (root: string, absolute: string): string =>
  relative(root, absolute).split("\\").join("/");
