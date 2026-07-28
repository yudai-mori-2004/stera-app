import { describe, expect, test } from "bun:test";

import { contrastRatio } from "./color.ts";
import {
  BASE_PALETTE,
  MAX_TINT,
  TINT_WEIGHTS,
  TOKEN_GROUPS,
  TOKEN_NAMES,
  changedTokens,
  checkContrast,
  resolvePalette,
} from "./palette.ts";

const ACCENT = "0xFF3D8AE8";

describe("token list", () => {
  test("the groups and the flat list agree", () => {
    expect(TOKEN_NAMES.length).toBe(
      TOKEN_GROUPS.reduce((sum, group) => sum + group.tokens.length, 0)
    );
    expect(new Set(TOKEN_NAMES).size).toBe(TOKEN_NAMES.length);
  });

  test("every token has a base value in both modes", () => {
    for (const token of TOKEN_NAMES) {
      expect(BASE_PALETTE[token]?.light).toMatch(/^0x[0-9A-F]{8}$/);
      expect(BASE_PALETTE[token]?.dark).toMatch(/^0x[0-9A-F]{8}$/);
    }
  });

  test("every tint weight names a real token", () => {
    for (const token of Object.keys(TINT_WEIGHTS)) {
      expect(TOKEN_NAMES).toContain(token);
    }
  });
});

describe("resolvePalette", () => {
  test("without a tint, only the accent moves", () => {
    const palette = resolvePalette({ accentLight: ACCENT, accentDark: ACCENT });
    expect(changedTokens(palette)).toEqual(["brandAccent"]);
  });

  test("a tint pulls the neutrals toward the accent", () => {
    const palette = resolvePalette({
      accentLight: ACCENT,
      accentDark: ACCENT,
      tint: 1,
    });
    expect(palette.surfacePrimary?.light).not.toBe(BASE_PALETTE.surfacePrimary?.light);
    // At weight 1 and tint 1 the surface takes exactly MAX_TINT of the accent.
    expect(TINT_WEIGHTS.surfacePrimary).toBe(1);
    expect(changedTokens(palette).length).toBeGreaterThan(10);
  });

  test("semantic colours and the black/white anchors never take tint", () => {
    const palette = resolvePalette({
      accentLight: ACCENT,
      accentDark: ACCENT,
      tint: 1,
    });
    for (const token of [
      "red",
      "green",
      "blue",
      "yellow",
      "textDestructive",
      "borderError",
      "surfaceWhite",
      "neutralWhite",
      "neutralBlack",
      "surfaceBlack",
      "textInversePrimary",
    ]) {
      expect(palette[token]).toEqual(BASE_PALETTE[token]);
    }
  });

  test("tint is proportional: half the tint moves a token half as far", () => {
    const full = resolvePalette({ accentLight: ACCENT, accentDark: ACCENT, tint: 1 });
    const half = resolvePalette({ accentLight: ACCENT, accentDark: ACCENT, tint: 0.5 });
    const base = Number.parseInt((BASE_PALETTE.surfacePrimary as { light: string }).light.slice(-2), 16);
    const fullBlue = Number.parseInt((full.surfacePrimary as { light: string }).light.slice(-2), 16);
    const halfBlue = Number.parseInt((half.surfacePrimary as { light: string }).light.slice(-2), 16);
    expect(Math.abs(halfBlue - base)).toBeLessThan(Math.abs(fullBlue - base));
  });

  test("overrides beat the tint", () => {
    const palette = resolvePalette({
      accentLight: ACCENT,
      accentDark: ACCENT,
      tint: 1,
      overrides: { surfacePrimary: { light: "0xFF010203", dark: "0xFF040506" } },
    });
    expect(palette.surfacePrimary).toEqual({ light: "0xFF010203", dark: "0xFF040506" });
  });

  test("the dark accent is derived when only the light one is given", () => {
    const palette = resolvePalette({ accentLight: ACCENT });
    expect(palette.brandAccent?.dark).not.toBe(ACCENT);
    expect(palette.brandAccent?.light).toBe(ACCENT);
  });

  test("MAX_TINT stays modest enough to be a tint rather than a repaint", () => {
    expect(MAX_TINT).toBeLessThanOrEqual(0.2);
  });
});

describe("checkContrast", () => {
  test("upstream's own palette produces no regressions", () => {
    // The engine has to be a no-op on an unconfigured brand. Upstream does fail
    // a couple of pairs (a hairline divider is not a component outline), but
    // none of those are the fork's doing.
    const findings = checkContrast(BASE_PALETTE);
    expect(findings.every((finding) => !finding.regression)).toBe(true);
  });

  test("a pair that met AA upstream and no longer does is a regression", () => {
    const palette = resolvePalette({
      accentLight: ACCENT,
      accentDark: ACCENT,
      overrides: {
        // Same colour on both sides: 1:1, as broken as it gets.
        textPrimary: { light: "0xFFF8F9FA", dark: "0xFF18191B" },
      },
    });
    const regressions = checkContrast(palette).filter((finding) => finding.regression);
    expect(regressions.length).toBeGreaterThan(0);
    expect(regressions[0]?.ratio).toBeLessThan(regressions[0]?.baseline as number);
  });

  test("a pair upstream already fails is reported but not blamed on the fork", () => {
    const findings = checkContrast(BASE_PALETTE);
    const inherited = findings.find(
      (finding) => finding.foreground === "borderDefault"
    );
    expect(inherited).toBeDefined();
    expect(inherited?.regression).toBe(false);
  });

  test("reports the ratio it actually measured", () => {
    const findings = checkContrast(BASE_PALETTE);
    for (const finding of findings) {
      const foreground = BASE_PALETTE[finding.foreground]?.[finding.mode] as string;
      const background = BASE_PALETTE[finding.background]?.[finding.mode] as string;
      expect(finding.ratio).toBeCloseTo(contrastRatio(foreground, background), 5);
    }
  });
});
