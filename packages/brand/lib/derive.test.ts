import { describe, expect, test } from "bun:test";

import { hexToHsl } from "./color.ts";
import {
  BrandConfigError,
  derive,
  hexToCss,
  hexToRgba,
  jvmPackage,
  kebab,
  normalizeHex,
  pascal,
  snake,
} from "./derive.ts";
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

describe("string helpers", () => {
  test("kebab", () => {
    expect(kebab("Acme Vision")).toBe("acme-vision");
    expect(kebab("  Acme   Vision!!  ")).toBe("acme-vision");
    expect(kebab("Café Robotics")).toBe("cafe-robotics");
    expect(kebab("A_B")).toBe("a-b");
  });

  test("snake", () => {
    expect(snake("Acme Vision")).toBe("acme_vision");
    expect(snake("Acme-Vision")).toBe("acme_vision");
  });

  test("pascal", () => {
    expect(pascal("acme_vision_recorder")).toBe("AcmeVisionRecorder");
    expect(pascal("stera_recorder")).toBe("SteraRecorder");
  });
});

describe("jvmPackage", () => {
  test("passes through a clean bundle id", () => {
    expect(jvmPackage("com.acmerobotics.vision")).toBe("com.acmerobotics.vision");
  });

  test("leaves `open` alone - it is not a Java keyword", () => {
    expect(jvmPackage("open.fpvlabs.stera")).toBe("open.fpvlabs.stera");
  });

  test("escapes segments that are keywords", () => {
    expect(jvmPackage("com.new.app")).toBe("com.new_.app");
    expect(jvmPackage("io.is.thing")).toBe("io.is_.thing");
    expect(jvmPackage("com.object.x")).toBe("com.object_.x");
  });
});

describe("bundle id validation", () => {
  test("accepts reverse-DNS", () => {
    expect(() => derive(minimal())).not.toThrow();
  });

  const bad = [
    "novdots",
    "Com.Acme.App",
    "com.acme.",
    "com..acme",
    "1com.acme.app",
    "com.acme.app-name",
    "com.acme.1app",
  ];
  for (const bundleId of bad) {
    test(`rejects "${bundleId}"`, () => {
      expect(() =>
        derive(minimal({ identifiers: { bundleId } } as Partial<BrandInput>))
      ).toThrow(BrandConfigError);
    });
  }

  test("rejects reusing the upstream bundle id", () => {
    expect(() =>
      derive(
        minimal({
          identifiers: { bundleId: "open.fpvlabs.stera" },
        } as Partial<BrandInput>),
        { upstream: UPSTREAM_BRAND }
      )
    ).toThrow(/identical to the upstream/);
  });
});

describe("dart package validation", () => {
  test("rejects a reserved word", () => {
    expect(() => derive(minimal({ brand: { name: "Class" } } as Partial<BrandInput>))).toThrow(
      /reserved word/
    );
  });

  test("rejects a name colliding with a pubspec dependency", () => {
    expect(() =>
      derive(minimal({ brand: { name: "Drift" } } as Partial<BrandInput>), {
        pubspecDependencies: ["drift", "flutter"],
      })
    ).toThrow(/collides with an existing pubspec dependency/);
  });

  test("rejects a name with no alphanumerics", () => {
    expect(() => derive(minimal({ brand: { name: "!!!" } } as Partial<BrandInput>))).toThrow(
      /no alphanumeric/
    );
  });
});

describe("derivation", () => {
  const b = derive(minimal({ brand: { name: "Acme Vision", legalEntity: "Acme Robotics, Inc." } } as Partial<BrandInput>));

  test("identifiers", () => {
    expect(b.brand.slug).toBe("acme-vision");
    expect(b.brand.shortName).toBe("Acme");
    expect(b.identifiers.dartPackage).toBe("acme_vision");
    expect(b.identifiers.npmScope).toBe("@acme-vision");
    expect(b.identifiers.kotlinPackage).toBe("com.acmerobotics.vision");
    expect(b.identifiers.recorder.dartPackage).toBe("acme_vision_recorder");
    expect(b.identifiers.recorder.pluginClass).toBe("AcmeVisionRecorderPlugin");
    expect(b.identifiers.recorder.swiftObjcTarget).toBe("acme_vision_recorder_objc");
    expect(b.identifiers.recorder.kotlinPackage).toBe(
      "com.acmerobotics.vision.ar_recorder"
    );
    expect(b.identifiers.mcapWriterLibrary).toBe("acme_vision/1.0");
    expect(b.identifiers.systemdServiceName).toBe("acme-vision-server");
    expect(b.identifiers.r2Bucket).toBe("acme-vision-uploads");
    expect(b.identifiers.bookmarkKeyPrefix).toBe("com.acmerobotics.vision.bookmark.");
  });

  test("the app ids collapse to one", () => {
    expect(b.identifiers.androidApplicationId).toBe(b.identifiers.bundleId);
    expect(b.legacy.iosBundleId).toBe(b.identifiers.bundleId);
  });

  test("urls", () => {
    expect(b.urls.termsAndConditions).toBe("https://acmerobotics.com/terms");
    expect(b.urls.privacyPolicy).toBe("https://acmerobotics.com/privacy");
    expect(b.urls.apiHostProd).toBe("app.acmerobotics.com");
    expect(b.urls.discordInvite).toBeNull();
  });

  test("an unpublished fork gets no update feed, so the updater stays off", () => {
    expect(b.urls.playStoreAppId).toBeNull();
    expect(b.urls.appStoreId).toBeNull();
    expect(b.urls.updateFeed).toBeNull();
  });

  test("update urls round-trip when the fork has published", () => {
    const published = derive(
      minimal({
        urls: {
          website: "https://acmerobotics.com",
          contactEmail: "hello@acmerobotics.com",
          sourceRepo: "https://github.com/acme-robotics/acme-vision",
          playStoreAppId: "com.acmerobotics.vision",
          appStoreId: "6501234567",
          updateFeed: "https://acmerobotics.com/appcast.xml",
        },
      } as Partial<BrandInput>)
    );
    expect(published.urls.playStoreAppId).toBe("com.acmerobotics.vision");
    expect(published.urls.appStoreId).toBe("6501234567");
    expect(published.urls.updateFeed).toBe("https://acmerobotics.com/appcast.xml");
  });

  test("copy", () => {
    expect(b.copy.appTitle).toBe("Acme Vision by Acme Robotics, Inc.");
    expect(b.copy.splashTitle).toBe("Acme Vision");
    expect(b.copy.splashSubtitle).toBe("by Acme Robotics, Inc.");
    expect(b.copy.iosUsageDescriptions.camera).toContain("Acme Vision uses your camera");
  });

  test("apple signing is never inherited from upstream", () => {
    expect(b.apple.developmentTeam).toBeNull();
    expect(b.apple.signInServiceId).toBe("com.acmerobotics.vision.signin");
  });

  test("attribution defaults on", () => {
    expect(b.attribution.enabled).toBe(true);
    expect(b.attribution.text).toBe("Powered by Stera");
    expect(b.attribution.upstreamRepo).toBe("https://github.com/fpv-labs/stera-app");
  });

  test("trailing slashes are stripped from urls", () => {
    const t = derive(
      minimal({
        urls: {
          website: "https://acmerobotics.com/",
          contactEmail: "hello@acmerobotics.com",
          sourceRepo: "https://github.com/acme-robotics/acme-vision/",
        },
      } as Partial<BrandInput>)
    );
    expect(t.urls.website).toBe("https://acmerobotics.com");
    expect(t.urls.sourceRepo).toBe("https://github.com/acme-robotics/acme-vision");
    expect(t.urls.termsAndConditions).toBe("https://acmerobotics.com/terms");
  });

  test("is deterministic", () => {
    expect(derive(minimal())).toEqual(derive(minimal()));
  });

  test("re-deriving a derived brand is a fixed point", () => {
    const once = derive(minimal());
    expect(derive(once as unknown as BrandInput)).toEqual(once);
  });
});

describe("colour handling", () => {
  test("normalizeHex accepts every form", () => {
    expect(normalizeHex("#E8A33D", "x")).toBe("0xFFE8A33D");
    expect(normalizeHex("E8A33D", "x")).toBe("0xFFE8A33D");
    expect(normalizeHex("0xffe8a33d", "x")).toBe("0xFFE8A33D");
    // CSS #RRGGBBAA -> Flutter 0xAARRGGBB
    expect(normalizeHex("#E8A33D80", "x")).toBe("0x80E8A33D");
  });

  test("normalizeHex expands the three-digit CSS form", () => {
    expect(normalizeHex("#FFF", "x")).toBe("0xFFFFFFFF");
    expect(normalizeHex("#1a2", "x")).toBe("0xFF11AA22");
  });

  test("normalizeHex rejects nonsense", () => {
    expect(() => normalizeHex("orange", "theme.brandAccentLight")).toThrow(
      BrandConfigError
    );
    expect(() => normalizeHex("#12345", "x")).toThrow();
    expect(() => normalizeHex("", "x")).toThrow();
  });

  test("hexToRgba", () => {
    expect(hexToRgba("0xFFE8A33D")).toEqual({ a: 255, r: 232, g: 163, b: 61 });
  });

  test("hexToCss drops alpha", () => {
    expect(hexToCss("0xFFE8A33D")).toBe("#E8A33D");
  });

  test("dark accent is lifted off the light one rather than copied", () => {
    const b = derive(
      minimal({ theme: { brandAccentLight: "#123456" } } as Partial<BrandInput>)
    );
    // Same hue, higher lightness: the light accent reads muddy on a dark page.
    expect(b.theme.brandAccentDark).not.toBe("0xFF123456");
    expect(hexToHsl(b.theme.brandAccentDark).l).toBeGreaterThan(
      hexToHsl("0xFF123456").l
    );
    expect(Math.abs(hexToHsl(b.theme.brandAccentDark).h - hexToHsl("0xFF123456").h)).toBeLessThan(2);
  });

  test("an explicit dark accent is used verbatim", () => {
    const b = derive(
      minimal({
        theme: { brandAccentLight: "#123456", brandAccentDark: "#654321" },
      } as Partial<BrandInput>)
    );
    expect(b.theme.brandAccentDark).toBe("0xFF654321");
  });

  test("theme overrides require both light and dark", () => {
    expect(() =>
      derive(
        minimal({
          theme: { overrides: { textPrimary: { light: "#000000" } } },
        } as unknown as Partial<BrandInput>)
      )
    ).toThrow(/both a `light` and a `dark`/);
  });
});

describe("the upstream literal is self-consistent", () => {
  test("its recorder identifiers match the real tree", () => {
    expect(UPSTREAM_BRAND.identifiers.recorder.kotlinPackage).toBe(
      `${UPSTREAM_BRAND.identifiers.kotlinPackage}.ar_recorder`
    );
  });

  test("it records the real three-way id disagreement", () => {
    expect(UPSTREAM_BRAND.identifiers.androidApplicationId).toBe("open.fpvlabs.stera");
    expect(UPSTREAM_BRAND.legacy.iosBundleId).toBe("com.fpvlabs.fpvlabs");
    expect(UPSTREAM_BRAND.legacy.playStoreAppId).toBe("com.fpvlabs.fpv");
    expect(UPSTREAM_BRAND.legacy.iosBundleId).not.toBe(
      UPSTREAM_BRAND.identifiers.androidApplicationId
    );
  });

  test("attribution is off upstream - a fork turns it on", () => {
    expect(UPSTREAM_BRAND.attribution.enabled).toBe(false);
  });
});

/** derive() applied to the minimal fixture - most assertions below want the resolved brand. */
const built = (overrides: Partial<BrandInput> = {}) => derive(minimal(overrides));

describe("theme.tint", () => {
  test("defaults to 0, so applying an unconfigured brand moves no neutral", () => {
    const b = built({});
    expect(b.theme.tint).toBe(0);
    expect(b.theme.palette.surfacePrimary?.light).toBe("0xFFF8F9FA");
  });

  test("pulls the neutrals toward the accent", () => {
    const b = built({
      theme: { brandAccentLight: "#3D8AE8", tint: 0.5 },
    } as Partial<BrandInput>);
    expect(b.theme.palette.surfacePrimary?.light).not.toBe("0xFFF8F9FA");
  });

  test("rejects a value outside 0..1", () => {
    expect(() => built({ theme: { tint: 2 } } as Partial<BrandInput>)).toThrow(
      BrandConfigError
    );
    expect(() => built({ theme: { tint: -1 } } as Partial<BrandInput>)).toThrow();
  });

  test("refuses a tint that breaks a pair which met AA upstream", () => {
    expect(() =>
      built({ theme: { brandAccentLight: "#3D8AE8", tint: 1 } } as Partial<BrandInput>)
    ).toThrow(/regresses contrast/);
  });

  test("allowLowContrast is the escape hatch, and it is opt-in", () => {
    const b = built({
      theme: { brandAccentLight: "#3D8AE8", tint: 1, allowLowContrast: true },
    } as Partial<BrandInput>);
    expect(b.theme.tint).toBe(1);
  });
});

describe("theme.overrides", () => {
  test("an unknown token is an error, not a constant nothing reads", () => {
    expect(() =>
      built({
        theme: { overrides: { textPrimry: { light: "#111", dark: "#EEE" } } },
      } as Partial<BrandInput>)
    ).toThrow(/is not a colour token/);
  });

  test("a known token reaches the resolved palette", () => {
    const b = built({
      theme: { overrides: { surfaceTertiary: { light: "#F0EDE4", dark: "#2A2C30" } } },
    } as Partial<BrandInput>);
    expect(b.theme.palette.surfaceTertiary).toEqual({
      light: "0xFFF0EDE4",
      dark: "0xFF2A2C30",
    });
  });

  test("an override that breaks a contract pair is refused like any other regression", () => {
    expect(() =>
      built({
        // Text the same colour as the page it sits on.
        theme: { overrides: { surfacePrimary: { light: "#18191B", dark: "#FFFFFF" } } },
      } as Partial<BrandInput>)
    ).toThrow(/regresses contrast/);
  });
});

describe("theme.shape", () => {
  test("defaults to the upstream geometry", () => {
    const b = built({});
    expect(b.theme.shape.style).toBe("soft");
    expect(b.theme.shape.scale.md).toBe(12);
  });

  test("a style selects a whole scale", () => {
    const b = built({ theme: { shape: { style: "pill" } } } as Partial<BrandInput>);
    expect(b.theme.shape.scale.md).toBe(26);
  });

  test("a per-step override wins over the style", () => {
    const b = built({
      theme: { shape: { style: "pill", scale: { md: 3 } } },
    } as Partial<BrandInput>);
    expect(b.theme.shape.scale.md).toBe(3);
    expect(b.theme.shape.scale.lg).toBe(34);
  });

  test("rejects an unknown style and a negative radius", () => {
    expect(() =>
      built({ theme: { shape: { style: "squircle" } } } as unknown as Partial<BrandInput>)
    ).toThrow(/is not a shape style/);
    expect(() =>
      built({ theme: { shape: { scale: { md: -1 } } } } as Partial<BrandInput>)
    ).toThrow();
  });
});

describe("assets.logo fallback", () => {
  test("the in-app logo inherits the icon rather than staying upstream's", () => {
    const b = built({
      assets: { iconSource: "packages/brand/source/icon.png" },
    } as Partial<BrandInput>);
    expect(b.assets.logoLight).toBe("packages/brand/source/icon.png");
    expect(b.assets.logoDark).toBe("packages/brand/source/icon.png");
  });

  test("an explicit dark logo wins", () => {
    const b = built({
      assets: {
        iconSource: "packages/brand/source/icon.png",
        logoDark: "packages/brand/source/logo_dark.png",
      },
    } as Partial<BrandInput>);
    expect(b.assets.logoDark).toBe("packages/brand/source/logo_dark.png");
  });

  test("the foreground layer is preferred over the full icon", () => {
    const b = built({
      assets: {
        iconSource: "packages/brand/source/icon.png",
        iconForeground: "packages/brand/source/fg.png",
      },
    } as Partial<BrandInput>);
    expect(b.assets.logoLight).toBe("packages/brand/source/fg.png");
  });
});
