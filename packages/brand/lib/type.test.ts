import { describe, expect, test } from "bun:test";

import { BrandConfigError, derive } from "./derive.ts";
import { buildBrandTypeDart } from "./generate.ts";
import {
  TYPE_SCALES,
  TYPE_STEPS,
  UPSTREAM_TYPE_STYLE,
  UPSTREAM_TYPE_WEIGHTS,
  resolveTypeScale,
  snapToTypeStep,
  snapToWeightRole,
} from "./type.ts";
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

describe("the type scale", () => {
  test("every style defines every step", () => {
    for (const [style, scale] of Object.entries(TYPE_SCALES)) {
      for (const step of TYPE_STEPS) {
        expect(scale[step], `${style}.${step}`).toBeDefined();
        expect(scale[step].size).toBeGreaterThan(0);
        expect(scale[step].lineHeight).toBeGreaterThan(0);
      }
    }
  });

  test("sizes increase monotonically across the ramp", () => {
    for (const [style, scale] of Object.entries(TYPE_SCALES)) {
      for (let i = 1; i < TYPE_STEPS.length; i += 1) {
        const previous = scale[TYPE_STEPS[i - 1] as (typeof TYPE_STEPS)[number]];
        const current = scale[TYPE_STEPS[i] as (typeof TYPE_STEPS)[number]];
        expect(
          current.size,
          `${style}: ${TYPE_STEPS[i]} must be larger than ${TYPE_STEPS[i - 1]}`
        ).toBeGreaterThan(previous.size);
      }
    }
  });

  test("line height is never smaller than the size", () => {
    // Set solid is fine for the display steps; set tighter than solid clips
    // descenders, and it is not something a fork should be able to reach for by
    // picking a style rather than by pinning a step on purpose.
    for (const [style, scale] of Object.entries(TYPE_SCALES)) {
      for (const step of TYPE_STEPS) {
        expect(
          scale[step].lineHeight,
          `${style}.${step}`
        ).toBeGreaterThanOrEqual(scale[step].size);
      }
    }
  });

  test("compact is tighter and spacious looser than default at every step", () => {
    for (const step of TYPE_STEPS) {
      expect(TYPE_SCALES.compact[step].size).toBeLessThanOrEqual(
        TYPE_SCALES.default[step].size
      );
      expect(TYPE_SCALES.spacious[step].size).toBeGreaterThanOrEqual(
        TYPE_SCALES.default[step].size
      );
    }
  });

  test("overrides are partial at the step level", () => {
    const scale = resolveTypeScale("default", { md: { size: 15 } });
    expect(scale.md.size).toBe(15);
    expect(scale.md.lineHeight).toBe(TYPE_SCALES.default.md.lineHeight);
    expect(scale.lg).toEqual(TYPE_SCALES.default.lg);
  });
});

describe("snapping upstream literals", () => {
  test("every size the widget tree used is claimed", () => {
    // The literals that were in apps/mobile/lib/src before the sweep. If a
    // future upstream introduces one that is off-scale, this is the test that
    // makes the decision explicit rather than silently leaving it behind.
    for (const literal of [10, 11, 12, 14, 16, 18, 20, 24, 28, 32]) {
      expect(snapToTypeStep(literal), `${literal}px`).not.toBeNull();
    }
  });

  test("an unrecognised size is left alone rather than guessed at", () => {
    expect(snapToTypeStep(13)).toBeNull();
    expect(snapToTypeStep(48)).toBeNull();
  });

  test("the four weights map to roles, others do not", () => {
    expect(snapToWeightRole(400)).toBe("regular");
    expect(snapToWeightRole(700)).toBe("bold");
    expect(snapToWeightRole(300)).toBeNull();
  });
});

describe("derive", () => {
  test("defaults to upstream's ramp and weights", () => {
    const brand = derive(minimal());
    expect(brand.theme.type.style).toBe(UPSTREAM_TYPE_STYLE);
    expect(brand.theme.type.scale).toEqual(TYPE_SCALES[UPSTREAM_TYPE_STYLE]);
    expect(brand.theme.type.weights).toEqual(UPSTREAM_TYPE_WEIGHTS);
  });

  test("a style plus a pinned step", () => {
    const brand = derive(
      minimal({
        theme: { type: { style: "compact", scale: { md: { lineHeight: 22 } } } },
      } as Partial<BrandInput>)
    );
    expect(brand.theme.type.scale.md.size).toBe(TYPE_SCALES.compact.md.size);
    expect(brand.theme.type.scale.md.lineHeight).toBe(22);
  });

  test("rejects an unknown style", () => {
    expect(() =>
      derive(minimal({ theme: { type: { style: "cramped" } } } as unknown as Partial<BrandInput>))
    ).toThrow(BrandConfigError);
  });

  test("rejects a weight Flutter cannot render", () => {
    expect(() =>
      derive(minimal({ theme: { type: { weights: { regular: 550 } } } } as Partial<BrandInput>))
    ).toThrow(BrandConfigError);
  });

  test("rejects a key that reaches nothing", () => {
    // `body` is a font *role*, not a weight role. Accepting it silently would
    // leave the fork at upstream's weights believing it had changed them.
    expect(() =>
      derive(minimal({ theme: { type: { weights: { body: 500 } } } } as unknown as Partial<BrandInput>))
    ).toThrow(BrandConfigError);
    expect(() =>
      derive(minimal({ theme: { type: { scale: { xxl: { size: 40 } } } } } as unknown as Partial<BrandInput>))
    ).toThrow(BrandConfigError);
  });

  test("rejects a non-positive measure", () => {
    expect(() =>
      derive(minimal({ theme: { type: { scale: { md: { size: 0 } } } } } as Partial<BrandInput>))
    ).toThrow(BrandConfigError);
  });
});

describe("buildBrandTypeDart", () => {
  test("upstream regenerates the literals already in the tree", () => {
    const dart = buildBrandTypeDart(UPSTREAM_BRAND);
    expect(dart).toContain("static const double sizeMd = 14;");
    expect(dart).toContain("static const double heightMd = 20 / 14;");
    expect(dart).toContain("static const FontWeight weightSemibold = FontWeight.w600;");
  });

  test("line height is emitted as the designed pair, not a decimal", () => {
    const dart = buildBrandTypeDart(UPSTREAM_BRAND);
    expect(dart).not.toMatch(/height\w+ = 1\.\d{3}/);
  });

  test("a moved weight reaches the generated file", () => {
    const brand = derive(
      minimal({ theme: { type: { weights: { semibold: 500 } } } } as Partial<BrandInput>)
    );
    expect(buildBrandTypeDart(brand)).toContain(
      "static const FontWeight weightSemibold = FontWeight.w500;"
    );
  });
});
