/**
 * Dart source rewrites that are broad rather than surgical.
 *
 * The seam transforms in `transforms/seams.ts` each know one file and one
 * literal. This module is for the opposite case: a rewrite that has to visit
 * every widget in the app because the value it is hoisting was inlined
 * everywhere. So far that is the corner-radius scale, which appears as a bare
 * number in roughly forty files.
 *
 * These run *inside* `20-rewrite-content` rather than as their own transform.
 * A transform that wanted these files would have to `owns()` them, which would
 * remove them from the token sweep and make it responsible for renaming
 * `package:stera/...` imports in a hundred files it has no other reason to
 * touch - and would collide with the copy seams, which already own a handful of
 * them. Running as a stage of the sweep keeps one writer per file.
 */

import { snapToStep } from "./shape.ts";
import { snapToSpaceStep } from "./space.ts";

/** Only the app's own widget tree. See `rewriteRadii` for why. */
export const RADIUS_SWEEP_PREFIX = "apps/mobile/lib/";

export const isRadiusSweepTarget = (path: string): boolean =>
  path.startsWith(RADIUS_SWEEP_PREFIX) && path.endsWith(".dart");

/**
 * Inserts an import, keeping the file's existing convention: this codebase puts
 * its own `package:<app>/...` imports first, then `package:flutter/...`.
 */
export const addDartImport = (source: string, statement: string): string => {
  if (source.includes(statement)) {
    return source;
  }
  const lines = source.split("\n");
  let insertAt = 0;
  let lastOwnImport = -1;

  lines.forEach((line, index) => {
    if (/^import "package:[a-z_0-9]+\/src\//.test(line)) {
      lastOwnImport = index;
    }
  });

  if (lastOwnImport >= 0) {
    insertAt = lastOwnImport + 1;
  } else {
    const firstImport = lines.findIndex((line) => line.startsWith("import "));
    insertAt = firstImport === -1 ? 0 : firstImport;
  }

  lines.splice(insertAt, 0, statement);
  return lines.join("\n");
};

export const dartImportLine = (dartPackage: string, path: string): string =>
  `import "package:${dartPackage}/${path}";`;

const SHAPE_IMPORT_PATH = "src/core/theme/brand_shape.dart";

/**
 * `BorderRadius.circular(12)` and `Radius.circular(12)`, with an optional
 * decimal part. The alternation puts `BorderRadius` first for readability; the
 * leading `\b` already prevents `Radius` from matching inside it.
 */
const RADIUS_RE = /\b(BorderRadius|Radius)\.circular\(\s*(\d+(?:\.\d+)?)\s*\)/g;

const STEP_CONSTANTS: Record<string, string> = {
  hairline: "BrandShape.radiusHairline",
  xs: "BrandShape.radiusXs",
  xsPlus: "BrandShape.radiusXsPlus",
  sm: "BrandShape.radiusSm",
  smPlus: "BrandShape.radiusSmPlus",
  md: "BrandShape.radiusMd",
  mdPlus: "BrandShape.radiusMdPlus",
  lg: "BrandShape.radiusLg",
  lgPlus: "BrandShape.radiusLgPlus",
  xl: "BrandShape.radiusXl",
  xlPlus: "BrandShape.radiusXlPlus",
  full: "BrandShape.radiusFull",
};

export interface RadiusRewrite {
  text: string;
  /** Literals converted to a scale reference, by step. */
  converted: Map<string, number>;
  /** Off-scale literals left alone, by value. */
  skipped: Map<number, number>;
}

/**
 * Rewrites on-scale radius literals into references to the generated
 * `BrandShape` scale, and adds the import if anything changed.
 *
 * Restricted to `apps/mobile/lib/` because `BrandShape` lives in the app
 * package. The recorder plugin cannot import from the app that hosts it, so its
 * radii stay literal - it has almost no chrome of its own, and inverting the
 * dependency to share a scale with it would be a much larger change than the
 * problem deserves.
 *
 * Off-scale values are deliberately untouched; `snapToStep` explains why.
 * Idempotent: after the first run the literals are gone, so a second pass finds
 * nothing and the numbers change by regenerating `brand_shape.dart` alone.
 */
export const rewriteRadii = (
  source: string,
  dartPackage: string
): RadiusRewrite => {
  const converted = new Map<string, number>();
  const skipped = new Map<number, number>();

  const text = source.replace(RADIUS_RE, (match, constructor: string, literal: string) => {
    const value = Number.parseFloat(literal);
    const step = snapToStep(value);
    if (step === null) {
      skipped.set(value, (skipped.get(value) ?? 0) + 1);
      return match;
    }
    converted.set(step, (converted.get(step) ?? 0) + 1);
    return `${constructor}.circular(${STEP_CONSTANTS[step] as string})`;
  });

  if (converted.size === 0) {
    return { text: source, converted, skipped };
  }

  return {
    text: addDartImport(text, dartImportLine(dartPackage, SHAPE_IMPORT_PATH)),
    converted,
    skipped,
  };
};

const SPACING_IMPORT_PATH = "src/core/theme/app_spacing.dart";

/**
 * The three places a spacing literal appears: inside an `EdgeInsets`
 * constructor, as a single-axis `SizedBox`, and as a flex `spacing:`.
 *
 * Deliberately not "any bare number". A `SizedBox` with *both* axes is a box
 * size rather than a gap, and an unanchored numeric sweep would also catch
 * durations, opacities, flex factors and page indices - the widget tree is full
 * of numbers that are not spacing. Every one of the ~400 sites this does match
 * is a gap or a pad; there are no two-axis `SizedBox`es in the tree, which is
 * what makes the narrow rule sufficient here.
 */
const EDGE_INSETS_RE =
  /EdgeInsets(?:\.directional)?\.(all|symmetric|only|fromLTRB)\(([^()]*)\)/g;
const SIZED_BOX_RE = /SizedBox\((height|width): (\d+(?:\.\d+)?)(?![\w.])/g;
const FLEX_SPACING_RE = /spacing: (\d+(?:\.\d+)?)(?![\w.])/g;
const BARE_NUMBER_RE = /(?<![\w.])(\d+(?:\.\d+)?)(?![\w.])/g;

export interface SpacingRewrite {
  text: string;
  /** Literals converted to a scale reference, by step. */
  converted: Map<string, number>;
  /** Off-scale literals left alone, by value. */
  skipped: Map<number, number>;
}

/**
 * Rewrites on-scale spacing literals into references to `AppSpacing`, and adds
 * the import if anything changed.
 *
 * Sibling of `rewriteRadii`, with the same restriction to `apps/mobile/lib/` and
 * the same idempotence: after the first run the literals are gone, so a second
 * pass finds nothing and the numbers move by regenerating `brand_space.dart`
 * alone.
 *
 * Unlike the radius sweep this targets `AppSpacing` rather than `BrandSpace`
 * directly, because the call sites read better - `EdgeInsets.all(AppSpacing.lg)`
 * against `EdgeInsets.all(BrandSpace.lg)` - and `AppSpacing` is where the
 * ready-made insets live.
 */
export const rewriteSpacing = (
  source: string,
  dartPackage: string
): SpacingRewrite => {
  const converted = new Map<string, number>();
  const skipped = new Map<number, number>();

  const replaceNumber = (raw: string): string => {
    const value = Number.parseFloat(raw);
    const step = snapToSpaceStep(value);
    if (step === null) {
      skipped.set(value, (skipped.get(value) ?? 0) + 1);
      return raw;
    }
    converted.set(step, (converted.get(step) ?? 0) + 1);
    return `AppSpacing.${step}`;
  };

  let text = source.replace(
    EDGE_INSETS_RE,
    (_match, constructor: string, args: string) =>
      `EdgeInsets.${constructor}(${args.replace(BARE_NUMBER_RE, (raw) => replaceNumber(raw))})`
  );
  text = text.replace(
    SIZED_BOX_RE,
    (_match, axis: string, raw: string) => `SizedBox(${axis}: ${replaceNumber(raw)}`
  );
  text = text.replace(
    FLEX_SPACING_RE,
    (_match, raw: string) => `spacing: ${replaceNumber(raw)}`
  );

  if (converted.size === 0) {
    return { text: source, converted, skipped };
  }

  return {
    text: addDartImport(text, dartImportLine(dartPackage, SPACING_IMPORT_PATH)),
    converted,
    skipped,
  };
};

/**
 * Rewrites the family literals in `app_text_theme.dart` into the four
 * `BrandFonts` roles.
 *
 * Matching is against `prev`'s families rather than a fixed list, so the
 * mapping keeps working after a fork has already changed them once. A family
 * that fills two roles (say, body and mono both "Geist") maps every occurrence
 * to the first matching role, which is why the roles are checked in a fixed
 * order rather than as a map.
 */
export const rewriteFontFamilies = (
  source: string,
  previous: { display: string; body: string; mono: string; accent: string },
  dartPackage: string
): { text: string; hits: number } => {
  const roles: ReadonlyArray<[string, string]> = [
    [previous.display, "BrandFonts.display"],
    [previous.body, "BrandFonts.body"],
    [previous.mono, "BrandFonts.mono"],
    [previous.accent, "BrandFonts.accent"],
  ];

  let hits = 0;
  const text = source.replace(
    /fontFamily:\s*"([^"]+)"/g,
    (match, family: string) => {
      const role = roles.find(([name]) => name === family);
      if (role === undefined) {
        return match;
      }
      hits += 1;
      return `fontFamily: ${role[1]}`;
    }
  );

  if (hits === 0) {
    return { text: source, hits };
  }

  return {
    text: addDartImport(
      text,
      dartImportLine(dartPackage, "src/core/theme/brand_fonts.dart")
    ),
    hits,
  };
};
