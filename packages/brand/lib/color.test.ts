import { describe, expect, test } from "bun:test";

import {
  contrastRatio,
  deriveDarkAccent,
  gradeContrast,
  hexToCss,
  hexToCssRgba,
  hexToHsl,
  hexToRgba,
  hslToRgba,
  mix,
  parseHex,
  rgbaToHex,
  rgbaToHsl,
  shiftLightness,
} from "./color.ts";

describe("parseHex", () => {
  test("accepts every spelling", () => {
    expect(parseHex("0xFFE8A33D")).toBe("0xFFE8A33D");
    expect(parseHex("0xffe8a33d")).toBe("0xFFE8A33D");
    expect(parseHex("#E8A33D")).toBe("0xFFE8A33D");
    expect(parseHex("E8A33D")).toBe("0xFFE8A33D");
    expect(parseHex("  #e8a33d  ")).toBe("0xFFE8A33D");
  });

  test("expands the three-digit form", () => {
    expect(parseHex("#FFF")).toBe("0xFFFFFFFF");
    expect(parseHex("#1a2")).toBe("0xFF11AA22");
  });

  test("moves alpha from CSS's last position to Flutter's first", () => {
    expect(parseHex("#E8A33D80")).toBe("0x80E8A33D");
  });

  test("returns null rather than throwing, so derive.ts owns the message", () => {
    expect(parseHex("orange")).toBeNull();
    expect(parseHex("#12345")).toBeNull();
    expect(parseHex("")).toBeNull();
  });
});

describe("conversions", () => {
  test("round-trips through rgba", () => {
    expect(rgbaToHex(hexToRgba("0x80E8A33D"))).toBe("0x80E8A33D");
  });

  test("round-trips through hsl for a saturated colour", () => {
    const original = "0xFFE8A33D";
    const rgba = hexToRgba(original);
    expect(rgbaToHex(hslToRgba(rgbaToHsl(rgba), rgba.a))).toBe(original);
  });

  test("hexToCss drops alpha; hexToCssRgba keeps it", () => {
    expect(hexToCss("0x80E8A33D")).toBe("#E8A33D");
    expect(hexToCssRgba("0x99FFFFFF")).toBe("rgba(255, 255, 255, 0.600)");
  });

  test("a grey has no meaningful hue and zero saturation", () => {
    expect(hexToHsl("0xFF737373").s).toBe(0);
  });
});

describe("mix", () => {
  test("0 and 1 are the endpoints", () => {
    expect(mix("0xFF000000", "0xFFFFFFFF", 0)).toBe("0xFF000000");
    expect(mix("0xFF000000", "0xFFFFFFFF", 1)).toBe("0xFFFFFFFF");
  });

  test("halfway is halfway", () => {
    expect(mix("0xFF000000", "0xFFFFFFFF", 0.5)).toBe("0xFF808080");
  });

  test("alpha comes from the base, so tinting cannot make a token opaque", () => {
    // textInverseSecondary is 0x99FFFFFF and has to stay 60% transparent.
    expect(mix("0x99FFFFFF", "0xFFE8A33D", 0.5)).toBe("0x99F4D19E");
  });

  test("clamps out-of-range amounts instead of extrapolating", () => {
    expect(mix("0xFF000000", "0xFFFFFFFF", 5)).toBe("0xFFFFFFFF");
    expect(mix("0xFF000000", "0xFFFFFFFF", -5)).toBe("0xFF000000");
  });
});

describe("lightness", () => {
  test("shiftLightness moves lightness and keeps hue", () => {
    const lifted = shiftLightness("0xFF123456", 0.2);
    expect(hexToHsl(lifted).l).toBeGreaterThan(hexToHsl("0xFF123456").l);
    expect(Math.abs(hexToHsl(lifted).h - hexToHsl("0xFF123456").h)).toBeLessThan(2);
  });

  test("clamps at the ends rather than wrapping", () => {
    expect(shiftLightness("0xFFFFFFFF", 0.5)).toBe("0xFFFFFFFF");
    expect(shiftLightness("0xFF000000", -0.5)).toBe("0xFF000000");
  });

  test("deriveDarkAccent lifts a dark hue into something usable on a dark page", () => {
    const dark = deriveDarkAccent("0xFF123456");
    expect(hexToHsl(dark).l).toBeGreaterThan(hexToHsl("0xFF123456").l);
  });

  test("deriveDarkAccent will not run an already-bright accent up to white", () => {
    expect(hexToHsl(deriveDarkAccent("0xFFFFE9A0")).l).toBeLessThanOrEqual(0.86);
  });
});

describe("contrast", () => {
  test("the extremes are the WCAG extremes", () => {
    expect(contrastRatio("0xFF000000", "0xFFFFFFFF")).toBeCloseTo(21, 1);
    expect(contrastRatio("0xFF808080", "0xFF808080")).toBeCloseTo(1, 5);
  });

  test("is symmetric", () => {
    expect(contrastRatio("0xFF18191B", "0xFFF8F9FA")).toBeCloseTo(
      contrastRatio("0xFFF8F9FA", "0xFF18191B"),
      5
    );
  });

  test("grades against the AA and AAA thresholds", () => {
    expect(gradeContrast(21)).toBe("AAA");
    expect(gradeContrast(5)).toBe("AA");
    expect(gradeContrast(3.2)).toBe("AA Large");
    expect(gradeContrast(1.5)).toBe("fail");
  });
});
