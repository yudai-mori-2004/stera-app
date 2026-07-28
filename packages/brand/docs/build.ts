#!/usr/bin/env bun
/**
 * Builds the white-label guide into a single self-contained HTML file.
 *
 *   bun run brand:guide
 *
 * The guide is styled with the app's own design tokens and typeset in the app's
 * own faces, so it looks like the product it documents. Those faces are the
 * variable TTFs in `apps/mobile/assets/fonts/` - EB Garamond alone is 934 KB,
 * which is far too much to inline - so `fonts/` holds Latin-subset woff2 builds
 * of the three the guide uses, 63 KB for the lot with the weight axis intact.
 *
 * Everything is inlined because a published artifact runs under a strict CSP
 * that blocks font CDNs; a linked webfont would silently fall back to Georgia
 * and the page would stop looking like the app.
 *
 * To regenerate the subsets after a font change (needs fonttools + brotli):
 *
 *   pyftsubset apps/mobile/assets/fonts/EBGaramond-VariableFont_wght.ttf \
 *     --output-file=packages/brand/docs/fonts/garamond.woff2 --flavor=woff2 \
 *     --unicodes='U+0020-007E,U+00A0,U+2018,U+2019,U+201C,U+201D,U+2013,U+2014,U+2026,U+2192,U+2713,U+00D7,U+00B7,U+2022' \
 *     --layout-features='kern,liga,calt,tnum' --no-hinting --desubroutinize
 */

import { join } from "node:path";

const DOCS = import.meta.dir;

const FONTS: Record<string, string> = {
  __GARAMOND__: "garamond.woff2",
  __GEIST__: "geist.woff2",
  __GEISTMONO__: "geistmono.woff2",
};

const SOURCE = join(DOCS, "guide.src.html");
const OUTPUT = join(DOCS, "whitelabel-guide.html");

const main = async (): Promise<number> => {
  const source = Bun.file(SOURCE);
  if (!(await source.exists())) {
    console.error(`missing ${SOURCE}`);
    return 1;
  }

  let html = await source.text();

  for (const [token, filename] of Object.entries(FONTS)) {
    if (!html.includes(token)) {
      console.error(`placeholder ${token} is not present in guide.src.html`);
      return 1;
    }
    const file = Bun.file(join(DOCS, "fonts", filename));
    if (!(await file.exists())) {
      console.error(`missing font subset: docs/fonts/${filename}`);
      return 1;
    }
    const base64 = Buffer.from(await file.arrayBuffer()).toString("base64");
    html = html.replace(token, base64);
  }

  // A surviving placeholder means a silent font fallback, which is exactly the
  // failure this build exists to prevent - so it is an error, not a warning.
  const leftover = /__[A-Z_]+__/.exec(html);
  if (leftover !== null) {
    console.error(`unreplaced placeholder: ${leftover[0]}`);
    return 1;
  }

  // The artifact host wraps the file in its own document skeleton, so any
  // document-level tag here would nest and break the page.
  const forbidden = /<!doctype|<html[\s>]|<head[\s>]|<body[\s>]/i.exec(html);
  if (forbidden !== null) {
    console.error(`document-level tag not allowed in an artifact: ${forbidden[0]}`);
    return 1;
  }

  await Bun.write(OUTPUT, html);
  console.log(
    `wrote packages/brand/docs/whitelabel-guide.html (${Math.round(html.length / 1024)} KB, no external requests)`
  );
  return 0;
};

process.exit(await main());
