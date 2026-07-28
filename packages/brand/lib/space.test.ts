import { describe, expect, test } from "bun:test";

import { rewriteSpacing } from "./dartsweep.ts";
import { BrandConfigError, derive } from "./derive.ts";
import { buildBrandSpaceDart } from "./generate.ts";
import {
  SPACE_SCALES,
  SPACE_STEPS,
  UPSTREAM_SPACE_STYLE,
  resolveSpaceScale,
  snapToSpaceStep,
} from "./space.ts";
import { UPSTREAM_BRAND } from "./upstream.ts";
import type { BrandInput } from "./types.ts";

const minimal = (overrides: Partial<BrandInput> = {}): BrandInput =>
  ({
    brand: { name: "Acme Vision" },
    identifiers: { bundleId: "com.acmerobotics.vision" },
    urls: {
      website: "https://acmerobotics.com",
      contactEmail: "hello@acmerobotics.com",
      sourceRepo: "https://github.com/acme-robotics/acme-vision",
    },
    ...overrides,
  }) as BrandInput;

describe("the spacing scale", () => {
  test("every style defines every step", () => {
    for (const [style, scale] of Object.entries(SPACE_SCALES)) {
      for (const step of SPACE_STEPS) {
        expect(scale[step], `${style}.${step}`).toBeGreaterThanOrEqual(0);
      }
    }
  });

  test("steps increase monotonically", () => {
    for (const [style, scale] of Object.entries(SPACE_SCALES)) {
      for (let i = 1; i < SPACE_STEPS.length; i += 1) {
        expect(
          scale[SPACE_STEPS[i] as (typeof SPACE_STEPS)[number]],
          `${style}: ${SPACE_STEPS[i]} vs ${SPACE_STEPS[i - 1]}`
        ).toBeGreaterThan(scale[SPACE_STEPS[i - 1] as (typeof SPACE_STEPS)[number]]);
      }
    }
  });

  test("`none` is zero in every density", () => {
    // A zero pad is the absence of spacing, not a small amount of it. Scaling it
    // would put a 3px gap where the design says there is none.
    for (const scale of Object.values(SPACE_SCALES)) {
      expect(scale.none).toBe(0);
    }
  });

  test("tight is tighter and comfortable looser than default", () => {
    for (const step of SPACE_STEPS) {
      expect(SPACE_SCALES.tight[step]).toBeLessThanOrEqual(SPACE_SCALES.default[step]);
      expect(SPACE_SCALES.comfortable[step]).toBeGreaterThanOrEqual(
        SPACE_SCALES.default[step]
      );
    }
  });

  test("default reproduces the literals that were in the widget tree", () => {
    // If this drifts, `brand:apply` on an unmodified config stops being a no-op
    // and every fork inherits a layout change nobody asked for.
    expect(SPACE_SCALES.default).toEqual({
      none: 0, xxs: 2, xs: 4, xsPlus: 6, sm: 8, smPlus: 10, md: 12,
      mdPlus: 14, lg: 16, lgPlus: 20, xl: 24, xlPlus: 28, xxl: 32, huge: 64,
    });
  });
});

describe("snapping upstream literals", () => {
  test("every value the tree used is claimed", () => {
    for (const literal of [0, 2, 3, 4, 5, 6, 7, 8, 10, 11, 12, 14, 16, 18, 20, 24, 28, 32, 64]) {
      expect(snapToSpaceStep(literal), `${literal}px`).not.toBeNull();
    }
  });

  test("an unrecognised value is left alone rather than guessed at", () => {
    expect(snapToSpaceStep(13)).toBeNull();
    expect(snapToSpaceStep(100)).toBeNull();
  });
});

describe("rewriteSpacing", () => {
  const sweep = (source: string) => rewriteSpacing(source, "stera").text;

  test("rewrites EdgeInsets, single-axis SizedBox and flex spacing", () => {
    expect(sweep("padding: const EdgeInsets.all(16),")).toContain(
      "EdgeInsets.all(AppSpacing.lg)"
    );
    expect(
      sweep("padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),")
    ).toContain("EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.sm)");
    expect(sweep("const SizedBox(height: 12),")).toContain(
      "SizedBox(height: AppSpacing.md)"
    );
    expect(sweep("Column(spacing: 8,")).toContain("spacing: AppSpacing.sm");
  });

  test("adds the import only when something changed", () => {
    expect(sweep("const SizedBox(height: 12),")).toContain(
      'import "package:stera/src/core/theme/app_spacing.dart";'
    );
    const untouched = "final duration = Duration(milliseconds: 250);";
    expect(sweep(untouched)).toBe(untouched);
  });

  test("leaves numbers that are not spacing alone", () => {
    // The reason the sweep is anchored to three constructors rather than
    // matching bare numbers: the tree is full of numbers that are not gaps.
    for (const source of [
      "Duration(milliseconds: 300)",
      "opacity: 0.6",
      "Expanded(flex: 2)",
      "maxLines: 6",
      "BorderRadius.circular(12)",
    ]) {
      expect(sweep(source)).toBe(source);
    }
  });

  test("is idempotent", () => {
    const once = sweep("padding: const EdgeInsets.all(16),");
    expect(sweep(once)).toBe(once);
  });

  test("reports off-scale values rather than guessing", () => {
    const result = rewriteSpacing("padding: const EdgeInsets.all(13),", "stera");
    expect(result.skipped.get(13)).toBe(1);
    expect(result.text).toContain("EdgeInsets.all(13)");
  });
});

describe("derive and generate", () => {
  test("defaults to upstream's density", () => {
    const brand = derive(minimal());
    expect(brand.theme.space.style).toBe(UPSTREAM_SPACE_STYLE);
    expect(brand.theme.space.scale).toEqual(SPACE_SCALES[UPSTREAM_SPACE_STYLE]);
  });

  test("a density plus a pinned step", () => {
    const brand = derive(
      minimal({ theme: { space: { style: "tight", scale: { lg: 14 } } } } as Partial<BrandInput>)
    );
    expect(brand.theme.space.scale.lg).toBe(14);
    expect(brand.theme.space.scale.xl).toBe(SPACE_SCALES.tight.xl);
  });

  test("rejects an unknown density and an unknown step", () => {
    expect(() =>
      derive(minimal({ theme: { space: { style: "airy" } } } as unknown as Partial<BrandInput>))
    ).toThrow(BrandConfigError);
    expect(() =>
      derive(minimal({ theme: { space: { scale: { enormous: 80 } } } } as unknown as Partial<BrandInput>))
    ).toThrow(BrandConfigError);
  });

  test("overrides apply on top of the chosen style", () => {
    expect(resolveSpaceScale("comfortable", { md: 99 }).md).toBe(99);
    expect(resolveSpaceScale("comfortable", { md: 99 }).lg).toBe(
      SPACE_SCALES.comfortable.lg
    );
  });

  test("upstream regenerates the literals already in the tree", () => {
    const dart = buildBrandSpaceDart(UPSTREAM_BRAND);
    expect(dart).toContain("static const double lg = 16;");
    expect(dart).toContain("static const double none = 0;");
  });
});
