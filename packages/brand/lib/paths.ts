/**
 * Path renames.
 *
 * Roughly 210 tracked files change path during a rebrand, but almost all of
 * them move because a *directory* above them was renamed. So the engine works
 * in directory moves, not file moves: one `git mv` for
 * `packages/stera_recorder`, not 194.
 *
 * The rules below are an ordered list of prefix substitutions, and the order is
 * significant in a specific way: each rule is written in terms of the tree as it
 * exists *after* every earlier rule has been applied. That is exactly what a
 * sequence of `git mv` calls does, which means the same list serves two
 * purposes - it is both the move plan and, via `mapPath`, the function that
 * tells the content-rewriting transform where a file will have ended up.
 */

import type { Brand } from "./types.ts";

export interface PathRule {
  from: string;
  to: string;
  label: string;
}

const KOTLIN_ROOTS = {
  app: "apps/mobile/android/app/src/main/kotlin",
  recorder: "android/src/main/kotlin",
  example: "example/android/app/src/main/kotlin",
} as const;

const packageToDir = (pkg: string): string => pkg.split(".").join("/");

/**
 * Builds the ordered rename list.
 *
 * Rules whose source and target are equal are dropped - unlike token rules,
 * a no-op path rule has no shadowing job to do.
 */
export const buildPathRules = (prev: Brand, next: Brand): PathRule[] => {
  const p = prev.identifiers;
  const n = next.identifiers;

  const prevRec = p.recorder.dartPackage;
  const nextRec = n.recorder.dartPackage;
  const recRoot = `packages/${nextRec}`;

  const rules: PathRule[] = [
    // 1. The recorder package directory. Everything below is expressed against
    //    its new location.
    {
      from: `packages/${prevRec}`,
      to: recRoot,
      label: "recorder package directory",
    },

    // 2. Dart entry point.
    {
      from: `${recRoot}/lib/${prevRec}.dart`,
      to: `${recRoot}/lib/${nextRec}.dart`,
      label: "recorder Dart entry point",
    },

    // 3-7. iOS. The podspec must be renamed as well as the directory it names,
    //      and `s.source_files` inside it globs the Sources/ subdirectories.
    {
      from: `${recRoot}/ios/${prevRec}.podspec`,
      to: `${recRoot}/ios/${nextRec}.podspec`,
      label: "recorder podspec",
    },
    {
      from: `${recRoot}/ios/${prevRec}`,
      to: `${recRoot}/ios/${nextRec}`,
      label: "recorder SwiftPM package directory",
    },
    {
      from: `${recRoot}/ios/${nextRec}/Sources/${prevRec}`,
      to: `${recRoot}/ios/${nextRec}/Sources/${nextRec}`,
      label: "recorder Swift target",
    },
    {
      from: `${recRoot}/ios/${nextRec}/Sources/${p.recorder.swiftObjcTarget}`,
      to: `${recRoot}/ios/${nextRec}/Sources/${n.recorder.swiftObjcTarget}`,
      label: "recorder ObjC target",
    },
    {
      from: `${recRoot}/ios/${nextRec}/Sources/${n.recorder.swiftObjcTarget}/include/${p.recorder.swiftObjcTarget}`,
      to: `${recRoot}/ios/${nextRec}/Sources/${n.recorder.swiftObjcTarget}/include/${n.recorder.swiftObjcTarget}`,
      label: "recorder ObjC umbrella header directory",
    },
    {
      from: `${recRoot}/ios/${nextRec}/Sources/${nextRec}/${p.recorder.pluginClass}.swift`,
      to: `${recRoot}/ios/${nextRec}/Sources/${nextRec}/${n.recorder.pluginClass}.swift`,
      label: "recorder plugin class (Swift)",
    },

    // 8-10. Kotlin package trees. Moving the leaf package directory into its new
    //       parent chain is enough; the now-empty old chain is pruned after.
    {
      from: `${KOTLIN_ROOTS.app}/${packageToDir(p.kotlinPackage)}`,
      to: `${KOTLIN_ROOTS.app}/${packageToDir(n.kotlinPackage)}`,
      label: "app Kotlin package tree",
    },
    {
      from: `${recRoot}/${KOTLIN_ROOTS.recorder}/${packageToDir(p.recorder.kotlinPackage)}`,
      to: `${recRoot}/${KOTLIN_ROOTS.recorder}/${packageToDir(n.recorder.kotlinPackage)}`,
      label: "recorder Kotlin package tree",
    },
    {
      from: `${recRoot}/${KOTLIN_ROOTS.example}/${packageToDir(p.recorder.examplePackage)}`,
      to: `${recRoot}/${KOTLIN_ROOTS.example}/${packageToDir(n.recorder.examplePackage)}`,
      label: "recorder example Kotlin package tree",
    },
    {
      from: `${recRoot}/${KOTLIN_ROOTS.recorder}/${packageToDir(n.recorder.kotlinPackage)}/${p.recorder.pluginClass}.kt`,
      to: `${recRoot}/${KOTLIN_ROOTS.recorder}/${packageToDir(n.recorder.kotlinPackage)}/${n.recorder.pluginClass}.kt`,
      label: "recorder plugin class (Kotlin)",
    },

    // 11. Deployment unit. The filename is what `systemctl enable` refers to.
    {
      from: `deploy/${p.systemdServiceName}.service`,
      to: `deploy/${n.systemdServiceName}.service`,
      label: "systemd unit",
    },
  ];

  return rules.filter((rule) => rule.from !== rule.to);
};

const isUnder = (path: string, prefix: string): boolean =>
  path === prefix || path.startsWith(`${prefix}/`);

/**
 * Where `path` ends up once every rule has been applied.
 *
 * Applied sequentially, mirroring the move order, so a file inside a directory
 * that is itself renamed twice lands in the right place.
 */
export const mapPath = (path: string, rules: readonly PathRule[]): string => {
  let current = path;
  for (const rule of rules) {
    if (isUnder(current, rule.from)) {
      current = rule.to + current.slice(rule.from.length);
    }
  }
  return current;
};

/**
 * Rejects a rule that would move a directory inside itself - `git mv a a/b` is
 * not a rename, it is a way to lose a directory.
 */
export const assertRulesSane = (rules: readonly PathRule[]): void => {
  for (const rule of rules) {
    if (isUnder(rule.to, rule.from)) {
      throw new Error(
        `path rule "${rule.label}" would move "${rule.from}" inside itself (-> "${rule.to}")`
      );
    }
  }
};

/**
 * The Kotlin package-root directories left behind by a tree move, so the caller
 * can prune the empty chain (`open/fpvlabs/`) afterwards.
 */
export const kotlinSourceRoots = (recorderRoot: string): string[] => [
  KOTLIN_ROOTS.app,
  `${recorderRoot}/${KOTLIN_ROOTS.recorder}`,
  `${recorderRoot}/${KOTLIN_ROOTS.example}`,
];
