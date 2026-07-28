#!/usr/bin/env bun
/**
 * Renders `brand.json` to a page you can look at, without applying anything.
 *
 *   bun run brand:preview            write packages/brand/preview.html
 *   bun run brand:preview --open     ... and open it
 *
 * This exists because the rebrand used to be unreviewable until it was done.
 * The dry run prints how many files will change, which says nothing about
 * whether the accent works against the app's greys, whether a dark wordmark
 * disappears on the dark splash, or what the launcher icon looks like under an
 * Android circle mask. Now the loop is: edit brand.json, preview, look, repeat -
 * and `brand:apply` becomes the boring last step rather than the leap.
 *
 * It reads only. It never writes into `apps/`, never needs `sharp`, and works
 * on a dirty tree, so it is safe to run as often as you like.
 */

import { join } from "node:path";

import { BrandConfigError, derive } from "./lib/derive.ts";
import { UPSTREAM_FONT_FILES } from "./lib/fonts.ts";
import { monogramSvg } from "./lib/raster.ts";
import { buildPreviewHtml, previewSummary } from "./lib/previewhtml.ts";
import type { EmbeddedFont, PreviewAssets } from "./lib/previewhtml.ts";
import { readState } from "./lib/state.ts";
import { UPSTREAM_BRAND } from "./lib/upstream.ts";
import type { Brand, BrandInput } from "./lib/types.ts";

const BRAND_PATH = "packages/brand/brand.json";
const OUTPUT_PATH = "packages/brand/preview.html";

const USAGE = `
Usage: bun run packages/brand/preview.ts [options]

Options:
  --brand=<path>   Read this config instead of ${BRAND_PATH}.
  --out=<path>     Write here instead of ${OUTPUT_PATH}.
  --open           Open the result when it is written.
  -h, --help       Show this message.
`.trim();

const RED = "[31m";
const YELLOW = "[33m";
const DIM = "[2m";
const RESET = "[0m";

// ---------------------------------------------------------------------------
// Embedding
// ---------------------------------------------------------------------------

const MIME: Record<string, string> = {
  png: "image/png",
  jpg: "image/jpeg",
  jpeg: "image/jpeg",
  svg: "image/svg+xml",
  webp: "image/webp",
};

const extensionOf = (path: string): string =>
  (path.split(".").pop() ?? "").toLowerCase();

/**
 * Artwork as a data URI.
 *
 * SVG is embedded as text rather than rasterised, which is why the preview
 * needs no `sharp` and no `bun install`: the whole point is to be runnable
 * before you have committed to anything.
 */
const embedImage = async (
  root: string,
  repoRelative: string | null
): Promise<string | null> => {
  if (repoRelative === null) {
    return null;
  }
  const file = Bun.file(join(root, repoRelative));
  if (!(await file.exists())) {
    return null;
  }
  const extension = extensionOf(repoRelative);
  const mime = MIME[extension];
  if (mime === undefined) {
    return null;
  }
  const base64 = Buffer.from(await file.arrayBuffer()).toString("base64");
  return `data:${mime};base64,${base64}`;
};

const embedSvgText = (svg: string): string =>
  `data:image/svg+xml;base64,${Buffer.from(svg).toString("base64")}`;

/**
 * Latin subsets of the three faces the app ships, built for the guide.
 *
 * Preferred over the full variable TTFs where the family has not changed: EB
 * Garamond alone is 934 KB, and inlining four of those would make a 4 MB page
 * that takes a visible moment to paint. A fork's own faces are embedded whole,
 * since no subset of them exists.
 */
const FONT_SUBSETS: Record<string, string> = {
  EBGaramond: "packages/brand/docs/fonts/garamond.woff2",
  Geist: "packages/brand/docs/fonts/geist.woff2",
  GeistMono: "packages/brand/docs/fonts/geistmono.woff2",
};

const FONT_FORMATS: Record<string, string> = {
  woff2: "woff2",
  woff: "woff",
  ttf: "truetype",
  otf: "opentype",
};

const embedFonts = async (
  root: string,
  brand: Brand
): Promise<EmbeddedFont[]> => {
  const families = [
    brand.fonts.display,
    brand.fonts.body,
    brand.fonts.mono,
    brand.fonts.accent,
  ].filter((family, index, all) => all.indexOf(family) === index);

  const embedded: EmbeddedFont[] = [];

  for (const family of families) {
    // A fork's own file wins; then the subset; then the full upstream TTF.
    const supplied = brand.fonts.files[family]?.find(
      (source) => source.style === "normal"
    );
    const candidate =
      supplied?.path ??
      FONT_SUBSETS[family] ??
      UPSTREAM_FONT_FILES[family]?.[0]?.path ??
      null;

    if (candidate === null) {
      continue;
    }

    const file = Bun.file(join(root, candidate));
    if (!(await file.exists())) {
      console.warn(
        `${YELLOW}warn${RESET}  no font file for "${family}" at ${candidate} - the preview will fall back to a system face for it.`
      );
      continue;
    }

    const format = FONT_FORMATS[extensionOf(candidate)];
    if (format === undefined) {
      continue;
    }

    embedded.push({
      family,
      dataUri: `data:font/${extensionOf(candidate)};base64,${Buffer.from(
        await file.arrayBuffer()
      ).toString("base64")}`,
      format,
    });
  }

  return embedded;
};

const collectAssets = async (
  root: string,
  brand: Brand
): Promise<PreviewAssets> => {
  const icon =
    (await embedImage(root, brand.assets.iconSource)) ??
    // Exactly what `70-assets` would fall back to, so the preview shows the
    // placeholder the build would actually ship rather than an empty box.
    embedSvgText(monogramSvg(brand));

  return {
    icon,
    logoLight: (await embedImage(root, brand.assets.logoLight)) ?? icon,
    logoDark: (await embedImage(root, brand.assets.logoDark)) ?? icon,
  };
};

// ---------------------------------------------------------------------------
// Entry
// ---------------------------------------------------------------------------

const flagValue = (argv: readonly string[], prefix: string): string | null => {
  const hit = argv.find((arg) => arg.startsWith(prefix));
  return hit === undefined ? null : hit.slice(prefix.length);
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

  const root = join(import.meta.dir, "..", "..");
  const brandPath = flagValue(argv, "--brand=") ?? BRAND_PATH;
  const outputPath = flagValue(argv, "--out=") ?? OUTPUT_PATH;

  const configFile = Bun.file(join(root, brandPath));
  if (!(await configFile.exists())) {
    console.error(
      `${RED}error${RESET} ${brandPath} not found.\n\n` +
        `Run /whitelabel in Claude Code to generate it, or copy packages/brand/brand.example.json.`
    );
    return 1;
  }

  let brand: Brand;
  try {
    brand = derive((await configFile.json()) as BrandInput, {
      pubspecDependencies: await pubspecDependencies(root),
      upstream: UPSTREAM_BRAND,
      // Render the failing palette rather than refusing: seeing which pair
      // broke, and by how much, is the whole reason to run this.
      ignoreContrast: true,
    });
  } catch (cause) {
    if (cause instanceof BrandConfigError) {
      console.error(`${RED}error${RESET} ${cause.message}`);
      return 1;
    }
    throw cause;
  }

  const state = await readState(root);
  const html = buildPreviewHtml({
    brand,
    previous: state?.brand ?? UPSTREAM_BRAND,
    applied: state !== null,
    assets: await collectAssets(root, brand),
    fonts: await embedFonts(root, brand),
    generatedAt: new Date().toISOString().slice(0, 16).replace("T", " "),
  });

  const absolute = join(root, outputPath);
  await Bun.write(absolute, html);

  const summary = previewSummary(brand);
  console.log(
    `Wrote ${outputPath} (${Math.round(html.length / 1024)} KB, no external requests)\n` +
      `  ${brand.copy.appName} · ${brand.identifiers.bundleId}\n` +
      `  ${summary.changed} colour token(s) differ from upstream` +
      (summary.regressions > 0
        ? `\n  ${RED}${summary.regressions} contrast regression(s)${RESET} - brand:apply will refuse unless theme.allowLowContrast is set`
        : "") +
      (summary.inherited > 0
        ? `\n  ${DIM}${summary.inherited} contrast pair(s) inherited from upstream, not caused by this brand${RESET}`
        : "")
  );

  if (brand.assets.iconSource === null) {
    console.log(
      `  ${YELLOW}using the placeholder monogram${RESET} - set assets.iconSource to your artwork`
    );
  }
  if (
    brand.assets.logoDark !== null &&
    brand.assets.logoDark === brand.assets.logoLight
  ) {
    console.log(
      `  ${DIM}the dark-mode logo is the same artwork as the light one - check the splash and sign-in screens${RESET}`
    );
  }

  console.log(`\n  open ${outputPath}`);

  if (argv.includes("--open")) {
    Bun.spawn(["open", absolute], { stdout: "ignore", stderr: "ignore" });
  }

  return 0;
};

process.exit(await main());
