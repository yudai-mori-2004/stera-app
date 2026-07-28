import { describe, expect, test } from "bun:test";

import { derive } from "./derive.ts";
import {
  UPSTREAM_FONT_FAMILIES,
  bundledFontPath,
  familiesToDeclare,
  filesForFamily,
  isValidFamilyName,
  orphanedFontFiles,
  renderPubspecFonts,
} from "./fonts.ts";
import type { BrandFonts } from "./types.ts";

const fonts = (overrides: Partial<BrandFonts> = {}): BrandFonts => ({
  display: "EBGaramond",
  body: "Geist",
  mono: "GeistMono",
  accent: "Handjet",
  files: {},
  replaceBundled: false,
  ...overrides,
});

const minimal = (fontsInput: Record<string, unknown>) =>
  derive({
    brand: { name: "Acme Vision" },
    identifiers: { bundleId: "com.acmerobotics.vision" },
    urls: {
      website: "https://acmerobotics.com",
      contactEmail: "hello@acmerobotics.com",
      sourceRepo: "https://github.com/acme-robotics/acme-vision",
    },
    fonts: fontsInput,
  } as Parameters<typeof derive>[0]);

describe("family names", () => {
  test("accepts what Flutter can match against a pubspec entry", () => {
    expect(isValidFamilyName("Inter")).toBe(true);
    expect(isValidFamilyName("EBGaramond")).toBe(true);
    expect(isValidFamilyName("Geist2")).toBe(true);
  });

  test("rejects spellings that would silently fail to match", () => {
    expect(isValidFamilyName("SF Pro")).toBe(false);
    expect(isValidFamilyName("my-font")).toBe(false);
    expect(isValidFamilyName("2Fast")).toBe(false);
  });
});

describe("familiesToDeclare", () => {
  test("keeps every upstream family by default", () => {
    const declared = familiesToDeclare(fonts());
    for (const family of UPSTREAM_FONT_FAMILIES) {
      expect(declared).toContain(family);
    }
  });

  test("drops the unused ones when replaceBundled is set", () => {
    const declared = familiesToDeclare(fonts({ replaceBundled: true }));
    expect(declared).toEqual(["EBGaramond", "Geist", "GeistMono", "Handjet"]);
    expect(declared).not.toContain("JetBrainsMono");
  });

  test("always includes a family supplied by the fork", () => {
    const declared = familiesToDeclare(
      fonts({
        display: "Inter",
        files: { Inter: [{ path: "packages/brand/source/fonts/Inter.ttf", weight: null, style: "normal" }] },
        replaceBundled: true,
      })
    );
    expect(declared).toContain("Inter");
  });

  test("has no duplicates when one family fills two roles", () => {
    const declared = familiesToDeclare(fonts({ display: "Geist" }));
    expect(new Set(declared).size).toBe(declared.length);
  });
});

describe("renderPubspecFonts", () => {
  test("emits app-relative asset paths at the indentation the manifest needs", () => {
    const yaml = renderPubspecFonts(fonts({ replaceBundled: true }));
    expect(yaml).toContain("    - family: EBGaramond");
    expect(yaml).toContain("      fonts:");
    expect(yaml).toContain("        - asset: assets/fonts/EBGaramond-VariableFont_wght.ttf");
    expect(yaml).not.toContain("apps/mobile/assets");
  });

  test("carries weight and style through", () => {
    const yaml = renderPubspecFonts(fonts());
    expect(yaml).toContain("          style: italic");
    expect(yaml).toContain("          weight: 800");
  });

  test("points a supplied family at where the file will be bundled", () => {
    const yaml = renderPubspecFonts(
      fonts({
        display: "Inter",
        files: {
          Inter: [{ path: "packages/brand/source/fonts/Inter.ttf", weight: null, style: "normal" }],
        },
      })
    );
    expect(yaml).toContain("    - family: Inter");
    expect(yaml).toContain("        - asset: assets/fonts/Inter.ttf");
  });

  test("puts the four roles first so the block does not churn", () => {
    const yaml = renderPubspecFonts(fonts());
    const order = [...yaml.matchAll(/- family: (\w+)/g)].map((m) => m[1]);
    expect(order.slice(0, 4)).toEqual(["EBGaramond", "Geist", "GeistMono", "Handjet"]);
  });
});

describe("orphanedFontFiles", () => {
  test("is empty unless replaceBundled is set", () => {
    expect(orphanedFontFiles(fonts())).toEqual([]);
  });

  test("lists the faces no declared family still uses", () => {
    const orphans = orphanedFontFiles(fonts({ replaceBundled: true }));
    expect(orphans).toContain("apps/mobile/assets/fonts/JetBrainsMono-VariableFont_wght.ttf");
    expect(orphans).not.toContain("apps/mobile/assets/fonts/Geist-VariableFont_wght.ttf");
  });
});

describe("bundledFontPath", () => {
  test("flattens a source path into the app's font directory", () => {
    expect(
      bundledFontPath({ path: "packages/brand/source/fonts/Inter.ttf", weight: null, style: "normal" })
    ).toBe("apps/mobile/assets/fonts/Inter.ttf");
  });
});

describe("filesForFamily", () => {
  test("prefers the fork's files over upstream's", () => {
    const supplied = { path: "x/Inter.ttf", weight: null, style: "normal" as const };
    expect(filesForFamily(fonts({ files: { Geist: [supplied] } }), "Geist")).toEqual([supplied]);
  });

  test("falls back to the upstream asset", () => {
    expect(filesForFamily(fonts(), "Geist")[0]?.path).toBe(
      "apps/mobile/assets/fonts/Geist-VariableFont_wght.ttf"
    );
  });
});

describe("derive(fonts)", () => {
  test("defaults to the app's own faces", () => {
    expect(minimal({}).fonts.display).toBe("EBGaramond");
  });

  test("accepts a bare path as shorthand for a font file", () => {
    const brand = minimal({
      display: "Inter",
      files: { Inter: ["packages/brand/source/fonts/Inter.ttf"] },
    });
    expect(brand.fonts.files.Inter).toEqual([
      { path: "packages/brand/source/fonts/Inter.ttf", weight: null, style: "normal" },
    ]);
  });

  test("refuses a family that is neither bundled nor supplied", () => {
    // Flutter would render this as the system face without an error, so it has
    // to fail here or it ships as silently wrong typography.
    expect(() => minimal({ display: "Inter" })).toThrow(/neither bundled/);
  });

  test("allows naming another already-bundled family", () => {
    expect(minimal({ display: "Geist" }).fonts.display).toBe("Geist");
  });

  test("rejects a family name the pubspec could not match", () => {
    expect(() => minimal({ display: "SF Pro" })).toThrow();
  });

  test("rejects an empty file list", () => {
    expect(() => minimal({ display: "Inter", files: { Inter: [] } })).toThrow();
  });

  test("rejects an out-of-range weight", () => {
    expect(() =>
      minimal({ display: "Inter", files: { Inter: [{ path: "x.ttf", weight: 1200 }] } })
    ).toThrow();
  });
});
