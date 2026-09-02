import { join } from "node:path";

import { describe, expect, test } from "bun:test";

import { UPSTREAM_BRAND } from "../lib/upstream.ts";
import { copy, copySeamTargets } from "./seams.ts";

const ROOT = join(import.meta.dir, "..", "..", "..");

/**
 * The seams match literal strings in `apps/mobile`. When one of those files is
 * edited and the pair is not, `65-copy` logs a warning and moves on - the call
 * site keeps its upstream literal and nothing else complains. That is silent for
 * everything except the update URLs, where the failure mode is a fork that
 * configured a store id in brand.json and still never checks for updates.
 */
describe("copy seams still match the tree", () => {
  const targets = copySeamTargets(UPSTREAM_BRAND);

  for (const target of targets) {
    test(target.path, async () => {
      const source = await Bun.file(join(ROOT, target.path)).text();

      if (source.includes(target.needs)) {
        // A fork runs these tests after brand:apply as well. In that state the
        // generated Brand seam is the contract, not the old upstream literal.
        for (const [, to] of target.pairs) {
          expect(source).toContain(to);
        }
      } else {
        for (const [from] of target.pairs) {
          expect(source).toContain(from);
        }
      }
    });
  }
});

test("copy owns its generated Brand file on subsequent runs", () => {
  expect(copy.owns?.(UPSTREAM_BRAND, UPSTREAM_BRAND)).toContain(
    "apps/mobile/lib/src/core/config/constants/brand.dart"
  );
});

describe("the update seam", () => {
  const target = copySeamTargets(UPSTREAM_BRAND).find((candidate) =>
    candidate.path.endsWith("app_update.dart")
  );

  test("is registered", () => {
    expect(target).toBeDefined();
  });

  test("routes all three update urls through Brand", async () => {
    const source = await Bun.file(join(ROOT, target!.path)).text();
    let seamed = source;
    for (const [from, to] of target!.pairs) {
      seamed = seamed.split(from).join(to);
    }

    expect(seamed).toContain("Brand.updateFeedUrl");
    expect(seamed).toContain("Brand.playStoreUrl");
    expect(seamed).toContain("Brand.appStoreUrl");
  });

  test("leaves no url literal at the call site before or after seaming", async () => {
    const source = await Bun.file(join(ROOT, target!.path)).text();
    expect([...source.matchAll(/"https?:\/\//g)]).toHaveLength(0);
  });
});
