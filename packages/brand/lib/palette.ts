/**
 * The app's design tokens, as data.
 *
 * `apps/mobile/lib/src/core/theme/colors.dart` declares thirty colours twice -
 * once for light, once for dark. Until now the rebrand engine could reach
 * exactly one of them (`brandAccent`), which is why changing the brand colour
 * changed a badge and nothing else: `theme.overrides` generated constants in
 * `BrandPalette` that `colors.dart` never read.
 *
 * This module is the fix. `BASE_PALETTE` mirrors the upstream literals, and
 * `resolvePalette` turns `(accent, tint, overrides)` into a value for every
 * token in both modes. `60-theme` then rewrites each literal in `colors.dart`
 * into a reference to the generated constant, so every token is reachable from
 * `brand.json`.
 *
 * ## Why a tint rather than a full palette in the config
 *
 * Asking a fork to specify thirty colours twice is asking them not to bother.
 * The app's palette is near-monochrome by design, so the useful knob is "how
 * much of my brand hue bleeds into the greys" - one number, `theme.tint`. Each
 * token declares how much of that it accepts (`TINT_WEIGHTS`); pure anchors and
 * semantic colours accept none, because a red that has drifted toward the brand
 * hue stops reading as an error and white that is no longer white breaks the
 * inversion pairs.
 *
 * `theme.overrides` still wins over everything, for the fork that does want to
 * name a specific colour.
 */

import {
  AA_LARGE,
  AA_NORMAL,
  contrastRatio,
  deriveDarkAccent,
  mix,
} from "./color.ts";
import type { Hex, Palette, TokenPair } from "./types.ts";

/**
 * Every colour field on `C`, in declaration order, grouped as the file groups
 * them. The order is load-bearing only for the generated file's readability -
 * lookups are by name.
 */
export const TOKEN_GROUPS: ReadonlyArray<{
  title: string;
  tokens: readonly string[];
}> = [
  {
    title: "Text",
    tokens: [
      "textPrimary",
      "textSecondary",
      "textTertiary",
      "textInversePrimary",
      "textInverseSecondary",
      "textDisabled",
      "textAlert",
      "textDestructive",
    ],
  },
  {
    title: "Surface",
    tokens: [
      "surfacePrimary",
      "surfaceSecondary",
      "surfaceTertiary",
      "surfaceBlack",
      "surfaceWhite",
    ],
  },
  {
    title: "Border",
    tokens: [
      "borderDefault",
      "borderDisabled",
      "borderDivider",
      "borderError",
      "borderSelected",
    ],
  },
  { title: "Icon", tokens: ["iconPrimary", "iconDisabled"] },
  {
    title: "Neutral",
    tokens: [
      "neutralDarkGray",
      "neutralGray",
      "neutralLightGray",
      "neutralBlack",
      "neutralWhite",
    ],
  },
  { title: "Semantic", tokens: ["blue", "red", "green", "yellow"] },
  { title: "Brand", tokens: ["brandAccent"] },
];

export const TOKEN_NAMES: readonly string[] = TOKEN_GROUPS.flatMap(
  (group) => group.tokens
);

/**
 * The upstream values, transcribed from `colors.dart`.
 *
 * These are the defaults, not a historical record: a fork that sets no theme
 * options at all resolves to exactly this, so `brand:apply` is colour-neutral
 * unless asked otherwise.
 */
export const BASE_PALETTE: Palette = {
  // Text
  textPrimary: { light: "0xFF18191B", dark: "0xFFFFFFFF" },
  textSecondary: { light: "0xFF737373", dark: "0xFFBBBEC3" },
  textTertiary: { light: "0xFFBBBEC3", dark: "0xFF737373" },
  textInversePrimary: { light: "0xFFFFFFFF", dark: "0xFF18191B" },
  textInverseSecondary: { light: "0x99FFFFFF", dark: "0x9918191B" },
  textDisabled: { light: "0xFFC7C7C7", dark: "0xFF5C5C5C" },
  textAlert: { light: "0xFFB27700", dark: "0xFFFFB740" },
  textDestructive: { light: "0xFFD32F2F", dark: "0xFFEF5350" },

  // Surface
  surfacePrimary: { light: "0xFFF8F9FA", dark: "0xFF18191B" },
  surfaceSecondary: { light: "0xFFFFFFFF", dark: "0xFF232426" },
  surfaceTertiary: { light: "0xFFF7F4ED", dark: "0xFF2E2F31" },
  surfaceBlack: { light: "0xFF18191B", dark: "0xFF000000" },
  surfaceWhite: { light: "0xFFFFFFFF", dark: "0xFFFFFFFF" },

  // Border
  borderDefault: { light: "0xFFB7B7B7", dark: "0xFF5C5C5C" },
  borderDisabled: { light: "0xFFC7C7C7", dark: "0xFF3D3D3D" },
  borderDivider: { light: "0xFFE0E0E0", dark: "0xFF3D3D3D" },
  borderError: { light: "0xFFD32F2F", dark: "0xFFEF5350" },
  borderSelected: { light: "0xFF000000", dark: "0xFFFFFFFF" },

  // Icon
  iconPrimary: { light: "0xFF737373", dark: "0xFFBBBEC3" },
  iconDisabled: { light: "0xFFC7C7C7", dark: "0xFF5C5C5C" },

  // Neutral
  neutralDarkGray: { light: "0xFF737373", dark: "0xFF8E8E93" },
  neutralGray: { light: "0xFFBBBEC3", dark: "0xFFBBBEC3" },
  neutralLightGray: { light: "0xFFEBEBEB", dark: "0xFF3D3D3D" },
  neutralBlack: { light: "0xFF18191B", dark: "0xFF000000" },
  neutralWhite: { light: "0xFFFFFFFF", dark: "0xFFFFFFFF" },

  // Semantic
  blue: { light: "0xFF007AFF", dark: "0xFF0A84FF" },
  red: { light: "0xFFD32F2F", dark: "0xFFEF5350" },
  green: { light: "0xFF047A00", dark: "0xFF32D74B" },
  yellow: { light: "0xFFFFB740", dark: "0xFFFFB740" },

  // Brand
  brandAccent: { light: "0xFFE8A33D", dark: "0xFFFFB740" },
};

/**
 * How much of the global tint each token accepts, 0..1.
 *
 * Zero is the default and the interesting cases are the ones that opt in. The
 * ladder runs: page and card surfaces take the most (they are the largest areas
 * and the most forgiving), strokes and fills take about half, muted text takes
 * a third, and primary text barely any - a heading that has drifted toward the
 * brand hue looks like a rendering bug, not a brand.
 *
 * Deliberately absent, and each for its own reason:
 * - `surfaceWhite` / `neutralWhite` / `neutralBlack` / `surfaceBlack` are
 *   anchors. Other tokens are defined by inverting against them.
 * - `textInverse*` must stay the exact inverse of the surfaces they sit on.
 * - `red` / `green` / `blue` / `yellow` / `*Destructive` / `*Error` / `textAlert`
 *   are semantic. An error that has been tinted brand-ward stops reading as an
 *   error, which is a usability regression dressed as a branding feature.
 */
export const TINT_WEIGHTS: Readonly<Record<string, number>> = {
  surfacePrimary: 1,
  surfaceTertiary: 1,

  // Deliberately low, and the reason is worth recording. `surfaceSecondary` is
  // the card, pure white in light mode, and `textSecondary` on it is 4.74:1 -
  // barely a quarter of a point above AA. Tinting the card as hard as the page
  // spends that headroom immediately, and the run gets refused for a change
  // almost nobody would notice. The page behind the cards carries the colour;
  // the cards stay out of the way.
  surfaceSecondary: 0.3,

  borderDefault: 0.6,
  borderDivider: 0.6,
  borderDisabled: 0.5,

  neutralLightGray: 0.55,
  neutralGray: 0.5,
  neutralDarkGray: 0.5,

  iconPrimary: 0.4,
  iconDisabled: 0.35,

  // Muted text takes a little so it does not read as a foreign grey against a
  // tinted surface. Primary text takes none: a heading that has drifted toward
  // the brand hue looks like a rendering bug rather than a brand, and it is
  // half of every contrast pair that matters.
  textSecondary: 0.25,
  textTertiary: 0.3,
  textDisabled: 0.3,
};

/**
 * The mix applied at `tint: 1`, before per-token weighting.
 *
 * 14% of the accent into a page background is clearly visible - a warm accent
 * turns #F8F9FA into a bone/ivory, a cool one into a pale slate - without
 * turning the app into a colour field. Above this it starts to fight the
 * content; a fork that wants that should name the colour in `theme.overrides`
 * and own the consequences.
 *
 * A mix moves lightness as well as hue, which is unavoidable: chroma needs
 * room, and a near-white surface has none to spare. That is exactly why the
 * contrast contract below exists, and why the weights above are apportioned
 * the way they are.
 */
export const MAX_TINT = 0.14;

/**
 * Pairs asserted to stay legible after tinting.
 *
 * These are the combinations the UI actually renders, not every possible pair.
 * `AA_NORMAL` where the pair carries body text, `AA_LARGE` where it is a stroke
 * or a large label - matching how WCAG grades each.
 */
const CONTRACT: ReadonlyArray<{
  foreground: string;
  background: string;
  minimum: number;
  what: string;
}> = [
  {
    foreground: "textPrimary",
    background: "surfacePrimary",
    minimum: AA_NORMAL,
    what: "body text on the page background",
  },
  {
    foreground: "textPrimary",
    background: "surfaceSecondary",
    minimum: AA_NORMAL,
    what: "body text on cards",
  },
  {
    foreground: "textSecondary",
    background: "surfacePrimary",
    minimum: AA_NORMAL,
    what: "secondary text on the page background",
  },
  {
    foreground: "textSecondary",
    background: "surfaceSecondary",
    minimum: AA_NORMAL,
    what: "secondary text on cards",
  },
  {
    foreground: "textPrimary",
    background: "surfaceTertiary",
    minimum: AA_NORMAL,
    what: "text on the accent surface",
  },
  {
    foreground: "borderDefault",
    background: "surfacePrimary",
    minimum: AA_LARGE,
    what: "control outlines on the page background",
  },
  {
    foreground: "iconPrimary",
    background: "surfacePrimary",
    minimum: AA_LARGE,
    what: "icons on the page background",
  },
];

export interface ContrastFinding {
  foreground: string;
  background: string;
  mode: "light" | "dark";
  ratio: number;
  /** The same pair's ratio in the upstream palette. */
  baseline: number;
  minimum: number;
  what: string;
  /**
   * True when this pair met its minimum upstream and no longer does.
   *
   * The upstream palette does not itself pass every pair - `borderDefault` on
   * `surfacePrimary` is 1.9:1 by design, a hairline rather than a component
   * outline - so absolute compliance cannot be the bar, or `brand:apply` would
   * refuse to run on an unmodified config. Nor is "any degradation" the bar:
   * blocking a rebrand because a hairline went from 1.90 to 1.79 is noise about
   * a pair that was never compliant to begin with.
   *
   * What a fork can fairly be held to is not *breaking* what worked. That is
   * this flag, and it is the only thing that blocks a run.
   */
  regression: boolean;
}

/** Every contract pair below its minimum, in both modes, graded against upstream. */
export const checkContrast = (
  palette: Palette,
  baseline: Palette = BASE_PALETTE
): ContrastFinding[] => {
  const findings: ContrastFinding[] = [];

  for (const mode of ["light", "dark"] as const) {
    for (const pair of CONTRACT) {
      const foreground = palette[pair.foreground]?.[mode];
      const background = palette[pair.background]?.[mode];
      if (foreground === undefined || background === undefined) {
        continue;
      }

      const ratio = contrastRatio(foreground, background);
      if (ratio >= pair.minimum) {
        continue;
      }

      const baseForeground = baseline[pair.foreground]?.[mode];
      const baseBackground = baseline[pair.background]?.[mode];
      const baseRatio =
        baseForeground === undefined || baseBackground === undefined
          ? ratio
          : contrastRatio(baseForeground, baseBackground);

      findings.push({
        foreground: pair.foreground,
        background: pair.background,
        mode,
        ratio,
        baseline: baseRatio,
        minimum: pair.minimum,
        what: pair.what,
        regression: baseRatio >= pair.minimum,
      });
    }
  }

  return findings;
};

export interface ResolvePaletteOptions {
  accentLight: Hex;
  accentDark?: Hex;
  /** 0..1. How much of the accent bleeds into the neutrals. */
  tint?: number;
  /** Explicit per-token colours. Applied last; they win over the tint. */
  overrides?: Readonly<Record<string, TokenPair>>;
}

/**
 * Resolves the full palette.
 *
 * Order is accent, then tint, then overrides - each stage able to overrule the
 * one before it, so `theme.overrides` remains the single sanctioned place to
 * disagree with the derivation.
 */
export const resolvePalette = ({
  accentLight,
  accentDark,
  tint = 0,
  overrides = {},
}: ResolvePaletteOptions): Palette => {
  const accent: TokenPair = {
    light: accentLight,
    dark: accentDark ?? deriveDarkAccent(accentLight),
  };

  const palette: Palette = {};
  for (const token of TOKEN_NAMES) {
    const base = token === "brandAccent" ? accent : (BASE_PALETTE[token] as TokenPair);
    const weight = TINT_WEIGHTS[token] ?? 0;
    const amount = tint * weight * MAX_TINT;

    palette[token] =
      amount === 0
        ? { ...base }
        : {
            light: mix(base.light, accent.light, amount),
            dark: mix(base.dark, accent.dark, amount),
          };
  }

  for (const [token, pair] of Object.entries(overrides)) {
    palette[token] = { ...pair };
  }

  return palette;
};

/** Tokens whose resolved value differs from upstream. Drives the preview diff. */
export const changedTokens = (palette: Palette): string[] =>
  TOKEN_NAMES.filter((token) => {
    const base = BASE_PALETTE[token];
    const next = palette[token];
    return (
      base !== undefined &&
      next !== undefined &&
      (base.light !== next.light || base.dark !== next.dark)
    );
  });
