#!/usr/bin/env bun
/**
 * White-label engine entry point.
 *
 *   bun run brand:apply           apply packages/brand/brand.json to the tree
 *   bun run brand:check           same, but print the plan and touch nothing
 *
 * See packages/brand/README.md for the full contract. The short version: this reads
 * `packages/brand/brand.json`, diffs it against the brand recorded in
 * `packages/brand/.applied.json` (or the upstream literal on the first run), and rewrites
 * the repository from one to the other.
 */

import { join } from "node:path";

import { BrandConfigError, derive } from "./lib/derive.ts";
import { createFileIndex } from "./lib/fileindex.ts";
import { diffStat, headSha } from "./lib/git.ts";
import { createLogger, PlanConflictError, runTransforms, TransformError } from "./lib/runner.ts";
import { findHandEdited, readState, writeState } from "./lib/state.ts";
import type { AppliedState } from "./lib/state.ts";
import { buildTokens } from "./lib/tokens.ts";
import { UPSTREAM_BRAND } from "./lib/upstream.ts";
import { REGISTRY, transformIds } from "./transforms/index.ts";
import type { Brand, BrandInput, EngineFlags } from "./lib/types.ts";

const BRAND_PATH = "packages/brand/brand.json";

const USAGE = `
Usage: bun run packages/brand/apply.ts [options]

Options:
  --dry-run              Print the plan and exit without touching anything.
  --only=<ids>           Run only these transforms (comma-separated).
  --skip=<ids>           Skip these transforms (comma-separated).
  --allow-dirty          Proceed even though the working tree has changes.
  --break-mcap-compat    Drop the legacy MCAP schema aliases.
  --no-verify            Skip the post-run verification pass.
  --force                Overwrite generated files that were hand-edited.
  --from-baseline=<ref>  Treat <ref> as the applied state instead of the ledger.
  --verbose              Print debug output.
  --list                 List transform ids and exit.
  -h, --help             Show this message.

Transforms: ${transformIds().join(", ")}
`.trim();

const parseFlags = (argv: readonly string[]): EngineFlags & { verbose: boolean } => {
  const listValue = (arg: string, prefix: string): string[] =>
    arg
      .slice(prefix.length)
      .split(",")
      .map((entry) => entry.trim())
      .filter((entry) => entry.length > 0);

  let only: string[] | null = null;
  const skip: string[] = [];
  let fromBaseline: string | null = null;
  let dryRun = false;
  let allowDirty = false;
  let breakMcapCompat = false;
  let noVerify = false;
  let force = false;
  let verbose = false;

  for (const arg of argv) {
    if (arg === "--dry-run") {
      dryRun = true;
    } else if (arg === "--allow-dirty") {
      allowDirty = true;
    } else if (arg === "--break-mcap-compat") {
      breakMcapCompat = true;
    } else if (arg === "--no-verify") {
      noVerify = true;
    } else if (arg === "--force") {
      force = true;
    } else if (arg === "--verbose") {
      verbose = true;
    } else if (arg.startsWith("--only=")) {
      only = listValue(arg, "--only=");
    } else if (arg.startsWith("--skip=")) {
      skip.push(...listValue(arg, "--skip="));
    } else if (arg.startsWith("--from-baseline=")) {
      fromBaseline = arg.slice("--from-baseline=".length);
    } else {
      throw new Error(`unknown option "${arg}"\n\n${USAGE}`);
    }
  }

  return {
    dryRun,
    only,
    skip,
    allowDirty,
    breakMcapCompat,
    noVerify,
    force,
    fromBaseline,
    verbose,
  };
};

const loadBrandInput = async (root: string): Promise<BrandInput> => {
  const file = Bun.file(join(root, BRAND_PATH));
  if (!(await file.exists())) {
    throw new Error(
      `${BRAND_PATH} not found.\n\n` +
        `Run the /whitelabel command in Claude Code to generate it interactively, ` +
        `or copy packages/brand/brand.example.json and edit it.`
    );
  }
  try {
    return (await file.json()) as BrandInput;
  } catch (cause) {
    throw new Error(
      `${BRAND_PATH} is not valid JSON: ${cause instanceof Error ? cause.message : String(cause)}`
    );
  }
};

const pubspecDependencies = async (root: string): Promise<string[]> => {
  const file = Bun.file(join(root, "apps/mobile/pubspec.yaml"));
  if (!(await file.exists())) {
    return [];
  }
  const text = await file.text();
  const names: string[] = [];
  let inDeps = false;
  for (const line of text.split("\n")) {
    if (/^(dependencies|dev_dependencies):\s*$/.test(line)) {
      inDeps = true;
      continue;
    }
    if (/^\S/.test(line)) {
      inDeps = false;
    }
    if (!inDeps) {
      continue;
    }
    const match = /^ {2}([a-z_][a-z0-9_]*):/.exec(line);
    if (match?.[1]) {
      names.push(match[1]);
    }
  }
  return names;
};

const main = async (): Promise<number> => {
  const argv = Bun.argv.slice(2);
  if (argv.includes("-h") || argv.includes("--help")) {
    console.log(USAGE);
    return 0;
  }
  if (argv.includes("--list")) {
    for (const transform of REGISTRY) {
      console.log(`${transform.id}  ${transform.title}`);
    }
    return 0;
  }

  const flags = parseFlags(argv);
  const log = createLogger(flags.verbose);

  // The engine always operates on the repo that contains it, not on the shell's
  // cwd - running it from apps/mobile should not silently do nothing.
  const root = join(import.meta.dir, "..", "..");

  const state = await readState(root);
  const prev: Brand = state?.brand ?? UPSTREAM_BRAND;

  if (flags.fromBaseline !== null) {
    log.warn(
      `--from-baseline=${flags.fromBaseline} is not yet implemented; using the ledger instead.`
    );
  }

  const input = await loadBrandInput(root);
  const next = derive(input, {
    pubspecDependencies: await pubspecDependencies(root),
    upstream: UPSTREAM_BRAND,
  });

  if (flags.breakMcapCompat) {
    next.compat.keepMcapAliases = false;
  }

  const handEdited = await findHandEdited(root, state);
  if (handEdited.length > 0 && !(flags.force || flags.dryRun)) {
    log.error(
      `these generated files have been edited by hand since the last run and would be overwritten:\n` +
        handEdited.map((path) => `  ${path}`).join("\n") +
        `\n\nMove your changes into ${BRAND_PATH}, or re-run with --force to discard them.`
    );
    return 1;
  }

  log.info(
    `Rebranding ${prev.copy.appName} (${prev.identifiers.bundleId}) -> ${next.copy.appName} (${next.identifiers.bundleId})`
  );
  if (flags.dryRun) {
    log.info("Dry run: nothing will be written.\n");
  }

  const ctx = {
    root,
    prev,
    next,
    tokens: buildTokens(prev, next),
    files: await createFileIndex(root),
    log,
    flags,
    owned: new Set<string>(),
  };

  const result = await runTransforms(ctx, REGISTRY);

  if (!result.committed) {
    log.info(
      `\n${result.planned.length} change(s) planned. Re-run without --dry-run to apply.`
    );
    return 0;
  }

  // A re-run with an unchanged brand.json legitimately produces no file edits -
  // only `exec` steps like `bun install`, which are safe to repeat. Rewriting
  // the ledger anyway would churn its timestamp and leave `git status` dirty,
  // making the engine look non-idempotent when it is not.
  const touchedFiles = result.planned.some(
    ({ change }) => change.kind !== "exec"
  );
  if (!touchedFiles && state !== null) {
    log.info("\nNothing to change - the tree already matches packages/brand/brand.json.");
    return 0;
  }

  const generatedHashes: Record<string, string> = { ...(state?.generatedHashes ?? {}) };
  const applied: AppliedState = {
    engineVersion: next.engineVersion,
    brand: next,
    appliedAt: new Date().toISOString(),
    gitCommit: await headSha(root),
    transforms: Object.fromEntries(result.outcomes),
    generatedHashes,
  };
  await writeState(root, applied);

  log.info(`\nApplied ${result.planned.length} change(s).`);
  const stat = await diffStat(root);
  if (stat.trim().length > 0) {
    log.info(`\n${stat.trimEnd()}`);
  }
  log.info(
    `\nNothing has been committed. Review the diff, then commit when you are happy.`
  );

  return 0;
};

try {
  process.exit(await main());
} catch (error) {
  const log = createLogger(false);
  if (error instanceof BrandConfigError || error instanceof PlanConflictError) {
    log.error(error.message);
  } else if (error instanceof TransformError) {
    log.error(error.message);
    log.error(
      error.phase === "plan"
        ? `\nNothing was written - the failure happened while planning. Fix the cause and re-run.`
        : `\nThe run stopped part-way and the tree is partially rebranded. Fix the cause, then re-run; ` +
            `transforms that already succeeded are safe to repeat. \`git checkout .\` reverts everything.`
    );
  } else {
    log.error(error instanceof Error ? error.message : String(error));
  }
  process.exit(1);
}
