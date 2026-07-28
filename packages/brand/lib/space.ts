/**
 * The spacing scale.
 *
 * Colour, shape and type were brandable before this; density was not. Two apps
 * can share a palette, a corner radius and a typeface and still read as
 * different products because one breathes and the other is packed - it is the
 * difference between a settings list you scan and one you scroll. That was
 * spelled out in ~400 literal `EdgeInsets` and `SizedBox` values, so a fork
 * could move everything else and still lay out exactly like upstream.
 *
 * Same structure as `shape.ts` and `type.ts`: named steps, explicit tables
 * rather than a multiplier, `default` reproducing the literals already in the
 * widget tree so a rebrand that does not ask for a density change is a no-op on
 * every pixel.
 *
 * The steps are dense on purpose. A four-step scale would be tidier and would
 * force ~90 call sites to move by 2-4px to reach it, which is a visual diff
 * nobody asked for in exchange for a vocabulary nobody needed. These are the
 * values the tree uses, named.
 */

import type { SpaceScale, SpaceStep as SpaceStepName, SpaceStyle } from "./types.ts";

export const SPACE_STEPS = [
  "none",
  "xxs",
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
  "xxl",
  "huge",
] as const;
export type SpaceStep = SpaceStepName;

/**
 * `tight` is roughly 0.75x and `comfortable` roughly 1.25x, rounded to whole
 * pixels at each step rather than computed, so the scale stays a designed set of
 * numbers instead of a float ramp with 11.25 in the middle of it.
 *
 * `none` is 0 in every style. A zero pad is the absence of spacing, not a small
 * amount of it, and scaling it would be meaningless.
 */
export const SPACE_SCALES: Readonly<Record<SpaceStyle, SpaceScale>> = {
  tight: {
    none: 0,
    xxs: 2,
    xs: 3,
    xsPlus: 5,
    sm: 6,
    smPlus: 8,
    md: 9,
    mdPlus: 11,
    lg: 12,
    lgPlus: 15,
    xl: 18,
    xlPlus: 21,
    xxl: 24,
    huge: 48,
  },
  default: {
    none: 0,
    xxs: 2,
    xs: 4,
    xsPlus: 6,
    sm: 8,
    smPlus: 10,
    md: 12,
    mdPlus: 14,
    lg: 16,
    lgPlus: 20,
    xl: 24,
    xlPlus: 28,
    xxl: 32,
    huge: 64,
  },
  comfortable: {
    none: 0,
    xxs: 3,
    xs: 5,
    xsPlus: 8,
    sm: 10,
    smPlus: 13,
    md: 15,
    mdPlus: 18,
    lg: 20,
    lgPlus: 25,
    xl: 30,
    xlPlus: 35,
    xxl: 40,
    huge: 80,
  },
};

/** The style whose scale equals the literals currently in the widget tree. */
export const UPSTREAM_SPACE_STYLE: SpaceStyle = "default";

/**
 * Maps an upstream literal onto a step, or `null` to leave it alone.
 *
 * Every value the tree contains is claimed. Five are not exact: 3 folds into
 * `xxs` (2), 5 into `xs` (4), 7 into `sm` (8), 11 into `md` (12) and 18 into
 * `lgPlus` (20). That is eight call sites moving by one or two pixels, against
 * those eight being the only places in the app whose spacing no future rebrand
 * can reach. Same trade `snapToStep` makes in `shape.ts`, and for the same
 * reason.
 *
 * Anything else - a value a fork introduced by hand - is left alone and reported
 * by `brand:apply`.
 */
export const snapToSpaceStep = (literal: number): SpaceStep | null => {
  switch (literal) {
    case 0:
      return "none";
    case 2:
    case 3:
      return "xxs";
    case 4:
    case 5:
      return "xs";
    case 6:
      return "xsPlus";
    case 7:
    case 8:
      return "sm";
    case 10:
      return "smPlus";
    case 11:
    case 12:
      return "md";
    case 14:
      return "mdPlus";
    case 16:
      return "lg";
    case 18:
    case 20:
      return "lgPlus";
    case 24:
      return "xl";
    case 28:
      return "xlPlus";
    case 32:
      return "xxl";
    case 64:
      return "huge";
    default:
      return null;
  }
};

export const resolveSpaceScale = (
  style: SpaceStyle,
  overrides: Partial<SpaceScale> = {}
): SpaceScale => ({ ...SPACE_SCALES[style], ...overrides });
