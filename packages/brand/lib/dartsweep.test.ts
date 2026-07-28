import { describe, expect, test } from "bun:test";

import {
  addDartImport,
  isRadiusSweepTarget,
  rewriteFontFamilies,
  rewriteRadii,
} from "./dartsweep.ts";

const PKG = "acme_vision";

describe("isRadiusSweepTarget", () => {
  test("claims the app's widget tree", () => {
    expect(isRadiusSweepTarget("apps/mobile/lib/src/modules/home/ui/home_page.dart")).toBe(true);
  });

  test("leaves the recorder plugin alone - it cannot import from the app", () => {
    expect(isRadiusSweepTarget("packages/stera_recorder/lib/src/view.dart")).toBe(false);
  });

  test("ignores non-Dart files under the prefix", () => {
    expect(isRadiusSweepTarget("apps/mobile/lib/assets/thing.json")).toBe(false);
  });
});

describe("rewriteRadii", () => {
  test("converts on-scale literals and imports the scale", () => {
    const source = `import "package:${PKG}/src/core/theme/colors.dart";

Widget build() => Container(
  decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
);`;
    const result = rewriteRadii(source, PKG);

    expect(result.text).toContain("BorderRadius.circular(BrandShape.radiusMd)");
    expect(result.text).toContain(
      `import "package:${PKG}/src/core/theme/brand_shape.dart";`
    );
    expect(result.converted.get("md")).toBe(1);
  });

  test("maps each on-scale value to its own step", () => {
    const result = rewriteRadii(
      `a(BorderRadius.circular(4)) b(BorderRadius.circular(8)) c(BorderRadius.circular(16)) d(BorderRadius.circular(24)) e(BorderRadius.circular(999))`,
      PKG
    );
    expect(result.text).toContain("BrandShape.radiusXs");
    expect(result.text).toContain("BrandShape.radiusSm");
    expect(result.text).toContain("BrandShape.radiusLg");
    expect(result.text).toContain("BrandShape.radiusXl");
    expect(result.text).toContain("BrandShape.radiusFull");
  });

  test("claims the values that used to be off-scale one-offs", () => {
    const result = rewriteRadii(
      "Radius.circular(1.5) Radius.circular(30) Radius.circular(14) Radius.circular(6) Radius.circular(10) Radius.circular(20)",
      PKG
    );

    expect(result.text).toContain("BrandShape.radiusHairline");
    expect(result.text).toContain("BrandShape.radiusXlPlus");
    expect(result.text).toContain("BrandShape.radiusMdPlus");
    expect(result.text).toContain("BrandShape.radiusXsPlus");
    expect(result.text).toContain("BrandShape.radiusSmPlus");
    expect(result.text).toContain("BrandShape.radiusLgPlus");
    expect(result.skipped.size).toBe(0);
  });

  test("leaves a value no step claims alone and counts it", () => {
    const source = "Radius.circular(7) Radius.circular(13)";
    const result = rewriteRadii(source, PKG);

    expect(result.text).toBe(source);
    expect(result.converted.size).toBe(0);
    expect(result.skipped.get(7)).toBe(1);
    expect(result.skipped.get(13)).toBe(1);
  });

  test("a file with nothing to convert is returned untouched, import and all", () => {
    const source = "const x = 1;";
    expect(rewriteRadii(source, PKG).text).toBe(source);
  });

  test("handles the decimal spelling of an on-scale value", () => {
    expect(rewriteRadii("BorderRadius.circular(12.0)", PKG).text).toContain(
      "BrandShape.radiusMd"
    );
  });

  test("matches Radius.circular without also matching inside BorderRadius", () => {
    const result = rewriteRadii(
      "BorderRadius.only(topLeft: Radius.circular(16))",
      PKG
    );
    expect(result.text).toContain("BorderRadius.only(topLeft: Radius.circular(BrandShape.radiusLg))");
    expect(result.converted.get("lg")).toBe(1);
  });

  test("is idempotent: a second pass finds nothing", () => {
    const once = rewriteRadii("BorderRadius.circular(12)", PKG);
    const twice = rewriteRadii(once.text, PKG);
    expect(twice.text).toBe(once.text);
    expect(twice.converted.size).toBe(0);
  });
});

describe("rewriteFontFamilies", () => {
  const previous = {
    display: "EBGaramond",
    body: "Geist",
    mono: "GeistMono",
    accent: "Handjet",
  };

  test("routes each family to its role", () => {
    const source = `TextStyle(fontFamily: "EBGaramond"), TextStyle(fontFamily: "Geist"), TextStyle(fontFamily: "GeistMono"), TextStyle(fontFamily: "Handjet")`;
    const { text, hits } = rewriteFontFamilies(source, previous, PKG);

    expect(hits).toBe(4);
    expect(text).toContain("fontFamily: BrandFonts.display");
    expect(text).toContain("fontFamily: BrandFonts.body");
    expect(text).toContain("fontFamily: BrandFonts.mono");
    expect(text).toContain("fontFamily: BrandFonts.accent");
    expect(text).toContain(`import "package:${PKG}/src/core/theme/brand_fonts.dart";`);
  });

  test("leaves a family that fills no role as a literal", () => {
    const source = 'TextStyle(fontFamily: "JetBrainsMono")';
    const { text, hits } = rewriteFontFamilies(source, previous, PKG);
    expect(hits).toBe(0);
    expect(text).toBe(source);
  });

  test("is idempotent", () => {
    const once = rewriteFontFamilies('fontFamily: "Geist"', previous, PKG);
    const twice = rewriteFontFamilies(once.text, previous, PKG);
    expect(twice.hits).toBe(0);
    expect(twice.text).toBe(once.text);
  });

  test("follows the previous brand's families, not a fixed list", () => {
    const { text } = rewriteFontFamilies(
      'fontFamily: "Inter"',
      { ...previous, body: "Inter" },
      PKG
    );
    expect(text).toContain("fontFamily: BrandFonts.body");
  });
});

describe("addDartImport", () => {
  test("inserts after the last own-package import", () => {
    const source = `import "package:${PKG}/src/a.dart";
import "package:flutter/material.dart";`;
    const out = addDartImport(source, `import "package:${PKG}/src/b.dart";`);
    const lines = out.split("\n");
    expect(lines[1]).toBe(`import "package:${PKG}/src/b.dart";`);
  });

  test("falls back to before the first import when there are no own imports", () => {
    const source = `import "package:flutter/material.dart";`;
    const out = addDartImport(source, `import "package:${PKG}/src/b.dart";`);
    expect(out.split("\n")[0]).toBe(`import "package:${PKG}/src/b.dart";`);
  });

  test("does not duplicate an import that is already there", () => {
    const statement = `import "package:${PKG}/src/b.dart";`;
    expect(addDartImport(statement, statement)).toBe(statement);
  });
});
