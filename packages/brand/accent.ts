#!/usr/bin/env bun
/**
 * Suggests a brand accent by reading the dominant hue out of a logo.
 *
 *   bun run brand:accent packages/brand/source/icon.png
 *
 * Exists to remove a question from the interview. "What is your accent colour,
 * as a hex?" is a strange thing to ask somebody who has just handed you their
 * artwork; the answer is nearly always "the colour in the logo". This reads it
 * off so the question becomes "is this it?" instead.
 *
 * Prints the light-mode accent and the dark-mode variant the engine would
 * derive from it, ready to paste into `theme.brandAccentLight`.
 */

import { isAbsolute, join } from "node:path";

import { deriveDarkAccent, hexToCss } from "./lib/color.ts";
import { sampleAccent } from "./lib/raster.ts";

const RED = "[31m";
const DIM = "[2m";
const RESET = "[0m";

const main = async (): Promise<number> => {
  const target = Bun.argv[2];
  if (target === undefined || target === "-h" || target === "--help") {
    console.log(
      "Usage: bun run packages/brand/accent.ts <path-to-logo>\n\n" +
        "Prints a suggested theme.brandAccentLight for the artwork."
    );
    return target === undefined ? 1 : 0;
  }

  const root = join(import.meta.dir, "..", "..");
  const absolute = isAbsolute(target) ? target : join(root, target);

  if (!(await Bun.file(absolute).exists())) {
    console.error(`${RED}error${RESET} no such file: ${target}`);
    return 1;
  }

  const sampled = await sampleAccent(absolute);
  if (sampled === null) {
    console.log(
      `No chromatic accent found - the mark looks monochrome.\n` +
        `Pick a colour yourself and set theme.brandAccentLight, or leave it and the app keeps its amber.`
    );
    return 0;
  }

  const dark = deriveDarkAccent(sampled.hex);
  console.log(
    `${hexToCss(sampled.hex)}   ${DIM}light-mode accent (theme.brandAccentLight)${RESET}\n` +
      `${hexToCss(dark)}   ${DIM}dark-mode variant the engine derives from it${RESET}\n\n` +
      `${DIM}Sampled from ${Math.round(sampled.coverage * 100)}% of the mark's opaque pixels. ` +
      `Run brand:preview to see it against the app's greys before committing to it.${RESET}`
  );
  return 0;
};

process.exit(await main());
