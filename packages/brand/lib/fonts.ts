/**
 * Typeface configuration.
 *
 * `fonts.display/body/mono/accent` have been in the schema since the engine was
 * written and, until now, no transform read them - the only mention anywhere
 * was a sentence in a TODO string. That is a shame, because swapping the
 * display face is the single cheapest change that makes a fork stop looking
 * like the app it was forked from.
 *
 * Two things make this safe to automate:
 *
 * - The app names its faces in exactly one file. All 21 `fontFamily:` literals
 *   live in `app_text_theme.dart`, so the seam is one file, not a sweep.
 * - Flutter fails *silently* on an unknown family - it falls back to the
 *   platform default and renders perfectly happily. So a family that is neither
 *   bundled upstream nor supplied by the fork is a hard error at derive time,
 *   not a warning nobody reads.
 */

import { basename } from "node:path";

import type { BrandFonts, FontSource } from "./types.ts";

export const FONT_ROLES = ["display", "body", "mono", "accent"] as const;
export type FontRole = (typeof FONT_ROLES)[number];

/**
 * Families declared in `apps/mobile/pubspec.yaml` upstream.
 *
 * `JetBrainsMono` and `GeistExtraBold` are declared but referenced nowhere in
 * Dart; they are listed here so that naming one is not an error, and so that
 * `replaceBundled` can tell "unused" from "unknown".
 */
export const UPSTREAM_FONT_FAMILIES: readonly string[] = [
  "EBGaramond",
  "Geist",
  "GeistMono",
  "Handjet",
  "JetBrainsMono",
  "GeistExtraBold",
];

/** Upstream family -> its asset files, for regenerating the pubspec block. */
export const UPSTREAM_FONT_FILES: Readonly<Record<string, readonly FontSource[]>> = {
  EBGaramond: [
    {
      path: "apps/mobile/assets/fonts/EBGaramond-VariableFont_wght.ttf",
      weight: null,
      style: "normal",
    },
    {
      path: "apps/mobile/assets/fonts/EBGaramond-Italic-VariableFont_wght.ttf",
      weight: null,
      style: "italic",
    },
  ],
  Geist: [
    {
      path: "apps/mobile/assets/fonts/Geist-VariableFont_wght.ttf",
      weight: null,
      style: "normal",
    },
  ],
  GeistMono: [
    {
      path: "apps/mobile/assets/fonts/GeistMono-VariableFont_wght.ttf",
      weight: null,
      style: "normal",
    },
  ],
  Handjet: [
    {
      path: "apps/mobile/assets/fonts/Handjet-VariableFont_ELGR,ELSH,wght.ttf",
      weight: null,
      style: "normal",
    },
  ],
  JetBrainsMono: [
    {
      path: "apps/mobile/assets/fonts/JetBrainsMono-VariableFont_wght.ttf",
      weight: null,
      style: "normal",
    },
  ],
  GeistExtraBold: [
    {
      path: "apps/mobile/assets/fonts/Geist-ExtraBold.ttf",
      weight: 800,
      style: "normal",
    },
  ],
};

const FAMILY_RE = /^[A-Za-z][A-Za-z0-9_]*$/;

/**
 * A Flutter family name is matched literally against the pubspec, so anything
 * with a space or a hyphen works only if both sides agree exactly. Requiring an
 * identifier-shaped name removes a class of "why is my font not applying"
 * where the two spellings differ by a character.
 */
export const isValidFamilyName = (family: string): boolean =>
  FAMILY_RE.test(family);

/** Where a supplied font file lands inside the app bundle. */
export const bundledFontPath = (source: FontSource): string =>
  `apps/mobile/assets/fonts/${basename(source.path)}`;


/**
 * The families that must end up declared in the pubspec: the four roles, plus
 * every upstream family unless the fork asked to drop the ones it is not using.
 *
 * Order is stable (roles first, then the remainder alphabetically) so the
 * generated block does not churn between runs.
 */
export const familiesToDeclare = (fonts: BrandFonts): string[] => {
  const roles = FONT_ROLES.map((role) => fonts[role]);
  const kept = new Set<string>(roles);

  if (!fonts.replaceBundled) {
    for (const family of UPSTREAM_FONT_FAMILIES) {
      kept.add(family);
    }
  }
  for (const family of Object.keys(fonts.files)) {
    kept.add(family);
  }

  const ordered: string[] = [];
  for (const family of roles) {
    if (!ordered.includes(family)) {
      ordered.push(family);
    }
  }
  for (const family of [...kept].sort()) {
    if (!ordered.includes(family)) {
      ordered.push(family);
    }
  }
  return ordered;
};

/**
 * Resolves a family to the files that back it: the fork's own if it supplied
 * any, otherwise the upstream asset already in the tree.
 */
export const filesForFamily = (
  fonts: BrandFonts,
  family: string
): readonly FontSource[] =>
  fonts.files[family] ?? UPSTREAM_FONT_FILES[family] ?? [];

/**
 * Renders the pubspec `fonts:` block, without the surrounding markers.
 *
 * Indentation is four/six spaces because the block sits under `flutter:` >
 * `fonts:`; YAML is whitespace-significant and Flutter's manifest parser
 * rejects the file outright if this is wrong.
 */
export const renderPubspecFonts = (fonts: BrandFonts): string => {
  const lines: string[] = [];
  for (const family of familiesToDeclare(fonts)) {
    const files = filesForFamily(fonts, family);
    if (files.length === 0) {
      continue;
    }
    lines.push(`    - family: ${family}`);
    lines.push("      fonts:");
    for (const file of files) {
      const asset =
        fonts.files[family] === undefined ? file.path : bundledFontPath(file);
      // Assets are declared relative to apps/mobile/, not to the repo root.
      lines.push(`        - asset: ${asset.replace(/^apps\/mobile\//, "")}`);
      if (file.weight !== null) {
        lines.push(`          weight: ${file.weight}`);
      }
      if (file.style === "italic") {
        lines.push("          style: italic");
      }
    }
  }
  return lines.join("\n");
};

/**
 * Upstream font files that no declared family references any more.
 *
 * Only meaningful with `replaceBundled: true`, where the point is licence
 * hygiene: a fork that has replaced the typefaces should not still be shipping
 * - and thereby redistributing - the ones it dropped.
 */
export const orphanedFontFiles = (fonts: BrandFonts): string[] => {
  if (!fonts.replaceBundled) {
    return [];
  }
  const declared = new Set(familiesToDeclare(fonts));
  const orphans: string[] = [];
  for (const [family, files] of Object.entries(UPSTREAM_FONT_FILES)) {
    if (declared.has(family)) {
      continue;
    }
    for (const file of files) {
      orphans.push(file.path);
    }
  }
  return orphans;
};
