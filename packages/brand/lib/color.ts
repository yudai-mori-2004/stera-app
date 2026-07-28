/**
 * Colour primitives and maths.
 *
 * This module owns the `0xAARRGGBB` representation the rest of the engine
 * passes around, plus everything that has to *reason* about a colour rather
 * than just carry it: mixing an accent into a neutral, lifting a hue for dark
 * mode, and checking that the result is still legible.
 *
 * It deliberately imports nothing but the `Hex` alias. `derive.ts` needs colour
 * maths and colour maths must not need `derive.ts` - so parse failures are
 * reported by returning `null` here and turned into a `BrandConfigError` up
 * there, rather than importing the error type down here and making a cycle.
 *
 * The space is plain sRGB. Not because it is perceptually correct - OKLab would
 * be - but because every consumer (Flutter `Color`, an `.colorset`, a CSS swatch
 * in the preview) is sRGB, and a round trip through a perceptual space would
 * make the generated Dart differ from the hex the user typed by a digit or two.
 * Predictability beats perceptual uniformity when the output is source code
 * somebody will read.
 */

import type { Hex } from "./types.ts";

export interface Rgba {
  r: number;
  g: number;
  b: number;
  a: number;
}

export interface Hsl {
  /** Degrees, 0-360. */
  h: number;
  /** 0-1. */
  s: number;
  /** 0-1. */
  l: number;
}

const clamp = (value: number, low: number, high: number): number =>
  Math.min(high, Math.max(low, value));

const byte = (value: number): number => clamp(Math.round(value), 0, 255);

const hex2 = (value: number): string =>
  byte(value).toString(16).toUpperCase().padStart(2, "0");

// ---------------------------------------------------------------------------
// Parsing and formatting
// ---------------------------------------------------------------------------

const FLUTTER_RE = /^0x[0-9A-Fa-f]{8}$/;
const CSS6_RE = /^#?([0-9A-Fa-f]{6})$/;
const CSS8_RE = /^#?([0-9A-Fa-f]{8})$/;
const CSS3_RE = /^#?([0-9A-Fa-f]{3})$/;

/**
 * Accepts `0xAARRGGBB`, `#RRGGBB`, `#RRGGBBAA` or `#RGB`; returns the canonical
 * `0xAARRGGBB` form, or `null` if the string is not a colour.
 *
 * Note the argument order flip: CSS puts alpha last, Flutter puts it first.
 * Getting that backwards produces a fully transparent colour that renders as
 * "nothing appeared" rather than as an error, which is why it is handled in
 * exactly one place.
 */
export const parseHex = (value: string): Hex | null => {
  const trimmed = value.trim();

  if (FLUTTER_RE.test(trimmed)) {
    return `0x${trimmed.slice(2).toUpperCase()}`;
  }

  const short = CSS3_RE.exec(trimmed);
  if (short?.[1]) {
    const [r, g, b] = short[1].toUpperCase();
    return `0xFF${r}${r}${g}${g}${b}${b}`;
  }

  const six = CSS6_RE.exec(trimmed);
  if (six?.[1]) {
    return `0xFF${six[1].toUpperCase()}`;
  }

  const eight = CSS8_RE.exec(trimmed);
  if (eight?.[1]) {
    const body = eight[1].toUpperCase();
    return `0x${body.slice(6, 8)}${body.slice(0, 6)}`;
  }

  return null;
};

export const hexToRgba = (hex: Hex): Rgba => {
  const body = hex.slice(2);
  return {
    a: Number.parseInt(body.slice(0, 2), 16),
    r: Number.parseInt(body.slice(2, 4), 16),
    g: Number.parseInt(body.slice(4, 6), 16),
    b: Number.parseInt(body.slice(6, 8), 16),
  };
};

export const rgbaToHex = ({ r, g, b, a }: Rgba): Hex =>
  `0x${hex2(a)}${hex2(r)}${hex2(g)}${hex2(b)}`;

/** `0xFFE8A33D` -> `#E8A33D`. Drops alpha; for CSS, SVG and Gradle consumers. */
export const hexToCss = (hex: Hex): string => `#${hex.slice(4)}`;

/** `0xCCE8A33D` -> `rgba(232, 163, 61, 0.8)`. Keeps alpha; for the preview. */
export const hexToCssRgba = (hex: Hex): string => {
  const { r, g, b, a } = hexToRgba(hex);
  return `rgba(${r}, ${g}, ${b}, ${(a / 255).toFixed(3)})`;
};

// ---------------------------------------------------------------------------
// HSL
// ---------------------------------------------------------------------------

export const rgbaToHsl = ({ r, g, b }: Rgba): Hsl => {
  const rn = r / 255;
  const gn = g / 255;
  const bn = b / 255;
  const max = Math.max(rn, gn, bn);
  const min = Math.min(rn, gn, bn);
  const l = (max + min) / 2;
  const delta = max - min;

  if (delta === 0) {
    return { h: 0, s: 0, l };
  }

  const s = delta / (1 - Math.abs(2 * l - 1));
  let h: number;
  if (max === rn) {
    h = ((gn - bn) / delta) % 6;
  } else if (max === gn) {
    h = (bn - rn) / delta + 2;
  } else {
    h = (rn - gn) / delta + 4;
  }
  h *= 60;
  if (h < 0) {
    h += 360;
  }
  return { h, s, l };
};

export const hslToRgba = ({ h, s, l }: Hsl, alpha = 255): Rgba => {
  const c = (1 - Math.abs(2 * l - 1)) * s;
  const hp = (((h % 360) + 360) % 360) / 60;
  const x = c * (1 - Math.abs((hp % 2) - 1));
  const m = l - c / 2;

  let rp = 0;
  let gp = 0;
  let bp = 0;
  if (hp < 1) {
    [rp, gp, bp] = [c, x, 0];
  } else if (hp < 2) {
    [rp, gp, bp] = [x, c, 0];
  } else if (hp < 3) {
    [rp, gp, bp] = [0, c, x];
  } else if (hp < 4) {
    [rp, gp, bp] = [0, x, c];
  } else if (hp < 5) {
    [rp, gp, bp] = [x, 0, c];
  } else {
    [rp, gp, bp] = [c, 0, x];
  }

  return {
    r: byte((rp + m) * 255),
    g: byte((gp + m) * 255),
    b: byte((bp + m) * 255),
    a: byte(alpha),
  };
};

export const hexToHsl = (hex: Hex): Hsl => rgbaToHsl(hexToRgba(hex));

// ---------------------------------------------------------------------------
// Operations
// ---------------------------------------------------------------------------

/**
 * Linear interpolation in sRGB. `amount` is how much of `overlay` ends up in
 * the result: 0 returns `base` unchanged, 1 returns `overlay`.
 *
 * Alpha comes from `base`, not from the mix. Tinting a translucent token must
 * not quietly make it opaque - `textInverseSecondary` is `0x99FFFFFF` and stays
 * 60% transparent no matter what hue is stirred into it.
 */
export const mix = (base: Hex, overlay: Hex, amount: number): Hex => {
  const t = clamp(amount, 0, 1);
  const a = hexToRgba(base);
  const b = hexToRgba(overlay);
  return rgbaToHex({
    r: a.r + (b.r - a.r) * t,
    g: a.g + (b.g - a.g) * t,
    b: a.b + (b.b - a.b) * t,
    a: a.a,
  });
};

/** Moves lightness by `delta` (in 0-1 units), preserving hue, saturation and alpha. */
export const shiftLightness = (hex: Hex, delta: number): Hex => {
  const rgba = hexToRgba(hex);
  const hsl = rgbaToHsl(rgba);
  return rgbaToHex(
    hslToRgba({ ...hsl, l: clamp(hsl.l + delta, 0, 1) }, rgba.a)
  );
};

/**
 * The dark-mode counterpart of a light-mode accent.
 *
 * A hue that reads as rich on a near-white page reads as muddy on a near-black
 * one, so the dark variant is lifted in lightness and pulled slightly toward
 * neutral saturation. The 10% figure matches what the interview used to ask the
 * user to confirm by hand.
 */
export const deriveDarkAccent = (accentLight: Hex): Hex => {
  const rgba = hexToRgba(accentLight);
  const { h, s, l } = rgbaToHsl(rgba);
  return rgbaToHex(
    hslToRgba(
      { h, s: clamp(s * 0.95, 0, 1), l: clamp(l + 0.1, 0, 0.85) },
      rgba.a
    )
  );
};

// ---------------------------------------------------------------------------
// Contrast
// ---------------------------------------------------------------------------

const channelLuminance = (value: number): number => {
  const c = value / 255;
  return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
};

/** WCAG 2.1 relative luminance. */
export const relativeLuminance = ({ r, g, b }: Rgba): number =>
  0.2126 * channelLuminance(r) +
  0.7152 * channelLuminance(g) +
  0.0722 * channelLuminance(b);

/**
 * WCAG 2.1 contrast ratio, 1..21.
 *
 * Alpha is ignored: both arguments are treated as opaque. Compositing a
 * translucent token against its actual backdrop is the caller's job, and the
 * engine only ever checks opaque pairs.
 */
export const contrastRatio = (a: Hex, b: Hex): number => {
  const la = relativeLuminance(hexToRgba(a));
  const lb = relativeLuminance(hexToRgba(b));
  const [hi, lo] = la > lb ? [la, lb] : [lb, la];
  return (hi + 0.05) / (lo + 0.05);
};

/** WCAG AA for body text. */
export const AA_NORMAL = 4.5;
/** WCAG AA for text >= 18.66px bold or 24px regular, and for UI component edges. */
export const AA_LARGE = 3;

export type ContrastGrade = "AAA" | "AA" | "AA Large" | "fail";

export const gradeContrast = (ratio: number): ContrastGrade => {
  if (ratio >= 7) {
    return "AAA";
  }
  if (ratio >= AA_NORMAL) {
    return "AA";
  }
  if (ratio >= AA_LARGE) {
    return "AA Large";
  }
  return "fail";
};

/**
 * Picks whichever of two foregrounds contrasts better against `background`.
 * Used for the preview's swatch labels and for the generated monogram, where
 * the mark has to stay legible against a background the user chose.
 */
export const bestForeground = (
  background: Hex,
  candidates: readonly Hex[]
): Hex => {
  let best = candidates[0] as Hex;
  let bestRatio = -1;
  for (const candidate of candidates) {
    const ratio = contrastRatio(background, candidate);
    if (ratio > bestRatio) {
      bestRatio = ratio;
      best = candidate;
    }
  }
  return best;
};
