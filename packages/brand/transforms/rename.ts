/**
 * `10-move-paths` and `20-rewrite-content`.
 *
 * These two do the bulk of the rebrand between them, and the split is
 * deliberate: paths move first, then contents are written to the *new* paths.
 * Doing it the other way round means writing 194 files and then moving them,
 * which works but makes a crash half-way through much harder to reason about.
 *
 * The content pass is one sweep over every rewritable tracked file rather than
 * a dozen hand-listed per-area transforms. Hand-listing looks tidier in a
 * registry, but every file it forgets is a silent miss that only shows up as a
 * broken build - and `packages/brand/lib/fileindex.ts` already encodes exactly which
 * files are off-limits. The tokenizer is precise enough to be pointed at
 * everything else.
 */

import {
  isRadiusSweepTarget,
  rewriteRadii,
  rewriteSpacing,
} from "../lib/dartsweep.ts";
import { applyTokens } from "../lib/tokens.ts";
import {
  assertRulesSane,
  buildPathRules,
  kotlinSourceRoots,
  mapPath,
} from "../lib/paths.ts";
import { isRewritable } from "../lib/fileindex.ts";
import type { Change, Ctx, Transform } from "../lib/types.ts";

export const movePaths: Transform = {
  id: "10-move-paths",
  title: "Rename directories and files",

  async plan(ctx: Ctx): Promise<Change[]> {
    const rules = buildPathRules(ctx.prev, ctx.next);
    assertRulesSane(rules);

    const changes: Change[] = [];

    // Simulate the tree as the moves are applied, so each rule can be tested
    // against the state it will actually see. A rule fires only if something is
    // there: a fork that already renamed the recorder by hand, or one that set
    // `recorder.rename: false`, must not emit a move for a missing directory.
    let current = ctx.files.all();

    for (const rule of rules) {
      const matches = current.filter(
        (path) => path === rule.from || path.startsWith(`${rule.from}/`)
      );
      if (matches.length === 0) {
        ctx.log.debug(`skip path rule "${rule.label}": ${rule.from} not present`);
        continue;
      }

      changes.push({
        kind: "move",
        from: rule.from,
        to: rule.to,
        why: `${rule.label} (${matches.length} file${matches.length === 1 ? "" : "s"})`,
      });

      current = current.map((path) =>
        path === rule.from || path.startsWith(`${rule.from}/`)
          ? rule.to + path.slice(rule.from.length)
          : path
      );
    }

    const moved = ctx.files.all().filter((path) => mapPath(path, rules) !== path);
    if (changes.length > 0) {
      ctx.log.info(
        `  ${changes.length} directory rename(s), affecting ${moved.length} file(s)`
      );
    }

    return changes;
  },
};

export const rewriteContent: Transform = {
  id: "20-rewrite-content",
  title: "Rewrite brand tokens in tracked files",
  needs: ["10-move-paths"],

  async plan(ctx: Ctx): Promise<Change[]> {
    const rules = buildPathRules(ctx.prev, ctx.next);
    const changes: Change[] = [];
    const hits = new Map<string, number>();
    const radiiConverted = new Map<string, number>();
    const radiiSkipped = new Map<number, number>();
    const spaceConverted = new Map<string, number>();
    const spaceSkipped = new Map<number, number>();
    let filesChanged = 0;

    for (const path of ctx.files.rewritable()) {
      if (ctx.owned.has(path)) {
        ctx.log.debug(`skip ${path}: owned by a specialist transform`);
        continue;
      }
      const before = await ctx.files.read(path);
      const result = applyTokens(before, ctx.tokens);
      const destination = mapPath(path, rules);

      // The corner-radius rewrite rides along with the token sweep rather than
      // running as its own transform: it wants the same forty widget files the
      // sweep already has open, and one writer per file is what keeps the plan
      // conflict-free. See lib/dartsweep.ts.
      let after = result.text;
      if (isRadiusSweepTarget(path)) {
        const radii = rewriteRadii(after, ctx.next.identifiers.dartPackage);
        after = radii.text;
        for (const [step, count] of radii.converted) {
          radiiConverted.set(step, (radiiConverted.get(step) ?? 0) + count);
        }
        for (const [value, count] of radii.skipped) {
          radiiSkipped.set(value, (radiiSkipped.get(value) ?? 0) + count);
        }

        const space = rewriteSpacing(after, ctx.next.identifiers.dartPackage);
        after = space.text;
        for (const [step, count] of space.converted) {
          spaceConverted.set(step, (spaceConverted.get(step) ?? 0) + count);
        }
        for (const [value, count] of space.skipped) {
          spaceSkipped.set(value, (spaceSkipped.get(value) ?? 0) + count);
        }
      }

      // A file whose content is unchanged still needs no write - the move
      // transform has already put it at `destination`.
      if (after === before) {
        continue;
      }

      filesChanged += 1;
      for (const [label, count] of result.hits) {
        hits.set(label, (hits.get(label) ?? 0) + count);
      }

      changes.push({
        kind: "write",
        path: destination,
        contents: after,
        why: "brand token rewrite",
      });
    }

    if (filesChanged > 0) {
      ctx.log.info(`  ${filesChanged} file(s) contain brand tokens:`);
      for (const [label, count] of [...hits].sort((a, b) => b[1] - a[1])) {
        ctx.log.info(`    ${String(count).padStart(5)}  ${label}`);
      }
    }

    const converted = [...radiiConverted.values()].reduce((a, b) => a + b, 0);
    if (converted > 0) {
      ctx.log.info(
        `  ${converted} corner radius/radii now follow theme.shape (${[...radiiConverted]
          .sort()
          .map(([step, count]) => `${step}:${count}`)
          .join(" ")})`
      );
    }
    const spaced = [...spaceConverted.values()].reduce((a, b) => a + b, 0);
    if (spaced > 0) {
      ctx.log.info(
        `  ${spaced} gap(s) and pad(s) now follow theme.space (${[...spaceConverted]
          .sort()
          .map(([step, count]) => `${step}:${count}`)
          .join(" ")})`
      );
    }
    if (spaceSkipped.size > 0) {
      ctx.log.info(
        `  ${[...spaceSkipped].reduce((sum, [, count]) => sum + count, 0)} off-scale ` +
          `gap(s) left as literals: ${[...spaceSkipped]
            .sort((a, b) => a[0] - b[0])
            .map(([value, count]) => `${value}px x${count}`)
            .join(", ")}`
      );
    }
    if (radiiSkipped.size > 0) {
      // Silence here would read as "everything is on the scale", so the
      // one-offs are named. Promoting one is a hand edit, by design.
      ctx.log.info(
        `  ${[...radiiSkipped].reduce((sum, [, count]) => sum + count, 0)} off-scale ` +
          `radius/radii left as literals: ${[...radiiSkipped]
            .sort((a, b) => a[0] - b[0])
            .map(([value, count]) => `${value}px x${count}`)
            .join(", ")}`
      );
    }

    return changes;
  },
};

/**
 * `15-prune-empty-dirs` is not a transform - directory pruning happens inside
 * the runner right after each move, because only the runner knows whether a
 * directory ended up empty. This is exported for the verifier, which checks
 * that no orphaned package root survived.
 */
export const orphanedKotlinRoots = (ctx: Ctx): string[] => {
  const rules = buildPathRules(ctx.prev, ctx.next);
  const recorderRoot = `packages/${ctx.next.identifiers.recorder.dartPackage}`;
  const roots = kotlinSourceRoots(recorderRoot);
  const stale = ctx.prev.identifiers.kotlinPackage.split(".")[0];
  return stale === undefined ? [] : roots.map((root) => `${root}/${stale}`).filter((path) =>
    ctx.files.all().some((tracked) => mapPath(tracked, rules).startsWith(`${path}/`))
  );
};

export { isRewritable };
