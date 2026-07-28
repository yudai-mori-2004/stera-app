/**
 * The corner-radius scale.
 *
 * "It doesn't change the layout" is mostly this: the app hardens its geometry
 * into ~180 literal `BorderRadius.circular(12)` calls, so a rebrand could move
 * every colour and every string and the product still had the same silhouette.
 *
 * The fix is a scale with the upstream numbers as the `soft` default, plus a
 * sweep in `20-rewrite-content` that rewrites the literals into references to
 * it.
 *
 * The scale used to have six steps, which covered the six values the tree used
 * *most* and left the rest - 1.5, 2, 3, 6, 10, 14, 20, 30 - as literals. That
 * was defensible as "deliberate one-offs" and wrong in practice: a fork asking
 * for `sharp` got sharp cards and rounded bottom sheets, because every sheet in
 * this app happens to be a 20 and 20 was off-scale. The in-between steps below
 * exist so that "does this element follow the brand" is yes for all of them.
 *
 * The `*Plus` steps are half-steps between the named ones. They are not a
 * second design vocabulary - `mdPlus` means "one notch above md", and at `soft`
 * it is exactly the literal that was already there.
 */

import type { ShapeScale, ShapeStyle } from "./types.ts";

export const SHAPE_STEPS = [
  "hairline",
  "xs",
  "xsPlus",
  "sm",
  "smPlus",
  "md",
  "mdPlus",
  "lg",
  "lgPlus",
  "xl",
  "xlPlus",
  "full",
] as const;
export type ShapeStep = (typeof SHAPE_STEPS)[number];

/**
 * `full` is 999 in every style on purpose. It is a sentinel meaning "clamp to
 * half the shorter side"; scaling it down would turn pill buttons and avatars
 * into rounded rectangles, which is not what "sharp" is asking for.
 *
 * `soft` reproduces the upstream literals exactly, so a rebrand that does not
 * ask for a shape change stays a no-op on every pixel.
 */
export const SHAPE_SCALES: Readonly<Record<ShapeStyle, ShapeScale>> = {
  sharp: {
    hairline: 0,
    xs: 0,
    xsPlus: 1,
    sm: 2,
    smPlus: 3,
    md: 4,
    mdPlus: 5,
    lg: 6,
    lgPlus: 7,
    xl: 8,
    xlPlus: 10,
    full: 999,
  },
  soft: {
    hairline: 1.5,
    xs: 4,
    xsPlus: 6,
    sm: 8,
    smPlus: 10,
    md: 12,
    mdPlus: 14,
    lg: 16,
    lgPlus: 20,
    xl: 24,
    xlPlus: 30,
    full: 999,
  },
  rounded: {
    hairline: 2,
    xs: 6,
    xsPlus: 9,
    sm: 12,
    smPlus: 15,
    md: 18,
    mdPlus: 21,
    lg: 24,
    lgPlus: 28,
    xl: 32,
    xlPlus: 40,
    full: 999,
  },
  pill: {
    hairline: 3,
    xs: 8,
    xsPlus: 12,
    sm: 16,
    smPlus: 21,
    md: 26,
    mdPlus: 30,
    lg: 34,
    lgPlus: 39,
    xl: 44,
    xlPlus: 52,
    full: 999,
  },
};

/** The style whose scale equals the literals currently in the widget tree. */
export const UPSTREAM_SHAPE_STYLE: ShapeStyle = "soft";

/**
 * Maps an upstream literal onto a scale step, or `null` to leave it alone.
 *
 * Every value the widget tree actually contains is claimed. Two of them are not
 * exact: 2 folds into `hairline` (1.5) and 3 into `xs` (4), which moves a
 * drag-grabber and a coaching-overlay dot by half a pixel and a pixel at the
 * default style. That is the price of "every radius follows the brand", and it
 * is a better trade than leaving two widgets pinned to upstream's silhouette
 * forever.
 *
 * Anything else - a value a fork introduced by hand - is left alone and
 * reported by `brand:apply`, because guessing which step an unknown number
 * meant is how a rebrand becomes a visual diff nobody asked for.
 */
export const snapToStep = (literal: number): ShapeStep | null => {
  switch (literal) {
    case 1.5:
    case 2:
      return "hairline";
    case 3:
    case 4:
      return "xs";
    case 6:
      return "xsPlus";
    case 8:
      return "sm";
    case 10:
      return "smPlus";
    case 12:
      return "md";
    case 14:
      return "mdPlus";
    case 16:
      return "lg";
    case 20:
      return "lgPlus";
    case 24:
      return "xl";
    case 30:
      return "xlPlus";
    case 999:
      return "full";
    default:
      return null;
  }
};

export const resolveShapeScale = (
  style: ShapeStyle,
  overrides: Partial<ShapeScale> = {}
): ShapeScale => ({ ...SHAPE_SCALES[style], ...overrides });
