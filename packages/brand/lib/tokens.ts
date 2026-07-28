/**
 * The rename engine.
 *
 * Every rewrite in the repo goes through `applyTokens`. It is deliberately not
 * a sequence of `String.replaceAll` calls: those would let an earlier rule's
 * *output* be re-matched by a later rule, and there is no way to reason about
 * that once you have twenty rules. Instead this is a single left-to-right scan
 * where, at each position, the first matching rule wins and the cursor jumps
 * past the text it just emitted. A replacement is therefore never re-examined,
 * which makes the ordering below the only thing you have to get right.
 *
 * Ordering rule: longest and most-specific first, bare tokens last.
 *
 * The two adjacency hazards that actually exist in this repo, and which the
 * `word` anchoring exists to defend against:
 *
 *   bun.lock            "sisteransi"            <- "stera" preceded by "i"
 *   recorder example    "steraRecorderExample"  <- "stera" followed by "R"
 *
 * A naive s/stera/acme/g corrupts the first into "sisiacmensi"-shaped garbage
 * and silently breaks `bun install`. That is the whole reason this file exists.
 */

import type { Brand, TokenRule } from "./types.ts";

const literal = (from: string, to: string, label: string): TokenRule => ({
  kind: "literal",
  from,
  to,
  label,
});

const word = (from: string, to: string, label: string): TokenRule => ({
  kind: "word",
  from,
  to,
  label,
});

const isWordChar = (ch: string | undefined): boolean =>
  ch !== undefined && /[A-Za-z0-9_]/.test(ch);

/** `open.fpvlabs.stera` -> `open/fpvlabs/stera`, the on-disk form. */
const slashed = (pkg: string): string => pkg.split(".").join("/");

/**
 * Builds the ordered rule list mapping `prev` onto `next`.
 *
 * Identity rules (`from === to`) are deliberately **kept**. They look useless,
 * but they are load-bearing: a rule that matches consumes the cursor, so an
 * identity rule shields its pattern from every rule below it. If a fork chooses
 * to keep upstream's MCAP namespace, dropping the now-redundant
 * `stera/msg/ -> stera/msg/` rule would let the bare `stera` rule at the bottom
 * of the list rewrite it anyway - silently defeating the opt-out. Identity
 * rules are excluded from the hit counts, not from the list.
 */
export const buildTokens = (prev: Brand, next: Brand): TokenRule[] => {
  const p = prev.identifiers;
  const n = next.identifiers;

  const rules: TokenRule[] = [
    // --- Dart package imports. The trailing "/" makes these unambiguous, so
    // they need no word anchoring - and `package:stera_recorder/` must come
    // first or `package:stera/` would never match it anyway (different prefix),
    // but keeping the longest-first discipline costs nothing.
    literal(
      `package:${p.recorder.dartPackage}/`,
      `package:${n.recorder.dartPackage}/`,
      "recorder Dart imports"
    ),
    literal(
      `package:${p.dartPackage}/`,
      `package:${n.dartPackage}/`,
      "app Dart imports"
    ),

    // --- JVM / bundle identifiers, longest first. The recorder and example
    // packages are prefixed by the app package, so they must precede it.
    literal(
      p.recorder.kotlinPackage,
      n.recorder.kotlinPackage,
      "recorder Kotlin package"
    ),
    literal(
      p.recorder.examplePackage,
      n.recorder.examplePackage,
      "recorder example Android package"
    ),
    literal(
      p.recorder.exampleIosBundleId,
      n.recorder.exampleIosBundleId,
      "recorder example iOS bundle id"
    ),
    literal(p.kotlinPackage, n.kotlinPackage, "app Kotlin package / Android id"),

    // Slash-separated forms of the same packages. These appear in prose and in
    // path literals - `apps/mobile/CLAUDE.md` documents the Kotlin module
    // directory as `android/app/src/main/kotlin/open/fpvlabs/stera/`. Without
    // these rules the bare token rule at the bottom of the list rewrites only
    // the last segment, producing `open/fpvlabs/acme_vision`: a path that does
    // not exist and never will.
    literal(
      slashed(p.recorder.kotlinPackage),
      slashed(n.recorder.kotlinPackage),
      "recorder Kotlin package (path form)"
    ),
    literal(
      slashed(p.recorder.examplePackage),
      slashed(n.recorder.examplePackage),
      "recorder example package (path form)"
    ),
    literal(
      slashed(p.kotlinPackage),
      slashed(n.kotlinPackage),
      "app Kotlin package (path form)"
    ),
    literal(prev.legacy.iosBundleId, n.bundleId, "legacy iOS bundle id"),
    literal(prev.legacy.playStoreAppId, n.bundleId, "legacy Play Store app id"),

    // --- Data-format and scope identifiers.
    literal(
      `${p.mcapSchemaNamespace}/msg/`,
      `${n.mcapSchemaNamespace}/msg/`,
      "MCAP ROS2 schema namespace"
    ),
    literal(p.mcapWriterLibrary, n.mcapWriterLibrary, "MCAP writer library"),
    literal(`${p.npmScope}/`, `${n.npmScope}/`, "npm workspace scope"),
    // `apps/server/tsdown.config.ts` writes the scope inside a regex literal as
    // `@stera\/.*` - the separator is an escaped slash, so the rule above does
    // not match it. Anchor on the trailing side instead: `@stera` followed by
    // anything non-identifier is unambiguously the scope, while `@steradian`
    // is left alone.
    word(p.npmScope, n.npmScope, "npm workspace scope (escaped)"),

    // --- Recorder plugin symbols. `<name>_objc` must precede `<name>`.
    literal(
      p.recorder.pluginClass,
      n.recorder.pluginClass,
      "recorder plugin class"
    ),
    literal(
      p.recorder.swiftObjcTarget,
      n.recorder.swiftObjcTarget,
      "recorder ObjC target"
    ),
    literal(
      p.recorder.dartPackage,
      n.recorder.dartPackage,
      "recorder package name"
    ),

    // --- Prose. The full app title must precede the subtitle, which must in
    // turn precede the bare org name, or "Stera by FPV Labs" would be rewritten
    // in two uncoordinated pieces.
    literal(prev.copy.appTitle, next.copy.appTitle, "app title"),
    literal(
      prev.copy.splashSubtitle,
      next.copy.splashSubtitle,
      "splash subtitle"
    ),
    literal(prev.brand.legalEntity, next.brand.legalEntity, "legal entity"),
    // Whole URL, and before `repoName`. The GitHub repo is `stera-app` while
    // the directory, deploy path and npm scope are `stera-open`, so the
    // repoName rule no longer reaches inside the URL - and without this the
    // bare `stera` token would chew it into `github.com/fpv-labs/acme_vision-app`.
    literal(prev.urls.sourceRepo, next.urls.sourceRepo, "source repo URL"),
    literal(p.repoName, n.repoName, "repository name"),

    // --- Bare tokens, word-anchored, LAST. Everything above has already
    // consumed the compound forms, so these only ever see standalone uses.
    word(p.dartPackage, n.dartPackage, "bare package token"),
    word(prev.copy.appName, next.copy.appName, "bare app name"),
  ];

  return rules.filter((rule) => rule.from.length > 0);
};

export interface ApplyResult {
  text: string;
  /** Rule label -> number of substitutions made. */
  hits: Map<string, number>;
}

/**
 * Single left-to-right pass. First matching rule at each position wins; the
 * cursor advances past the *source* text consumed, and the replacement is
 * appended to the output where it can never be re-scanned.
 */
export const applyTokens = (input: string, rules: readonly TokenRule[]): ApplyResult => {
  const hits = new Map<string, number>();
  let out = "";
  let i = 0;

  outer: while (i < input.length) {
    for (const rule of rules) {
      if (!input.startsWith(rule.from, i)) {
        continue;
      }
      if (rule.kind === "word") {
        const before = i > 0 ? input[i - 1] : undefined;
        const after = input[i + rule.from.length];
        if (isWordChar(before) || isWordChar(after)) {
          continue;
        }
      }
      out += rule.to;
      i += rule.from.length;
      // Identity rules exist only to shadow later rules; they are not edits.
      if (rule.from !== rule.to) {
        hits.set(rule.label, (hits.get(rule.label) ?? 0) + 1);
      }
      continue outer;
    }
    out += input[i];
    i += 1;
  }

  return { text: out, hits };
};

/** Convenience for callers that do not care about the hit counts. */
export const rewrite = (input: string, rules: readonly TokenRule[]): string =>
  applyTokens(input, rules).text;

// ---------------------------------------------------------------------------
// Residual detection (used by verify.ts)
// ---------------------------------------------------------------------------

export interface StaleHit {
  token: string;
  line: number;
  column: number;
  excerpt: string;
}

/**
 * Finds occurrences of `tokens` that survived a rename. Word-anchored, so it
 * agrees with what `applyTokens` would have rewritten - otherwise verify would
 * flag `sisteransi` as a miss forever.
 */
export const findStale = (
  text: string,
  tokens: readonly string[]
): StaleHit[] => {
  const hits: StaleHit[] = [];
  const lines = text.split("\n");

  lines.forEach((lineText, index) => {
    for (const token of tokens) {
      if (token.length === 0) {
        continue;
      }
      let from = 0;
      for (;;) {
        const at = lineText.indexOf(token, from);
        if (at === -1) {
          break;
        }
        const before = at > 0 ? lineText[at - 1] : undefined;
        const after = lineText[at + token.length];
        if (!(isWordChar(before) || isWordChar(after))) {
          hits.push({
            token,
            line: index + 1,
            column: at + 1,
            excerpt: lineText.trim().slice(0, 160),
          });
        }
        from = at + token.length;
      }
    }
  });

  return hits;
};

/**
 * The set of previous-brand tokens that must not survive anywhere outside the
 * attribution allowlist.
 */
export const staleTokensOf = (prev: Brand): string[] =>
  Array.from(
    new Set(
      [
        prev.identifiers.dartPackage,
        prev.copy.appName,
        prev.identifiers.kotlinPackage,
        prev.identifiers.recorder.dartPackage,
        prev.identifiers.recorder.pluginClass,
        prev.identifiers.npmScope,
        prev.identifiers.repoName,
        prev.brand.legalEntity,
        prev.identifiers.mcapWriterLibrary,
        prev.legacy.iosBundleId,
      ].filter((token) => token.length > 0)
    )
  );
