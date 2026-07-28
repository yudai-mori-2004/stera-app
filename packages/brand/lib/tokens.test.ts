import { describe, expect, test } from "bun:test";

import { derive } from "./derive.ts";
import { applyTokens, buildTokens, findStale, rewrite, staleTokensOf } from "./tokens.ts";
import { UPSTREAM_BRAND } from "./upstream.ts";
import type { Brand } from "./types.ts";

const ACME: Brand = derive({
  brand: { name: "Acme Vision", legalEntity: "Acme Robotics, Inc." },
  identifiers: { bundleId: "com.acmerobotics.vision" },
  urls: {
    website: "https://acmerobotics.com",
    contactEmail: "hello@acmerobotics.com",
    sourceRepo: "https://github.com/acme-robotics/acme-vision",
  },
});

const RULES = buildTokens(UPSTREAM_BRAND, ACME);
const go = (input: string): string => rewrite(input, RULES);

describe("adjacency hazards - the reason this engine exists", () => {
  test("does not corrupt `sisteransi` in bun.lock", () => {
    const line = `    "sisteransi": ["sisteransi@1.0.5", "", {}, "sha512-aBc"],`;
    expect(go(line)).toBe(line);
  });

  test("does not corrupt other real substring carriers", () => {
    for (const word of ["sisteransi", "asteroid", "steradian", "hysteresis"]) {
      expect(go(word)).toBe(word);
    }
  });

  test("rewrites the recorder example iOS bundle id as a unit", () => {
    expect(go("open.fpvlabs.steraRecorderExample")).toBe(
      "com.acmerobotics.vision.recorderExample"
    );
  });

  test("never leaves a half-rewritten identifier", () => {
    const out = go("open.fpvlabs.steraRecorderExample.RunnerTests");
    expect(out).not.toContain("stera");
    expect(out).toBe("com.acmerobotics.vision.recorderExample.RunnerTests");
  });
});

describe("longest-match ordering", () => {
  test("recorder imports beat app imports", () => {
    expect(go('import "package:stera_recorder/stera_recorder.dart";')).toBe(
      'import "package:acme_vision_recorder/acme_vision_recorder.dart";'
    );
  });

  test("app imports rewrite cleanly", () => {
    expect(go('import "package:stera/src/core/theme/colors.dart";')).toBe(
      'import "package:acme_vision/src/core/theme/colors.dart";'
    );
  });

  test("recorder Kotlin package beats app Kotlin package", () => {
    expect(go("package open.fpvlabs.stera.ar_recorder.data")).toBe(
      "package com.acmerobotics.vision.ar_recorder.data"
    );
  });

  test("app Kotlin package still rewrites on its own", () => {
    expect(go("package open.fpvlabs.stera.video_picker")).toBe(
      "package com.acmerobotics.vision.video_picker"
    );
  });

  test("the slash-separated package path is rewritten whole", () => {
    // apps/mobile/CLAUDE.md documents this directory. Rewriting only the last
    // segment would produce `open/fpvlabs/acme_vision`, which does not exist.
    expect(go("android/app/src/main/kotlin/open/fpvlabs/stera/<module>/")).toBe(
      "android/app/src/main/kotlin/com/acmerobotics/vision/<module>/"
    );
    expect(go("kotlin/open/fpvlabs/stera/ar_recorder/data")).toBe(
      "kotlin/com/acmerobotics/vision/ar_recorder/data"
    );
    expect(go("kotlin/open/fpvlabs/stera_recorder_example/MainActivity.kt")).toBe(
      "kotlin/com/acmerobotics/vision/recorder_example/MainActivity.kt"
    );
  });

  test("plugin class beats the bare recorder package name", () => {
    expect(go("class SteraRecorderPlugin : FlutterPlugin {")).toBe(
      "class AcmeVisionRecorderPlugin : FlutterPlugin {"
    );
  });

  test("the objc target beats the plain target", () => {
    expect(go("import stera_recorder_objc")).toBe("import acme_vision_recorder_objc");
    expect(go("target(name: \"stera_recorder\")")).toBe(
      'target(name: "acme_vision_recorder")'
    );
  });

  test("app title beats subtitle beats bare org name", () => {
    expect(go('title: "Stera by FPV Labs",')).toBe(
      'title: "Acme Vision by Acme Robotics, Inc.",'
    );
    expect(go('Text("by FPV Labs")')).toBe('Text("by Acme Robotics, Inc.")');
    expect(go("Copyright FPV Labs")).toBe("Copyright Acme Robotics, Inc.");
  });
});

describe("the three-way app id mismatch is normalised", () => {
  test("all of them collapse onto one bundle id", () => {
    expect(go("PRODUCT_BUNDLE_IDENTIFIER = com.fpvlabs.fpvlabs;")).toBe(
      "PRODUCT_BUNDLE_IDENTIFIER = com.acmerobotics.vision;"
    );
    expect(go("applicationId = \"open.fpvlabs.stera\"")).toBe(
      'applicationId = "com.acmerobotics.vision"'
    );
    expect(go("details?id=com.fpvlabs.fpv")).toBe(
      "details?id=com.acmerobotics.vision"
    );
  });

  test("the iOS test target suffix survives", () => {
    expect(go("com.fpvlabs.fpvlabs.RunnerTests")).toBe(
      "com.acmerobotics.vision.RunnerTests"
    );
  });
});

describe("real upstream lines", () => {
  const cases: Array<[string, string]> = [
    [
      '<string name="app_name">Stera</string>',
      '<string name="app_name">Acme Vision</string>',
    ],
    [
      'static const String sourceRepo = "https://github.com/fpv-labs/stera-app";',
      'static const String sourceRepo = "https://github.com/acme-robotics/acme-vision";',
    ],
    ['"@stera/db": "workspace:*"', '"@acme-vision/db": "workspace:*"'],
    ['noExternal: [/@stera\\/.*/]', 'noExternal: [/@acme-vision\\/.*/]'],
    ['case "stera/msg/TrackingState":', 'case "acme_vision/msg/TrackingState":'],
    ['library: "fpv_labs/1.0"', 'library: "acme_vision/1.0"'],
    [
      'BGTaskSchedulerPermittedIdentifiers open.fpvlabs.stera.upload.finalize',
      "BGTaskSchedulerPermittedIdentifiers com.acmerobotics.vision.upload.finalize",
    ],
    ['name: "stera"', 'name: "acme_vision"'],
    ["turbo run dev -F @stera/mobile", "turbo run dev -F @acme-vision/mobile"],
    [
      'AppHeader(text1: "Stera", text2: "")',
      'AppHeader(text1: "Acme Vision", text2: "")',
    ],
  ];

  for (const [input, expected] of cases) {
    test(input.slice(0, 60), () => {
      expect(go(input)).toBe(expected);
    });
  }
});

describe("idempotence", () => {
  test("applying the same rules twice changes nothing the second time", () => {
    const source = [
      'import "package:stera/src/core/theme/colors.dart";',
      "package open.fpvlabs.stera.ar_recorder",
      '"@stera/db": "workspace:*"',
      'Text("Stera")',
    ].join("\n");

    const once = go(source);
    expect(go(once)).toBe(once);
  });

  test("a second rename maps the fork forward, not back to upstream", () => {
    const second = derive({
      brand: { name: "Acme Two", legalEntity: "Acme Robotics, Inc." },
      identifiers: { bundleId: "com.acmerobotics.two" },
      urls: {
        website: "https://acmerobotics.com",
        contactEmail: "hello@acmerobotics.com",
        sourceRepo: "https://github.com/acme-robotics/acme-two",
      },
    });

    const step1 = go('import "package:stera/src/main.dart";');
    const step2 = rewrite(step1, buildTokens(ACME, second));
    expect(step2).toBe('import "package:acme_two/src/main.dart";');
  });
});

describe("identity rules shield their pattern from later rules", () => {
  test("a fork keeping the upstream MCAP namespace really keeps it", () => {
    const keeper = derive({
      brand: { name: "Acme Vision" },
      identifiers: {
        bundleId: "com.acmerobotics.vision",
        mcapSchemaNamespace: "stera",
      },
      urls: {
        website: "https://acmerobotics.com",
        contactEmail: "hello@acmerobotics.com",
        sourceRepo: "https://github.com/acme-robotics/acme-vision",
      },
    });
    const rules = buildTokens(UPSTREAM_BRAND, keeper);
    // The rule is still present - as an identity rule - because removing it
    // would let the bare `stera` rule below rewrite the namespace anyway.
    const rule = rules.find((r) => r.label === "MCAP ROS2 schema namespace");
    expect(rule).toBeDefined();
    expect(rule?.from).toBe(rule?.to);
    expect(rewrite('case "stera/msg/TrackingState":', rules)).toBe(
      'case "stera/msg/TrackingState":'
    );
    // ...while everything else in the same file still renames.
    expect(rewrite('import "package:stera/x.dart";', rules)).toBe(
      'import "package:acme_vision/x.dart";'
    );
  });

  test("identity rules are not counted as edits", () => {
    const keeper = derive({
      brand: { name: "Acme Vision" },
      identifiers: {
        bundleId: "com.acmerobotics.vision",
        mcapSchemaNamespace: "stera",
      },
      urls: {
        website: "https://acmerobotics.com",
        contactEmail: "hello@acmerobotics.com",
        sourceRepo: "https://github.com/acme-robotics/acme-vision",
      },
    });
    const { hits } = applyTokens(
      'case "stera/msg/TrackingState":',
      buildTokens(UPSTREAM_BRAND, keeper)
    );
    expect(hits.size).toBe(0);
  });
});

describe("hit accounting", () => {
  test("reports which rule fired how often", () => {
    const { hits } = applyTokens(
      ['import "package:stera/a.dart";', 'import "package:stera/b.dart";'].join("\n"),
      RULES
    );
    expect(hits.get("app Dart imports")).toBe(2);
  });
});

describe("findStale agrees with applyTokens", () => {
  const stale = staleTokensOf(UPSTREAM_BRAND);

  test("clean text has no stale hits", () => {
    expect(findStale(go('import "package:stera/x.dart";'), stale)).toHaveLength(0);
  });

  test("sisteransi is not reported as stale", () => {
    expect(findStale('"sisteransi": ["sisteransi@1.0.5"]', stale)).toHaveLength(0);
  });

  test("a genuinely missed token is reported with position", () => {
    const hits = findStale('const x = "Stera";', stale);
    expect(hits).toHaveLength(1);
    expect(hits[0]?.token).toBe("Stera");
    expect(hits[0]?.line).toBe(1);
  });
});
