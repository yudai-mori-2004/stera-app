/**
 * The typographic scale.
 *
 * `fonts.*` changes which typefaces the app draws with. This module changes how
 * big they are, how tightly they are set, and how heavy they run - which is most
 * of what makes two apps in the same typeface still look like different
 * products. A fork matching a reference could previously swap Geist for Inter
 * and inherit upstream's exact 10/12/14/16/18/20/24/32 ramp at upstream's exact
 * weights, which reads as this app wearing someone else's font.
 *
 * The structure deliberately copies `shape.ts`: named steps, three explicit
 * tables rather than a multiplier, `default` reproducing the literals already in
 * the widget tree so a rebrand that does not ask for a type change is a no-op on
 * every pixel.
 *
 * Two axes, because they are independently brandable and references publish
 * them separately:
 *
 * - the **step** table - a size and a line height per step
 * - the **weights** - the four `FontWeight`s the tree actually uses
 *
 * `xl3Plus` is the half-step the app's two big page titles sit on (28). It
 * exists for the same reason shape's `*Plus` steps do: without it those titles
 * would be the two headings in the product that quietly stop following the
 * brand, and "does this text follow the type scale" has to be yes everywhere for
 * the scale to mean anything.
 */

import type {
  TypeScale,
  TypeScaleOverrides,
  TypeStep as TypeStepName,
  TypeStyle,
  TypeWeights,
} from "./types.ts";

export const TYPE_STEPS = [
  "xs",
  "sm",
  "md",
  "lg",
  "xl",
  "xl2",
  "xl3",
  "xl3Plus",
  "xl4",
] as const;
export type TypeStep = TypeStepName;

export const TYPE_WEIGHT_ROLES = [
  "regular",
  "medium",
  "semibold",
  "bold",
] as const;

/**
 * Line heights are absolute logical pixels, not multipliers, because that is how
 * the app already expresses them (`height: 24 / 16`) and how a reference's CSS
 * expresses them. `generate.ts` converts to Flutter's ratio at the last moment.
 *
 * The display steps (`xl2` and up) are set solid - line height equal to size -
 * in every table. That is a deliberate property of the app's headings rather
 * than an artefact of the default table, so `compact` and `spacious` keep it and
 * move the body steps, which is where line height is actually legible as a
 * brand.
 */
export const TYPE_SCALES: Readonly<Record<TypeStyle, TypeScale>> = {
  compact: {
    xs: { size: 10, lineHeight: 12 },
    sm: { size: 11, lineHeight: 14 },
    md: { size: 13, lineHeight: 18 },
    lg: { size: 15, lineHeight: 20 },
    xl: { size: 17, lineHeight: 22 },
    xl2: { size: 19, lineHeight: 19 },
    xl3: { size: 22, lineHeight: 22 },
    xl3Plus: { size: 26, lineHeight: 26 },
    xl4: { size: 28, lineHeight: 28 },
  },
  default: {
    xs: { size: 10, lineHeight: 14 },
    sm: { size: 12, lineHeight: 16 },
    md: { size: 14, lineHeight: 20 },
    lg: { size: 16, lineHeight: 24 },
    xl: { size: 18, lineHeight: 26 },
    xl2: { size: 20, lineHeight: 20 },
    xl3: { size: 24, lineHeight: 24 },
    xl3Plus: { size: 28, lineHeight: 28 },
    xl4: { size: 32, lineHeight: 32 },
  },
  spacious: {
    xs: { size: 11, lineHeight: 16 },
    sm: { size: 13, lineHeight: 20 },
    md: { size: 15, lineHeight: 24 },
    lg: { size: 17, lineHeight: 28 },
    xl: { size: 20, lineHeight: 30 },
    xl2: { size: 22, lineHeight: 22 },
    xl3: { size: 27, lineHeight: 27 },
    xl3Plus: { size: 31, lineHeight: 31 },
    xl4: { size: 36, lineHeight: 36 },
  },
};

/** The style whose table equals the literals currently in the widget tree. */
export const UPSTREAM_TYPE_STYLE: TypeStyle = "default";

/**
 * The four weights the tree uses, by role rather than by number.
 *
 * A reference that runs light (400 headings, 300 body) or heavy (600 body, 800
 * headings) is expressed by moving these, and every `TextStyle` in the app
 * follows. Roles rather than raw numbers because "the headings got heavier" is
 * one edit here and forty otherwise.
 */
export const UPSTREAM_TYPE_WEIGHTS: TypeWeights = {
  regular: 400,
  medium: 500,
  semibold: 600,
  bold: 700,
};

/**
 * Maps an upstream literal `fontSize:` onto a step, or `null` to leave it alone.
 *
 * Every size the widget tree contains is claimed. One is not exact: 11 folds
 * into `sm` (12), which moves two captions in the error view by a pixel. Same
 * trade as `snapToStep` in `shape.ts` - a pixel now against two labels pinned to
 * upstream's typography forever.
 */
export const snapToTypeStep = (literal: number): TypeStep | null => {
  switch (literal) {
    case 10:
      return "xs";
    case 11:
    case 12:
      return "sm";
    case 14:
      return "md";
    case 16:
      return "lg";
    case 18:
      return "xl";
    case 20:
      return "xl2";
    case 24:
      return "xl3";
    case 28:
      return "xl3Plus";
    case 32:
      return "xl4";
    default:
      return null;
  }
};

/** Maps an upstream `FontWeight.wNNN` onto a role, or `null` if off-scale. */
export const snapToWeightRole = (
  literal: number
): keyof TypeWeights | null => {
  switch (literal) {
    case 400:
      return "regular";
    case 500:
      return "medium";
    case 600:
      return "semibold";
    case 700:
      return "bold";
    default:
      return null;
  }
};

export const resolveTypeScale = (
  style: TypeStyle,
  overrides: TypeScaleOverrides = {}
): TypeScale => {
  const base = TYPE_SCALES[style];
  const out = {} as TypeScale;
  for (const step of TYPE_STEPS) {
    out[step] = { ...base[step], ...overrides[step] };
  }
  return out;
};

export const resolveTypeWeights = (
  overrides: Partial<TypeWeights> = {}
): TypeWeights => ({ ...UPSTREAM_TYPE_WEIGHTS, ...overrides });
