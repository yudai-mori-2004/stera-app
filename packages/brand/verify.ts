#!/usr/bin/env bun
/**
 * Post-rebrand verification.
 *
 *   bun run brand:verify              structural checks only (fast)
 *   bun run brand:verify --full       also run the toolchains
 *   bun run brand:verify --build      also build a debug APK
 *
 * The structural checks are the interesting half. A compiler will tell you that
 * a Kotlin import is wrong; nothing will tell you that the background-upload
 * task id in Info.plist stopped matching the one the Swift code registers,
 * because that combination compiles perfectly and simply never fires at
 * runtime. Everything in `structuralChecks` is a mismatch of that kind.
 */

import { join } from "node:path";

import { isRadiusSweepTarget } from "./lib/dartsweep.ts";
import { createFileIndex } from "./lib/fileindex.ts";
import {
  BRAND_DART_PATH,
  BRAND_FONTS_PATH,
  BRAND_PALETTE_PATH,
  BRAND_SHAPE_PATH,
  BRAND_SPACE_PATH,
  BRAND_TYPE_PATH,
  COLORS_DART_PATH,
} from "./lib/generate.ts";
import { TOKEN_NAMES } from "./lib/palette.ts";
import { snapToStep } from "./lib/shape.ts";
import { snapToSpaceStep } from "./lib/space.ts";
import { readState } from "./lib/state.ts";
import { findStale, staleTokensOf } from "./lib/tokens.ts";
import { snapToTypeStep, snapToWeightRole } from "./lib/type.ts";
import { UPSTREAM_ASSET_HASHES, UPSTREAM_BRAND } from "./lib/upstream.ts";
import type { Brand, FileIndex } from "./lib/types.ts";

const RED = "[31m";
const GREEN = "[32m";
const YELLOW = "[33m";
const DIM = "[2m";
const RESET = "[0m";

export interface CheckResult {
  name: string;
  status: "pass" | "fail" | "skip";
  detail?: string;
  hits?: string[];
}

interface CheckCtx {
  root: string;
  files: FileIndex;
  prev: Brand;
  next: Brand;
}

/**
 * Existence on disk, not in the git index.
 *
 * `FileIndex` is built from `git ls-files`, which is right for deciding what to
 * rewrite but wrong for asserting that a generated asset exists: the ~40 icons
 * `flutter_launcher_icons` just wrote are untracked until the user commits, so
 * an index-based check reports every one of them missing.
 */
const onDisk = async (ctx: CheckCtx, path: string): Promise<boolean> =>
  await Bun.file(join(ctx.root, path)).exists();

const pass = (name: string, detail?: string): CheckResult => ({
  name,
  status: "pass",
  ...(detail === undefined ? {} : { detail }),
});
const fail = (name: string, detail: string, hits?: string[]): CheckResult => ({
  name,
  status: "fail",
  detail,
  ...(hits === undefined ? {} : { hits }),
});
const skip = (name: string, detail: string): CheckResult => ({
  name,
  status: "skip",
  detail,
});

// ---------------------------------------------------------------------------
// Attribution allowlist
// ---------------------------------------------------------------------------

/**
 * Where the previous brand's name is *supposed* to survive. Two rules run
 * against this list, in opposite directions: nothing outside it may mention the
 * old brand, and - when attribution is enabled - something inside it must.
 * The second half is what stops a well-meaning cleanup from quietly deleting
 * the upstream credit.
 */
const ATTRIBUTION_ALLOWLIST: readonly RegExp[] = [
  /^packages\/brand\//,
  /(^|\/)ATTRIBUTION\.md$/,
  /(^|\/)LICENSE(\.[A-Za-z]+)?$/,
  /(^|\/)NOTICE$/,
  /(^|\/)CHANGELOG\.md$/,
  /(^|\/)attribution\.dart$/,
  // Legacy MCAP schema aliases live here on purpose when compat is kept.
  /(^|\/)ros2_message_decoder\.dart$/,
  // Lockfiles are regenerated, not rewritten; they lag until `bun install`.
  /^bun\.lock$/,
  /(^|\/)pubspec\.lock$/,
  /(^|\/)Podfile\.lock$/,
];

const isAllowed = (path: string): boolean =>
  ATTRIBUTION_ALLOWLIST.some((pattern) => pattern.test(path));

const ATTRIBUTION_START = "<!-- brand:attribution:start -->";
const ATTRIBUTION_END = "<!-- brand:attribution:end -->";

/** Blanks the marked credits region, preserving line numbers for reporting. */
const stripAttributionBlock = (text: string): string => {
  const start = text.indexOf(ATTRIBUTION_START);
  const end = text.indexOf(ATTRIBUTION_END);
  if (start === -1 || end === -1 || end < start) {
    return text;
  }
  const block = text.slice(start, end + ATTRIBUTION_END.length);
  return (
    text.slice(0, start) +
    block.replace(/[^\n]/g, " ") +
    text.slice(end + ATTRIBUTION_END.length)
  );
};

// ---------------------------------------------------------------------------
// Token checks
// ---------------------------------------------------------------------------

const checkNoStaleTokens = async (ctx: CheckCtx): Promise<CheckResult> => {
  const tokens = staleTokensOf(ctx.prev);
  const hits: string[] = [];

  for (const path of ctx.files.rewritable()) {
    if (isAllowed(path)) {
      continue;
    }
    // README.md is checked, but the credits block inside it is an attribution
    // carrier and names the upstream project on purpose. Blanking just that
    // region is more precise than allowlisting the whole file, which would let
    // a genuinely missed token hide anywhere else in it.
    const text = stripAttributionBlock(await ctx.files.read(path));
    for (const hit of findStale(text, tokens)) {
      hits.push(`${path}:${hit.line}:${hit.column}  ${hit.token}  ${DIM}${hit.excerpt}${RESET}`);
    }
  }

  return hits.length === 0
    ? pass("no stale brand tokens outside the attribution allowlist")
    : fail(
        "no stale brand tokens outside the attribution allowlist",
        `${hits.length} occurrence(s) of the previous brand survived`,
        hits.slice(0, 40)
      );
};

const checkAttributionSurvives = async (ctx: CheckCtx): Promise<CheckResult> => {
  const name = "upstream attribution was not scrubbed";
  if (!ctx.next.attribution.enabled) {
    return skip(name, "attribution is disabled in brand.json");
  }

  const wanted = ctx.next.attribution.upstreamName;

  // Deliberately narrow. Checking "does the old name appear anywhere in the
  // allowlist" would pass on a stray mention in a changelog or in the engine's
  // own test fixtures - which is not attribution, it is a coincidence. Only the
  // files whose job is to carry the credit count.
  const carriers = [
    "apps/mobile/lib/src/core/config/constants/attribution.dart",
    "packages/brand/ATTRIBUTION.md",
    "README.md",
  ].filter((path) => ctx.files.exists(path));

  const found: string[] = [];
  for (const path of carriers) {
    if ((await ctx.files.read(path)).includes(wanted)) {
      found.push(path);
    }
  }

  return found.length > 0
    ? pass(name, found.join(", "))
    : fail(
        name,
        `attribution.enabled is true but "${wanted}" appears in none of the attribution carriers ` +
          `(${carriers.join(", ") || "none present"}). Re-run \`bun run brand:apply\` to regenerate them.`
      );
};

// ---------------------------------------------------------------------------
// Structural checks
// ---------------------------------------------------------------------------

const checkKotlinPackages = async (ctx: CheckCtx): Promise<CheckResult> => {
  const name = "every Kotlin package declaration matches its directory";
  const hits: string[] = [];

  for (const path of ctx.files.all()) {
    if (!path.endsWith(".kt")) {
      continue;
    }
    const marker = "/src/main/kotlin/";
    const at = path.indexOf(marker);
    if (at === -1) {
      continue;
    }
    const relative = path.slice(at + marker.length);
    const expected = relative.slice(0, relative.lastIndexOf("/")).split("/").join(".");
    const declared = /^package\s+([A-Za-z0-9_.]+)/m.exec(await ctx.files.read(path))?.[1];
    if (declared !== expected) {
      hits.push(`${path}: declares "${declared}", directory implies "${expected}"`);
    }
  }

  return hits.length === 0
    ? pass(name, `${ctx.files.all().filter((p) => p.endsWith(".kt")).length} files`)
    : fail(name, `${hits.length} mismatch(es)`, hits);
};

const checkDartPackage = async (ctx: CheckCtx): Promise<CheckResult> => {
  const name = "the Dart package name and its imports agree";
  const expected = ctx.next.identifiers.dartPackage;
  const pubspec = await ctx.files.read("apps/mobile/pubspec.yaml");
  const declared = /^name:\s*(\S+)\s*$/m.exec(pubspec)?.[1];

  if (declared !== expected) {
    return fail(name, `pubspec declares "${declared}", brand.json says "${expected}"`);
  }

  let current = 0;
  let stale = 0;
  const staleFiles: string[] = [];
  for (const path of ctx.files.under("apps/mobile/lib")) {
    const text = await ctx.files.read(path);
    if (text.includes(`package:${expected}/`)) {
      current += 1;
    }
    if (text.includes(`package:${ctx.prev.identifiers.dartPackage}/`)) {
      stale += 1;
      staleFiles.push(path);
    }
  }

  return stale === 0
    ? pass(name, `${current} files import package:${expected}/`)
    : fail(name, `${stale} file(s) still import the old package`, staleFiles.slice(0, 20));
};

/**
 * The single most valuable check in the file. Upstream shipped three different
 * app identifiers - the Android applicationId, the iOS PRODUCT_BUNDLE_IDENTIFIER
 * and the id in the Play Store update URL - and they did not match each other.
 * Nothing in either build catches that; it surfaced as an in-app updater that
 * linked to a stranger's listing.
 *
 * `urls.playStoreAppId` is now opt-in, so a null one is not a mismatch: it means
 * the fork has not published on Play and the Android update check is off. When
 * it *is* set it must equal the bundle id, because the store lookup keys off the
 * id the running app was built with, not off this value.
 */
const checkAppIdConsistency = async (ctx: CheckCtx): Promise<CheckResult> => {
  const name = "Android, iOS and Play Store app ids agree";
  const expected = ctx.next.identifiers.bundleId;
  const found: Record<string, string | undefined> = {};

  const gradle = await ctx.files.read("apps/mobile/android/app/build.gradle.kts");
  found.androidApplicationId = /applicationId\s*=\s*"([^"]+)"/.exec(gradle)?.[1];
  found.androidNamespace = /namespace\s*=\s*"([^"]+)"/.exec(gradle)?.[1];

  const pbxproj = await ctx.files.read("apps/mobile/ios/Runner.xcodeproj/project.pbxproj");
  const bundleIds = new Set(
    [...pbxproj.matchAll(/PRODUCT_BUNDLE_IDENTIFIER\s*=\s*([^;]+);/g)].map((m) =>
      (m[1] ?? "").trim()
    )
  );
  // The test target is legitimately `<bundleId>.RunnerTests`.
  const appBundleIds = [...bundleIds].filter((id) => !id.endsWith(".RunnerTests"));
  found.iosBundleId = appBundleIds[0];

  // After the seam refactor the Play Store URL lives in the generated
  // brand.dart, not at the call site - so look there first and fall back to the
  // call site for a tree that has not been seamed yet. An absent URL is only a
  // finding when the brand claims a Play listing.
  const playStoreSources = [
    "apps/mobile/lib/src/core/config/constants/brand.dart",
    "apps/mobile/lib/src/core/common/utils/app_update.dart",
  ];
  let playStoreId: string | undefined;
  for (const path of playStoreSources) {
    if (!(await onDisk(ctx, path))) {
      continue;
    }
    const id = /details\?id=([A-Za-z0-9_.]+)/.exec(
      await Bun.file(join(ctx.root, path)).text()
    )?.[1];
    if (id !== undefined) {
      playStoreId = id;
      break;
    }
  }
  if (ctx.next.urls.playStoreAppId !== null || playStoreId !== undefined) {
    found.playStoreId = playStoreId;
  }

  const wrong = Object.entries(found).filter(([, value]) => value !== expected);
  if (appBundleIds.length > 1) {
    wrong.push(["iosBundleId(multiple)", appBundleIds.join(", ")]);
  }

  return wrong.length === 0
    ? pass(name, expected)
    : fail(
        name,
        `expected every id to be "${expected}"`,
        wrong.map(([key, value]) => `${key} = ${value ?? "<not found>"}`)
      );
};

const APP_UPDATE_PATH = "apps/mobile/lib/src/core/common/utils/app_update.dart";

/**
 * The in-app updater is off unless the fork says where its releases live. That
 * only holds if `app_update.dart` reads its three URLs from `brand.json` and
 * carries no URL of its own - a stray literal here is an updater pointing at
 * somebody else's app, which is exactly the bug this knob exists to prevent.
 */
const checkUpdateFeedWired = async (ctx: CheckCtx): Promise<CheckResult> => {
  const name = "the in-app updater reads its URLs from brand.json";
  const { playStoreAppId, appStoreId, updateFeed } = ctx.next.urls;
  const configured = [playStoreAppId, appStoreId, updateFeed].filter(
    (value) => value !== null
  );

  const source = await ctx.files.read(APP_UPDATE_PATH);
  const constants = ["_updateFeedUrl", "_playStoreUrl", "_appStoreUrl"];
  const hits: string[] = [];

  for (const constant of constants) {
    const value = new RegExp(
      `static const String\\? ${constant} = ([^;]+);`
    ).exec(source)?.[1];
    if (value === undefined) {
      hits.push(`${constant} = <not found> - the update seam no longer matches`);
    } else if (value !== "null" && !value.startsWith("Brand.")) {
      hits.push(`${constant} = ${value} - must be null or a Brand constant`);
    }
  }

  // Anything that looks like a URL at the call site bypasses brand.json.
  for (const [literal] of source.matchAll(/"https?:\/\/[^"]*"/g)) {
    hits.push(`${literal} - hoist this into brand.json`);
  }

  if (hits.length > 0) {
    return fail(name, `${hits.length} problem(s) in ${APP_UPDATE_PATH}`, hits);
  }

  if (configured.length === 0) {
    return pass(
      name,
      "no store id and no update feed - in-app update checks are off"
    );
  }

  // Configured: the URLs must actually have been generated into brand.dart.
  if (!(await onDisk(ctx, BRAND_DART_PATH))) {
    return fail(
      name,
      `${configured.length} update URL(s) configured but ${BRAND_DART_PATH} ` +
        `does not exist - run \`bun run brand:apply\``
    );
  }
  const brandDart = await Bun.file(join(ctx.root, BRAND_DART_PATH)).text();
  const missing = configured.filter((value) => !brandDart.includes(value));

  return missing.length === 0
    ? pass(name, `${configured.length} update URL(s) wired`)
    : fail(
        name,
        `${BRAND_DART_PATH} is stale - run \`bun run brand:apply\``,
        missing.map((value) => `${value} is missing from brand.dart`)
      );
};

/**
 * `BGTaskScheduler` silently refuses to launch a task whose identifier is not
 * declared in Info.plist. A mismatch here means background upload finalisation
 * stops happening, with no error anywhere.
 */
const checkBackgroundTaskId = async (ctx: CheckCtx): Promise<CheckResult> => {
  const name = "the iOS background task id is declared in Info.plist";
  const plist = await ctx.files.read("apps/mobile/ios/Runner/Info.plist");
  const declared = /<key>BGTaskSchedulerPermittedIdentifiers<\/key>\s*<array>\s*<string>([^<]+)<\/string>/.exec(
    plist
  )?.[1];

  const swift = await ctx.files.read(
    "apps/mobile/ios/Runner/background_uploader/manager/ChunkWindowManager.swift"
  );
  const registered = /backgroundTaskIdentifier\s*=\s*"([^"]+)"/.exec(swift)?.[1];

  if (declared === undefined || registered === undefined) {
    return fail(name, `could not locate both ids (plist=${declared}, swift=${registered})`);
  }
  return declared === registered
    ? pass(name, declared)
    : fail(name, `Info.plist declares "${declared}" but Swift registers "${registered}"`);
};

const checkMcapSchemas = async (ctx: CheckCtx): Promise<CheckResult> => {
  const name = "MCAP schema names agree across Swift, Kotlin and Dart";
  const recorder = `packages/${ctx.next.identifiers.recorder.dartPackage}`;
  const swiftPath = `${recorder}/ios/${ctx.next.identifiers.recorder.dartPackage}/Sources/${ctx.next.identifiers.recorder.dartPackage}/data/ROS2SchemaDefinitions.swift`;
  const kotlinPath = `${recorder}/android/src/main/kotlin/${ctx.next.identifiers.recorder.kotlinPackage.split(".").join("/")}/data/ROS2SchemaDefinitions.kt`;
  const dartPath = "apps/mobile/lib/src/services/mcap_reader/cdr/ros2_message_decoder.dart";

  for (const path of [swiftPath, kotlinPath, dartPath]) {
    if (!ctx.files.exists(path)) {
      return skip(name, `${path} not found`);
    }
  }

  const namespace = ctx.next.identifiers.mcapSchemaNamespace;
  const pattern = new RegExp(`${namespace}/msg/([A-Za-z0-9_]+)`, "g");
  const namesIn = (text: string): Set<string> =>
    new Set([...text.matchAll(pattern)].map((m) => m[1] ?? ""));

  const swift = namesIn(await ctx.files.read(swiftPath));
  const kotlin = namesIn(await ctx.files.read(kotlinPath));
  const dart = namesIn(await ctx.files.read(dartPath));

  const missing: string[] = [];
  for (const produced of [...swift, ...kotlin]) {
    if (!dart.has(produced)) {
      missing.push(`producers emit "${namespace}/msg/${produced}" but the Dart decoder has no case for it`);
    }
  }
  // Deliberately NOT asserting swift.size === kotlin.size. Upstream is already
  // asymmetric - Swift declares TrackingState, DeviceMetrics and ImuIntrinsics
  // while Kotlin declares only DeviceMetrics, because Android does not emit the
  // other two. That is a product fact, not a rebrand error. The invariant that
  // does matter is that every schema a producer emits has a decoder case.

  // Compat: the decoder should still accept the previous namespace.
  if (ctx.next.compat.keepMcapAliases && ctx.prev.identifiers.mcapSchemaNamespace !== namespace) {
    const dartText = await ctx.files.read(dartPath);
    if (!dartText.includes(`${ctx.prev.identifiers.mcapSchemaNamespace}/msg/`)) {
      missing.push(
        `compat.keepMcapAliases is true but the decoder no longer accepts "${ctx.prev.identifiers.mcapSchemaNamespace}/msg/*" - old recordings will not decode`
      );
    }
  }

  return missing.length === 0
    ? pass(name, `${swift.size} schema(s)`)
    : fail(name, `${missing.length} problem(s)`, missing);
};

const checkXcassets = async (ctx: CheckCtx): Promise<CheckResult> => {
  const name = "every .xcassets Contents.json parses and its files exist";
  const problems: string[] = [];

  for (const path of ctx.files.all()) {
    if (!path.endsWith("/Contents.json") || !path.includes(".xcassets/")) {
      continue;
    }
    let parsed: { images?: Array<{ filename?: string }> };
    try {
      parsed = JSON.parse(await ctx.files.read(path)) as typeof parsed;
    } catch (cause) {
      problems.push(`${path}: invalid JSON (${cause instanceof Error ? cause.message : cause})`);
      continue;
    }
    const dir = path.slice(0, path.lastIndexOf("/"));
    for (const image of parsed.images ?? []) {
      if (
        image.filename !== undefined &&
        !(await onDisk(ctx, `${dir}/${image.filename}`))
      ) {
        problems.push(`${path}: references missing file "${image.filename}"`);
      }
    }
  }

  return problems.length === 0
    ? pass(name)
    : fail(name, `${problems.length} problem(s)`, problems.slice(0, 20));
};

const checkStoryboard = async (ctx: CheckCtx): Promise<CheckResult> => {
  const name = "LaunchScreen.storyboard references only existing image sets";
  const path = "apps/mobile/ios/Runner/Base.lproj/LaunchScreen.storyboard";
  if (!ctx.files.exists(path)) {
    return skip(name, "storyboard not found");
  }

  const text = await ctx.files.read(path);
  const problems: string[] = [];

  // The <resources> block at the bottom is a cache Xcode maintains; every
  // image named there must have a matching .imageset or the launch screen
  // renders blank on device while looking fine in Interface Builder.
  for (const match of text.matchAll(/<image name="([^"]+)"/g)) {
    const imageName = match[1];
    if (imageName === undefined) {
      continue;
    }
    const expected = `apps/mobile/ios/Runner/Assets.xcassets/${imageName}.imageset/Contents.json`;
    if (!(await onDisk(ctx, expected))) {
      problems.push(`storyboard references image "${imageName}" but ${expected} is missing`);
    }
  }

  for (const match of text.matchAll(/<namedColor name="([^"]+)"/g)) {
    const colorName = match[1];
    if (colorName === undefined) {
      continue;
    }
    const expected = `apps/mobile/ios/Runner/Assets.xcassets/${colorName}.colorset/Contents.json`;
    if (!(await onDisk(ctx, expected))) {
      problems.push(`storyboard references colour "${colorName}" but ${expected} is missing`);
    }
  }

  return problems.length === 0
    ? pass(name)
    : fail(name, `${problems.length} problem(s)`, problems);
};

const checkNoOrphanedPackageRoots = (ctx: CheckCtx): CheckResult => {
  const name = "no files remain under the previous Kotlin package root";
  const staleRoot = ctx.prev.identifiers.kotlinPackage.split(".")[0];
  if (staleRoot === undefined || staleRoot === ctx.next.identifiers.kotlinPackage.split(".")[0]) {
    return skip(name, "the package root did not change");
  }
  const orphans = ctx.files
    .all()
    .filter((path) => path.includes(`/src/main/kotlin/${staleRoot}/`));

  return orphans.length === 0
    ? pass(name)
    : fail(name, `${orphans.length} file(s) still under /kotlin/${staleRoot}/`, orphans.slice(0, 20));
};

// ---------------------------------------------------------------------------
// Branding-reached-the-product checks
// ---------------------------------------------------------------------------

/**
 * The in-app marks are not upstream's any more.
 *
 * This is the check that would have caught the engine's worst failure mode: a
 * fork that supplied only `assets.iconSource` got its own launcher icon, a
 * warning it never read, and a splash screen, sign-in sheet and onboarding
 * modal still showing Stera's logo. Comparing bytes is the only way to know -
 * the file has the right name and the right dimensions either way.
 */
const checkLogoArtwork = async (ctx: CheckCtx): Promise<CheckResult> => {
  const name = "in-app logo artwork is not upstream's";
  const stale: string[] = [];
  let checked = 0;

  for (const [path, expected] of Object.entries(UPSTREAM_ASSET_HASHES)) {
    const file = Bun.file(join(ctx.root, path));
    if (!(await file.exists())) {
      continue;
    }
    checked += 1;
    const digest = new Bun.CryptoHasher("sha256")
      .update(new Uint8Array(await file.arrayBuffer()))
      .digest("hex");
    if (digest === expected) {
      stale.push(path);
    }
  }

  if (checked === 0) {
    return skip(name, "no in-app logo assets on disk");
  }
  return stale.length === 0
    ? pass(name, `${checked} asset(s) replaced`)
    : fail(
        name,
        `${stale.length} of ${checked} still byte-identical to upstream's artwork. ` +
          `Set assets.iconSource (the logo falls back to it) or assets.logoLight / assets.logoDark, then re-run brand:apply.`,
        stale
      );
};

/**
 * `colors.dart` reads from `BrandPalette` rather than carrying literals.
 *
 * A literal left behind is a token that `brand.json` cannot reach - exactly the
 * state the whole palette rewrite exists to end - and it is invisible until
 * somebody wonders why one surface did not change colour.
 */
const checkPaletteWired = async (ctx: CheckCtx): Promise<CheckResult> => {
  const name = "every colour token resolves through BrandPalette";
  if (!(await onDisk(ctx, BRAND_PALETTE_PATH))) {
    return skip(name, "brand_palette.dart not generated yet");
  }
  if (!ctx.files.exists(COLORS_DART_PATH)) {
    return skip(name, "colors.dart not found");
  }

  const source = await ctx.files.read(COLORS_DART_PATH);
  const leftovers: string[] = [];
  for (const token of TOKEN_NAMES) {
    const pattern = new RegExp(`\\b${token}:\\s*const Color\\(0x[0-9A-Fa-f]{8}\\)`);
    if (pattern.test(source)) {
      leftovers.push(token);
    }
  }

  return leftovers.length === 0
    ? pass(name, `${TOKEN_NAMES.length} token(s)`)
    : fail(
        name,
        `${leftovers.length} token(s) still hold a literal colour, so brand.json cannot change them`,
        leftovers
      );
};

/** Every family the app names is actually declared in the manifest. */
const checkFontsDeclared = async (ctx: CheckCtx): Promise<CheckResult> => {
  const name = "every typeface the app names is declared in pubspec.yaml";
  if (!(await onDisk(ctx, BRAND_FONTS_PATH))) {
    return skip(name, "brand_fonts.dart not generated yet");
  }

  const generated = await Bun.file(join(ctx.root, BRAND_FONTS_PATH)).text();
  const families = [...generated.matchAll(/static const String \w+ = "([^"]+)";/g)].map(
    (match) => match[1] as string
  );
  if (families.length === 0) {
    return fail(name, "brand_fonts.dart declares no families");
  }

  const pubspec = await ctx.files.read("apps/mobile/pubspec.yaml");
  const missing = families.filter(
    (family) => !new RegExp(`^\\s*- family:\\s*${family}\\s*$`, "m").test(pubspec)
  );

  return missing.length === 0
    ? pass(name, families.join(", "))
    : fail(
        name,
        "Flutter renders an unknown family as the system face without an error, " +
          "so this would ship as silently wrong typography",
        missing
      );
};

/**
 * The theme directory itself. These files are the *definition* of the tokens,
 * so they are the one place a literal colour or radius is not drift.
 */
const THEME_DIR = "apps/mobile/lib/src/core/theme/";

/** A widget file: in the app's tree, and not part of the theme definition. */
const isWidgetSource = (path: string): boolean =>
  isRadiusSweepTarget(path) && !path.startsWith(THEME_DIR);

/** The radius sweep reached the whole widget tree. */
const checkShapeWired = async (ctx: CheckCtx): Promise<CheckResult> => {
  const name = "corner radii follow theme.shape";
  if (!(await onDisk(ctx, BRAND_SHAPE_PATH))) {
    return skip(name, "brand_shape.dart not generated yet");
  }

  const leftovers: string[] = [];
  for (const path of ctx.files.all()) {
    if (!isRadiusSweepTarget(path)) {
      continue;
    }
    const source = await ctx.files.read(path);
    for (const match of source.matchAll(
      /\b(?:BorderRadius|Radius)\.circular\(\s*(\d+(?:\.\d+)?)\s*\)/g
    )) {
      const value = Number.parseFloat(match[1] as string);
      if (snapToStep(value) !== null) {
        leftovers.push(`${path}: ${value}px`);
      }
    }
  }

  return leftovers.length === 0
    ? pass(name)
    : fail(
        name,
        `${leftovers.length} on-scale radius literal(s) were not converted - ` +
          `re-run brand:apply, or promote them by hand if they are deliberate`,
        leftovers.slice(0, 20)
      );
};

/**
 * The type scale reached the whole widget tree.
 *
 * Sibling of `checkShapeWired`, and it exists for the sharper version of the
 * same failure: a fork can change `fonts.body` and get a new typeface at
 * upstream's exact sizes and weights, which is the most convincing way to look
 * like you rebranded without having done it. `app_text_theme.dart` is exempt -
 * it is the file that turns the scale into named styles.
 */
/**
 * The spacing sweep reached the whole widget tree.
 *
 * Sibling of `checkShapeWired`. Density is the quietest of the four axes: a fork
 * that misses it keeps upstream's exact rhythm under its own colours and type,
 * and nobody can name why the app still feels like the one it forked.
 */
const checkSpaceWired = async (ctx: CheckCtx): Promise<CheckResult> => {
  const name = "gaps and pads follow theme.space";
  if (!(await onDisk(ctx, BRAND_SPACE_PATH))) {
    return skip(name, "brand_space.dart not generated yet");
  }

  const leftovers: string[] = [];
  for (const path of ctx.files.all()) {
    if (!isRadiusSweepTarget(path) || path.startsWith(THEME_DIR)) {
      continue;
    }
    const source = await ctx.files.read(path);
    const patterns = [
      /EdgeInsets(?:\.directional)?\.(?:all|symmetric|only|fromLTRB)\(([^()]*)\)/g,
      /SizedBox\((?:height|width): *(\d+(?:\.\d+)?)/g,
      /spacing: (\d+(?:\.\d+)?)(?![\w.])/g,
    ];
    for (const pattern of patterns) {
      for (const match of source.matchAll(pattern)) {
        for (const raw of (match[1] as string).matchAll(/(?<![\w.])(\d+(?:\.\d+)?)(?![\w.])/g)) {
          const value = Number.parseFloat(raw[1] as string);
          if (snapToSpaceStep(value) !== null) {
            leftovers.push(`${path}: ${value}px`);
          }
        }
      }
    }
  }

  return leftovers.length === 0
    ? pass(name)
    : fail(
        name,
        `${leftovers.length} on-scale spacing literal(s) were not converted - ` +
          `route them through AppSpacing`,
        leftovers.slice(0, 20)
      );
};

const checkTypeWired = async (ctx: CheckCtx): Promise<CheckResult> => {
  const name = "font sizes and weights follow theme.type";
  if (!(await onDisk(ctx, BRAND_TYPE_PATH))) {
    return skip(name, "brand_type.dart not generated yet");
  }

  const leftovers: string[] = [];
  for (const path of ctx.files.all()) {
    if (!isRadiusSweepTarget(path) || path.startsWith(THEME_DIR)) {
      continue;
    }
    const source = await ctx.files.read(path);
    for (const match of source.matchAll(/\bfontSize:\s*(\d+(?:\.\d+)?)/g)) {
      const value = Number.parseFloat(match[1] as string);
      if (snapToTypeStep(value) !== null) {
        leftovers.push(`${path}: ${value}px`);
      }
    }
    for (const match of source.matchAll(/\bFontWeight\.w(\d00)\b/g)) {
      const value = Number.parseInt(match[1] as string, 10);
      if (snapToWeightRole(value) !== null) {
        leftovers.push(`${path}: FontWeight.w${value}`);
      }
    }
  }

  return leftovers.length === 0
    ? pass(name)
    : fail(
        name,
        `${leftovers.length} on-scale type literal(s) were not converted - ` +
          `route them through AppType, or through a named style on context.textTheme`,
        leftovers.slice(0, 20)
      );
};

/**
 * No widget spells a design value as a literal.
 *
 * The other checks ask "did the rebrand land". This one asks "can it land
 * *next* time", which is the failure the engine kept losing to: a rebrand is
 * verified green, someone adds a card with `BorderRadius.circular(12)` and
 * `Colors.white` in it because that is what the surrounding code used to look
 * like, and the next fork's shape style and palette quietly skip that card. One
 * widget off the tokens is invisible in review and obvious in the product.
 *
 * `Colors.transparent` is allowed: it is the absence of a colour, not a choice
 * of one, and no brand has an opinion about it. `apps/mobile/lib/src/core/theme/`
 * is allowed because it is where the tokens are defined.
 */
const checkTokensOnly = async (ctx: CheckCtx): Promise<CheckResult> => {
  const name = "no widget hard-codes a colour, a radius, a type value or a gap";

  const patterns: ReadonlyArray<[RegExp, string]> = [
    [/\bfontSize:\s*\d/g, "literal font size - use AppType or context.textTheme"],
    [
      /EdgeInsets(?:\.directional)?\.(?:all|symmetric|only|fromLTRB)\([^()]*\d[^()]*\)/g,
      "literal padding - use AppSpacing",
    ],
    [/SizedBox\((?:height|width): *\d/g, "literal gap - use AppSpacing"],
    [/\bFontWeight\.w\d00\b/g, "literal font weight - use AppType"],
    [
      /\b(?:BorderRadius|Radius)\.circular\(\s*\d/g,
      "literal radius - use AppRadii",
    ],
    [/\bColor\(0x[0-9A-Fa-f]+\)/g, "literal colour - use context.colors"],
    [
      /\bColor\.from(?:ARGB|RGBO)\(/g,
      "literal colour - use context.colors",
    ],
    [
      /\bColors\.(?!transparent\b)[a-z]\w*/g,
      "Flutter palette colour - use context.colors",
    ],
  ];

  const hits: string[] = [];
  for (const path of ctx.files.all()) {
    if (!isWidgetSource(path)) {
      continue;
    }
    const source = await ctx.files.read(path);
    // Doc comments name these constructs to explain why they are banned, and a
    // comment cannot paint anything.
    const code = source
      .replace(/^\s*\/\/.*$/gm, "")
      .replace(/\/\*[\s\S]*?\*\//g, "");

    for (const [pattern, why] of patterns) {
      for (const match of code.matchAll(pattern)) {
        hits.push(`${path}: ${match[0]} (${why})`);
      }
    }
  }

  return hits.length === 0
    ? pass(name, "every widget reads the design tokens")
    : fail(
        name,
        `${hits.length} hard-coded design value(s) - these do not follow ` +
          `brand.json, so a fork's theme will skip exactly these widgets`,
        hits.slice(0, 20)
      );
};

const structuralChecks = [
  checkKotlinPackages,
  checkDartPackage,
  checkAppIdConsistency,
  checkUpdateFeedWired,
  checkBackgroundTaskId,
  checkMcapSchemas,
  checkXcassets,
  checkStoryboard,
  checkLogoArtwork,
  checkPaletteWired,
  checkFontsDeclared,
  checkShapeWired,
  checkTypeWired,
  checkSpaceWired,
  checkTokensOnly,
];

// ---------------------------------------------------------------------------
// Toolchain checks
// ---------------------------------------------------------------------------

const runCommand = async (
  name: string,
  cmd: readonly string[],
  cwd: string
): Promise<CheckResult> => {
  const proc = Bun.spawn([...cmd], { cwd, stdout: "pipe", stderr: "pipe" });
  const [stdout, stderr, code] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
    proc.exited,
  ]);
  if (code === 0) {
    return pass(name);
  }
  const output = `${stdout}\n${stderr}`.trim().split("\n");
  return fail(name, `exit ${code}`, output.slice(-25));
};

const toolchainChecks = async (root: string): Promise<CheckResult[]> => {
  const results = [
    await runCommand("bun install", ["bun", "install"], root),
    await runCommand("bun run check-types", ["bun", "run", "check-types"], root),
    await runCommand(
      "flutter pub get (mobile)",
      ["flutter", "pub", "get"],
      join(root, "apps/mobile")
    ),
  ];

  // `.env` is gitignored and listed as a Flutter asset, so it is absent in every
  // fresh clone and `dart analyze` fails on it. That is a repo setup step, not a
  // rebrand defect - failing the whole verification on it would train people to
  // ignore a red result.
  const analyzeName = "dart analyze (mobile)";
  if (await Bun.file(join(root, "apps/mobile/.env")).exists()) {
    results.push(
      await runCommand(analyzeName, ["dart", "analyze"], join(root, "apps/mobile"))
    );
  } else {
    results.push(
      skip(
        analyzeName,
        "apps/mobile/.env is missing - copy apps/mobile/.env.example to .env first, then re-run"
      )
    );
  }

  return results;
};

// ---------------------------------------------------------------------------
// Reporting
// ---------------------------------------------------------------------------

const report = (results: readonly CheckResult[]): number => {
  let failures = 0;
  for (const result of results) {
    if (result.status === "pass") {
      console.log(
        `${GREEN}pass${RESET}  ${result.name}${result.detail === undefined ? "" : ` ${DIM}(${result.detail})${RESET}`}`
      );
    } else if (result.status === "skip") {
      console.log(`${YELLOW}skip${RESET}  ${result.name} ${DIM}(${result.detail})${RESET}`);
    } else {
      failures += 1;
      console.log(`${RED}FAIL${RESET}  ${result.name}`);
      if (result.detail !== undefined) {
        console.log(`      ${result.detail}`);
      }
      for (const hit of result.hits ?? []) {
        console.log(`      ${hit}`);
      }
    }
  }
  return failures;
};

const main = async (): Promise<number> => {
  const argv = Bun.argv.slice(2);
  const full = argv.includes("--full");
  const root = join(import.meta.dir, "..", "..");

  const state = await readState(root);
  if (state === null) {
    // Nothing has been rebranded, so every check that compares the tree
    // against an applied brand has nothing to compare. One check does not:
    // whether the widgets read their design values from the tokens at all.
    // That is a property of this repository, true or false before any fork
    // exists, and it is the check whose failure a fork inherits - so it runs
    // here, and upstream CI gets to keep it green.
    console.log(
      `${YELLOW}skip${RESET}  no packages/brand/.applied.json - nothing has been rebranded yet; running the design-token check only.`
    );
    const failed = report([
      await checkTokensOnly({
        root,
        files: await createFileIndex(root),
        prev: UPSTREAM_BRAND,
        next: UPSTREAM_BRAND,
      }),
    ]);
    return failed === 0 ? 0 : 1;
  }

  const ctx: CheckCtx = {
    root,
    files: await createFileIndex(root),
    // After a run, the tree holds `state.brand`. Stale-token checks look for
    // whatever came before it, which the ledger does not record - so compare
    // against upstream, the only brand the tree could have held earlier.
    prev: UPSTREAM_BRAND,
    next: state.brand,
  };

  const results: CheckResult[] = [];
  results.push(await checkNoStaleTokens(ctx));
  results.push(await checkAttributionSurvives(ctx));
  results.push(checkNoOrphanedPackageRoots(ctx));
  for (const check of structuralChecks) {
    results.push(await check(ctx));
  }
  if (full) {
    console.log(`${DIM}running toolchains...${RESET}`);
    results.push(...(await toolchainChecks(root)));
  }

  const failures = report(results);
  console.log(
    failures === 0
      ? `\n${GREEN}All ${results.length} check(s) passed.${RESET}`
      : `\n${RED}${failures} of ${results.length} check(s) failed.${RESET}`
  );
  if (!full) {
    console.log(`${DIM}Run with --full to also exercise bun, flutter and dart.${RESET}`);
  }
  return failures === 0 ? 0 : 1;
};

process.exit(await main());
