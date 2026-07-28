/**
 * `00-preflight` and `05-backup`.
 *
 * Neither produces a `Change`. They exist to fail the run *before* anything is
 * touched, which is the only cheap moment to fail: once the Dart imports are
 * half-rewritten, "just re-run it" stops being good advice.
 */

import { validateBundleId } from "../lib/derive.ts";
import { dirtyFiles, isGitRepo } from "../lib/git.ts";
import type { Change, Ctx, Transform } from "../lib/types.ts";

const which = async (command: string): Promise<boolean> => {
  const proc = Bun.spawn(["which", command], { stdout: "ignore", stderr: "ignore" });
  return (await proc.exited) === 0;
};

export const preflight: Transform = {
  id: "00-preflight",
  title: "Validate configuration and environment",

  async plan(ctx: Ctx): Promise<Change[]> {
    if (!(await isGitRepo(ctx.root))) {
      throw new Error(
        `${ctx.root} is not a git repository. The engine relies on git for file discovery and for making the rebrand revertable.`
      );
    }

    validateBundleId(ctx.next.identifiers.bundleId);

    if (ctx.next.identifiers.bundleId === ctx.prev.identifiers.bundleId) {
      ctx.log.warn(
        `bundle id is unchanged (${ctx.next.identifiers.bundleId}). That is legal, but if you meant to rebrand you probably want your own.`
      );
    }

    // The pubspec is the one file whose parse failure would poison everything
    // downstream, so read it here rather than discovering it in `20-dart-package`.
    const pubspecPath = "apps/mobile/pubspec.yaml";
    if (!ctx.files.exists(pubspecPath)) {
      throw new Error(
        `${pubspecPath} not found. Run this from the repository root.`
      );
    }
    const pubspec = await ctx.files.read(pubspecPath);
    const declaredName = /^name:\s*(\S+)\s*$/m.exec(pubspec)?.[1];
    if (declaredName !== ctx.prev.identifiers.dartPackage) {
      throw new Error(
        `${pubspecPath} declares "name: ${declaredName}", but the ledger says the applied Dart package is "${ctx.prev.identifiers.dartPackage}". ` +
          `The tree and packages/brand/.applied.json disagree - fix one of them, or re-run with --from-baseline to start from a known commit.`
      );
    }

    for (const tool of ["git", "bun"]) {
      if (!(await which(tool))) {
        throw new Error(`required tool "${tool}" is not on PATH`);
      }
    }

    // Without node_modules, Bun auto-installs on first import and can resolve
    // sharp to its WebAssembly build, which crashes mid-run with an out-of-bounds
    // memory access rather than failing to load. Far better to say so here.
    if (!(await Bun.file(`${ctx.root}/node_modules/.bin/tsc`).exists())) {
      throw new Error(
        `dependencies are not installed. Run \`bun install\` in the repository root first.\n` +
          `(The engine needs sharp for icon generation, and an auto-installed sharp resolves to a ` +
          `WebAssembly build that crashes part-way through the rebrand.)`
      );
    }
    if (!(await which("flutter"))) {
      ctx.log.warn(
        "flutter is not on PATH - the lockfile and verification steps will be skipped. Install it before building."
      );
    }

    // Compatibility decisions. These are recorded in brand.json rather than
    // asked here, because a script that blocks on stdin cannot run in CI.
    if (ctx.next.compat.keepMcapAliases) {
      ctx.log.info(
        `  MCAP: keeping legacy "${ctx.prev.identifiers.mcapSchemaNamespace}/msg/*" schema aliases so existing recordings stay readable.`
      );
    } else {
      ctx.log.warn(
        `MCAP: dropping legacy "${ctx.prev.identifiers.mcapSchemaNamespace}/msg/*" aliases. Recordings made before this rebrand will no longer decode.`
      );
    }
    if (ctx.next.compat.renameDriftDatabase) {
      ctx.log.warn(
        `drift: renaming the on-disk database to "${ctx.next.identifiers.driftDatabaseName}". Existing installs will start with an empty database.`
      );
    }
    if (ctx.next.compat.renameBookmarkPrefix) {
      ctx.log.warn(
        `iOS: renaming the security-scoped bookmark prefix. Saved folder bookmarks on existing installs will be invalidated.`
      );
    }

    return [];
  },
};

export const backup: Transform = {
  id: "05-backup",
  title: "Refuse to run on a dirty tree",

  async plan(ctx: Ctx): Promise<Change[]> {
    const dirty = await dirtyFiles(ctx.root);
    if (dirty.length === 0 || ctx.flags.allowDirty || ctx.flags.dryRun) {
      if (dirty.length > 0 && !ctx.flags.dryRun) {
        ctx.log.warn(
          `proceeding with ${dirty.length} uncommitted change(s) because --allow-dirty was passed`
        );
      }
      return [];
    }

    throw new Error(
      `the working tree has ${dirty.length} uncommitted change(s).\n` +
        `The rebrand rewrites hundreds of files; committing first is what makes it revertable with a single \`git checkout .\`.\n` +
        `Commit or stash, or pass --allow-dirty if you know what you are doing.\n\n` +
        dirty.slice(0, 10).map((line) => `  ${line}`).join("\n") +
        (dirty.length > 10 ? `\n  ...and ${dirty.length - 10} more` : "")
    );
  },
};
