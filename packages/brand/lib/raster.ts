/**
 * Image generation.
 *
 * `flutter_launcher_icons` does all the launcher-icon resizing itself from one
 * square master, so sharp is only needed to *produce* those masters - and to
 * accept an SVG, which libvips handles natively via librsvg. sharp rather than
 * macOS `sips` because this has to work on Linux CI too.
 *
 * sharp is imported lazily: a fork that supplies no artwork should not need a
 * native dependency to install just to rename itself.
 */

import { mkdir } from "node:fs/promises";
import { dirname } from "node:path";

import { hexToCss, hslToRgba, rgbaToHex, rgbaToHsl } from "./color.ts";
import type { Brand, Hex } from "./types.ts";
import type { Rgba } from "./color.ts";

/** The callable factory, i.e. sharp's default export - not the namespace. */
type Sharp = (typeof import("sharp"))["default"];

let cached: Sharp | null = null;

export const loadSharp = async (): Promise<Sharp> => {
  if (cached !== null) {
    return cached;
  }
  try {
    const module = await import("sharp");
    cached = module.default;
    return cached;
  } catch (cause) {
    throw new Error(
      `sharp is required to generate icons but could not be loaded. Run \`bun install\`, ` +
        `or remove the \`assets.*\` entries from packages/brand/brand.json to skip icon generation. ` +
        `(${cause instanceof Error ? cause.message : String(cause)})`
    );
  }
};

export const GENERATED_DIR = "packages/brand/generated";

export interface RasterTarget {
  source: string;
  output: string;
  size: number;
  /** Background for the padded area; transparent when omitted. */
  background?: string;
  fit?: "contain" | "cover";
}

/** Smallest acceptable master. Below this, upscaling to 1024 looks soft. */
export const MIN_ICON_SOURCE = 512;

export const probe = async (
  absolutePath: string
): Promise<{ width: number; height: number; format: string }> => {
  const sharp = await loadSharp();
  const meta = await sharp(absolutePath).metadata();
  return {
    width: meta.width ?? 0,
    height: meta.height ?? 0,
    format: meta.format ?? "unknown",
  };
};

/**
 * Renders `source` into a square PNG of `size`.
 *
 * `density: 512` only affects SVG input, where it controls the rasterisation
 * DPI - without it librsvg renders at the SVG's nominal size and the result is
 * blurry once scaled to 1024.
 */
export const square = async (
  sourceAbsolute: string,
  outputAbsolute: string,
  size: number,
  background?: string
): Promise<void> => {
  const sharp = await loadSharp();
  await mkdir(dirname(outputAbsolute), { recursive: true });
  await sharp(sourceAbsolute, { density: 512 })
    .resize(size, size, {
      fit: "contain",
      background: background ?? { r: 0, g: 0, b: 0, alpha: 0 },
    })
    .png({ compressionLevel: 9 })
    .toFile(outputAbsolute);
};

export const resizeTo = async (
  sourceAbsolute: string,
  outputAbsolute: string,
  width: number,
  height: number,
  fit: "contain" | "cover" = "cover"
): Promise<void> => {
  const sharp = await loadSharp();
  await mkdir(dirname(outputAbsolute), { recursive: true });
  await sharp(sourceAbsolute, { density: 512 })
    .resize(width, height, { fit, background: { r: 0, g: 0, b: 0, alpha: 0 } })
    .png({ compressionLevel: 9 })
    .toFile(outputAbsolute);
};

/**
 * Flattens a mark to a single-colour silhouette, for the Android themed-icon
 * monochrome layer. Used only when the fork supplies no dedicated monochrome
 * artwork; a hand-drawn one is almost always better.
 */
export const monochrome = async (
  sourceAbsolute: string,
  outputAbsolute: string,
  size: number
): Promise<void> => {
  const sharp = await loadSharp();
  await mkdir(dirname(outputAbsolute), { recursive: true });
  await sharp(sourceAbsolute, { density: 512 })
    .resize(size, size, { fit: "contain", background: { r: 0, g: 0, b: 0, alpha: 0 } })
    .greyscale()
    .normalise()
    .png({ compressionLevel: 9 })
    .toFile(outputAbsolute);
};

// ---------------------------------------------------------------------------
// Accent extraction
// ---------------------------------------------------------------------------

/**
 * Suggests a brand accent by finding the dominant chromatic hue in a logo.
 *
 * The interview used to ask for a hex, which is a strange question to put to
 * somebody who has just handed over their artwork - the answer is almost always
 * "the colour in the logo". This reads it off instead, and the answer is then
 * something to confirm rather than invent.
 *
 * Deliberately ignores three kinds of pixel: transparent ones (padding, not
 * design), near-neutral ones (a black wordmark on white has no accent to find),
 * and near-black/near-white ones (they carry a hue but it is noise). If nothing
 * survives, the mark is monochrome and the caller is told so rather than handed
 * a grey that would make the whole app look broken.
 */
export const sampleAccent = async (
  sourceAbsolute: string
): Promise<{ hex: Hex; coverage: number } | null> => {
  const sharp = await loadSharp();
  const size = 64;

  const { data } = await sharp(sourceAbsolute, { density: 256 })
    .resize(size, size, { fit: "inside", background: { r: 0, g: 0, b: 0, alpha: 0 } })
    .ensureAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });

  const BUCKETS = 24;
  const buckets: Array<{ count: number; weight: number; h: number; s: number; l: number }> =
    Array.from({ length: BUCKETS }, () => ({ count: 0, weight: 0, h: 0, s: 0, l: 0 }));

  let considered = 0;

  for (let index = 0; index + 3 < data.length; index += 4) {
    const alpha = data[index + 3] as number;
    if (alpha < 160) {
      continue;
    }
    considered += 1;

    const rgba: Rgba = {
      r: data[index] as number,
      g: data[index + 1] as number,
      b: data[index + 2] as number,
      a: 255,
    };
    const { h, s, l } = rgbaToHsl(rgba);
    if (s < 0.18 || l < 0.12 || l > 0.92) {
      continue;
    }

    const bucket = buckets[Math.min(BUCKETS - 1, Math.floor((h / 360) * BUCKETS))];
    if (bucket === undefined) {
      continue;
    }
    // Weighting by saturation lets a small, vivid mark outvote a large, washed
    // background - which matches how a person would name "the brand colour".
    const weight = s;
    bucket.count += 1;
    bucket.weight += weight;
    bucket.h += h * weight;
    bucket.s += s * weight;
    bucket.l += l * weight;
  }

  const best = buckets.reduce((a, b) => (b.weight > a.weight ? b : a));
  if (best.weight === 0 || considered === 0) {
    return null;
  }

  const h = best.h / best.weight;
  const s = best.s / best.weight;
  const l = best.l / best.weight;

  return {
    // Clamped into a range that works as a UI accent: a colour sampled from the
    // dark part of a gradient is still the brand's hue, but at l=0.15 it reads
    // as black everywhere the app would use it.
    hex: rgbaToHex(
      hslToRgba({
        h,
        s: Math.min(Math.max(s, 0.35), 0.95),
        l: Math.min(Math.max(l, 0.35), 0.68),
      })
    ),
    coverage: best.count / considered,
  };
};

// ---------------------------------------------------------------------------
// Placeholder monogram
// ---------------------------------------------------------------------------

/**
 * A geometric monogram, used when a fork has no artwork yet.
 *
 * This is a placeholder and the engine says so - it is a legible mark to build
 * and screenshot against, not a logo. `packages/brand/TODO.md` tells the user where to
 * drop real art.
 */
export const monogramSvg = (brand: Brand): string => {
  const initials = brand.brand.name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((word) => word.charAt(0).toUpperCase())
    .join("");

  const accent = hexToCss(brand.theme.brandAccentLight);
  const background = hexToCss(brand.assets.iconBackgroundColor);
  const fontSize = initials.length > 1 ? 380 : 520;

  return `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <!-- Placeholder monogram generated by packages/brand/apply.ts. Replace with real
       artwork at the path named in brand.json > assets.iconSource. -->
  <rect width="1024" height="1024" rx="220" fill="${background}"/>
  <circle cx="512" cy="512" r="392" fill="none" stroke="${accent}" stroke-width="16" opacity="0.35"/>
  <text x="512" y="512" fill="${accent}"
        font-family="Georgia, 'EB Garamond', 'Times New Roman', serif"
        font-size="${fontSize}" font-weight="600"
        text-anchor="middle" dominant-baseline="central">${initials}</text>
</svg>
`;
};
