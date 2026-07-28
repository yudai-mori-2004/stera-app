/**
 * Renders `brand.json` as a page you can look at.
 *
 * The gap this closes: until now the only way to see a rebrand was to run it
 * and then build the app - roughly five minutes, after ~360 files had already
 * been rewritten. The dry run printed a file count, which tells you nothing
 * about whether the colour works or the logo is legible on a dark background.
 *
 * So this takes the same derived `Brand` the engine applies and draws it:
 * the icon, the launch screen, the four screens that actually carry brand
 * marks, every colour token, the type scale and the corner radii. Nothing is
 * written to the app - `brand:preview` is a pure function of the config, which
 * is what makes it safe to run in a loop while deciding.
 *
 * Everything is inlined (fonts as data URIs, artwork as data URIs) so the file
 * opens with a double-click and renders identically with no network.
 */

import {
  contrastRatio,
  gradeContrast,
  hexToCss,
  hexToCssRgba,
  hexToRgba,
  relativeLuminance,
} from "./color.ts";
import {
  BASE_PALETTE,
  MAX_TINT,
  TOKEN_GROUPS,
  changedTokens,
  checkContrast,
} from "./palette.ts";
import { SPACE_STEPS } from "./space.ts";
import { TYPE_STEPS } from "./type.ts";
import type { Brand, Hex } from "./types.ts";

export interface PreviewAssets {
  /** The launcher icon, as a data URI. Null when the fork supplied no artwork. */
  icon: string | null;
  logoLight: string | null;
  logoDark: string | null;
}

export interface EmbeddedFont {
  family: string;
  dataUri: string;
  /** The CSS `format()` hint: `woff2`, `truetype`, `opentype`. */
  format: string;
}

export interface PreviewInput {
  brand: Brand;
  /** The brand currently on disk: the ledger's, or upstream's on a first run. */
  previous: Brand;
  assets: PreviewAssets;
  fonts: readonly EmbeddedFont[];
  /** Supplied by the caller; this module never reads the clock. */
  generatedAt: string;
  /** True when `.applied.json` exists, i.e. this repo has been rebranded before. */
  applied: boolean;
}

const escapeHtml = (value: string): string =>
  value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");

/** Black or white, whichever is legible on `background`. */
const readableOn = (background: Hex): string =>
  relativeLuminance(hexToRgba(background)) > 0.45 ? "#18191B" : "#FFFFFF";

// ---------------------------------------------------------------------------
// Fragments
// ---------------------------------------------------------------------------

const fontFaces = (fonts: readonly EmbeddedFont[]): string =>
  fonts
    .map(
      (font) => `@font-face {
  font-family: "${font.family}";
  src: url(${font.dataUri}) format("${font.format}");
  font-weight: 100 900;
  font-display: block;
}`
    )
    .join("\n");

const paletteVariables = (brand: Brand, mode: "light" | "dark"): string =>
  Object.entries(brand.theme.palette)
    .map(([token, pair]) => `    --c-${token}: ${hexToCssRgba(pair[mode])};`)
    .join("\n");

/**
 * A phone-shaped frame. The mock screens inside are HTML, not screenshots, so
 * they are approximations - the point is to answer "does this colour work and
 * is that logo legible", not to replace running the app.
 */
const screen = (
  title: string,
  mode: "light" | "dark",
  body: string
): string => `
        <figure class="screen">
          <div class="phone ${mode}">
            <div class="phone-inner">${body}</div>
          </div>
          <figcaption>${escapeHtml(title)} &middot; ${mode}</figcaption>
        </figure>`;

const logoImg = (
  assets: PreviewAssets,
  mode: "light" | "dark",
  className: string
): string => {
  const source = mode === "light" ? assets.logoLight : assets.logoDark;
  if (source === null) {
    return `<div class="${className} logo-missing">no artwork</div>`;
  }
  return `<img class="${className}" src="${source}" alt="" />`;
};

const splashScreen = (input: PreviewInput, mode: "light" | "dark"): string => {
  const { brand } = input;
  const background =
    mode === "light"
      ? brand.theme.launchBackgroundLight
      : brand.theme.launchBackgroundDark;
  const foreground =
    mode === "light"
      ? brand.theme.launchForegroundLight
      : brand.theme.launchForegroundDark;

  return screen(
    "Launch screen",
    mode,
    `
            <div class="splash" style="background:${hexToCss(background)};color:${hexToCss(foreground)}">
              <div class="splash-mark">${logoImg(input.assets, mode, "splash-logo")}</div>
              <div class="splash-wordmark">
                <div class="splash-title">${escapeHtml(brand.copy.splashTitle)}</div>
                <div class="splash-subtitle">${escapeHtml(brand.copy.splashSubtitle)}</div>
              </div>
            </div>`
  );
};

const signInScreen = (input: PreviewInput, mode: "light" | "dark"): string => {
  const { brand } = input;
  return screen(
    "Sign-in sheet",
    mode,
    `
            <div class="sheet-backdrop">
              <div class="sheet">
                ${logoImg(input.assets, mode, "sheet-logo")}
                <h2 class="sheet-title">Build with <span class="accent-face">multimodal data</span></h2>
                <p class="sheet-body">${escapeHtml(brand.copy.loginTagline)}</p>
                <div class="button primary">Continue with Google</div>
                <div class="button secondary">Continue with Apple</div>
                <p class="sheet-legal">By continuing you agree to the
                  <span class="link">Terms</span> and <span class="link">Privacy Policy</span>.</p>
              </div>
            </div>`
  );
};

const homeScreen = (input: PreviewInput, mode: "light" | "dark"): string => {
  const { brand } = input;
  return screen(
    "Home",
    mode,
    `
            <div class="app">
              <header class="app-bar">
                <span class="app-title">${escapeHtml(brand.copy.appName)}</span>
                <span class="badge">OPEN SOURCE</span>
              </header>
              <div class="card">
                <div class="card-thumb"></div>
                <div class="card-text">
                  <div class="card-title">Warehouse walkthrough</div>
                  <div class="card-meta">00:04:12 &middot; 1.2 GB</div>
                </div>
              </div>
              <div class="card">
                <div class="card-thumb"></div>
                <div class="card-text">
                  <div class="card-title">Rooftop survey</div>
                  <div class="card-meta">00:01:47 &middot; 480 MB</div>
                </div>
              </div>
              <div class="chip-row">
                <span class="chip chip-accent">Uploading</span>
                <span class="chip">Processed</span>
                <span class="chip">Draft</span>
              </div>
              <nav class="tab-bar">
                <span class="tab active">Home</span>
                <span class="tab">Record</span>
                <span class="tab">Profile</span>
              </nav>
            </div>`
  );
};

const profileScreen = (input: PreviewInput, mode: "light" | "dark"): string => {
  const { brand } = input;
  const attribution =
    brand.attribution.enabled && brand.attribution.showInProfileFooter
      ? `<div class="footer-attribution">${escapeHtml(brand.attribution.text)}</div>`
      : "";

  return screen(
    "Profile footer",
    mode,
    `
            <div class="app">
              <header class="app-bar"><span class="app-title">Profile</span></header>
              <div class="row">Account settings</div>
              <div class="row">Storage</div>
              <div class="row">${escapeHtml(brand.urls.contactEmail)}</div>
              <div class="profile-footer">
                <div class="footer-link">${escapeHtml(brand.copy.appName)} is open source — view the code on GitHub</div>
                ${attribution}
              </div>
            </div>`
  );
};

// ---------------------------------------------------------------------------
// Sections
// ---------------------------------------------------------------------------

const iconSection = (input: PreviewInput): string => {
  const { brand, assets } = input;
  const background = hexToCss(brand.assets.iconBackgroundColor);
  const tile = (label: string, style: string): string =>
    assets.icon === null
      ? `<figure class="icon-tile"><div class="icon-shape logo-missing" style="${style}">none</div><figcaption>${label}</figcaption></figure>`
      : `<figure class="icon-tile"><div class="icon-shape" style="${style};background:${background}"><img src="${assets.icon}" alt="" /></div><figcaption>${label}</figcaption></figure>`;

  return `
      <div class="icon-row">
        ${tile("iOS · 180px", "width:96px;height:96px;border-radius:22%")}
        ${tile("Android adaptive", "width:96px;height:96px;border-radius:50%")}
        ${tile("Home screen · 60px", "width:60px;height:60px;border-radius:22%")}
        ${tile("Notification · 28px", "width:28px;height:28px;border-radius:22%")}
      </div>
      <div class="logo-row">
        <figure><div class="logo-plate light">${logoImg(assets, "light", "plate-logo")}</div><figcaption>In-app logo · light</figcaption></figure>
        <figure><div class="logo-plate dark">${logoImg(assets, "dark", "plate-logo")}</div><figcaption>In-app logo · dark</figcaption></figure>
      </div>`;
};

const paletteSection = (brand: Brand): string => {
  const changed = new Set(changedTokens(brand.theme.palette));

  return TOKEN_GROUPS.map((group) => {
    const swatches = group.tokens
      .map((token) => {
        const pair = brand.theme.palette[token];
        if (pair === undefined) {
          return "";
        }
        const marks = [
          brand.theme.overrides[token] !== undefined ? "pinned" : "",
          changed.has(token) && brand.theme.overrides[token] === undefined
            ? "tinted"
            : "",
        ]
          .filter(Boolean)
          .map((mark) => `<span class="tag">${mark}</span>`)
          .join("");

        return `
          <div class="swatch">
            <div class="swatch-pair">
              <div class="swatch-half" style="background:${hexToCssRgba(pair.light)};color:${readableOn(pair.light)}">${hexToCss(pair.light)}</div>
              <div class="swatch-half" style="background:${hexToCssRgba(pair.dark)};color:${readableOn(pair.dark)}">${hexToCss(pair.dark)}</div>
            </div>
            <div class="swatch-name">${token}${marks}</div>
          </div>`;
      })
      .join("");

    return `
        <h3 class="group-title">${group.title}</h3>
        <div class="swatch-grid">${swatches}</div>`;
  }).join("");
};

const contrastSection = (brand: Brand): string => {
  const findings = checkContrast(brand.theme.palette);
  if (findings.length === 0) {
    return `<p class="ok">Every checked pair meets its WCAG minimum in both modes.</p>`;
  }

  const rows = findings
    .map(
      (finding) => `
          <tr class="${finding.regression ? "bad" : "inherited"}">
            <td><code>${finding.foreground}</code> on <code>${finding.background}</code></td>
            <td>${finding.mode}</td>
            <td>${finding.ratio.toFixed(2)}:1</td>
            <td>${finding.baseline.toFixed(2)}:1</td>
            <td>${finding.minimum}:1</td>
            <td>${finding.regression ? "caused by this brand" : "inherited from upstream"}</td>
          </tr>`
    )
    .join("");

  return `
      <table class="grid">
        <thead><tr><th>Pair</th><th>Mode</th><th>Ratio</th><th>Upstream</th><th>Needs</th><th></th></tr></thead>
        <tbody>${rows}</tbody>
      </table>
      <p class="note">Inherited failures are upstream's design (a hairline divider is not a component
        outline) and do not block a run. Anything marked <em>caused by this brand</em> does, unless
        <code>theme.allowLowContrast</code> is set.</p>`;
};

const typeSection = (brand: Brand): string => {
  const specimen = (role: string, family: string, sample: string, cls: string): string => `
        <div class="specimen">
          <div class="specimen-label">${role} · <code>${escapeHtml(family)}</code></div>
          <div class="specimen-sample ${cls}">${escapeHtml(sample)}</div>
        </div>`;

  const { style, scale, weights } = brand.theme.type;

  // Rendered at the real size and leading rather than described in a table. The
  // whole reason the ramp is configurable is that "md is 15px now" tells you
  // nothing and seeing a paragraph set at it tells you everything.
  const ramp = TYPE_STEPS.map((step) => {
    const { size, lineHeight } = scale[step];
    return `
        <div class="ramp-row">
          <div class="ramp-label">${step}<br><span class="ramp-measure">${size}/${lineHeight}</span></div>
          <div class="ramp-sample face-body" style="font-size:${size}px; line-height:${lineHeight}px">
            ${escapeHtml(brand.copy.appName)} — the quick brown fox
          </div>
        </div>`;
  }).join("");

  const weightRow = (["regular", "medium", "semibold", "bold"] as const)
    .map(
      (role) => `
          <div class="weight-cell face-body" style="font-weight:${weights[role]}">
            ${role}<br><span class="ramp-measure">${weights[role]}</span>
          </div>`
    )
    .join("");

  return [
    specimen("display", brand.fonts.display, brand.copy.appName, "face-display"),
    specimen("body", brand.fonts.body, brand.copy.loginTagline, "face-body"),
    specimen("mono", brand.fonts.mono, "00:04:12 · 1.2 GB · v2.14.0", "face-mono"),
    specimen("accent", brand.fonts.accent, "multimodal data", "face-accent"),
    `
      <p class="note">Scale <code>${style}</code>. Every <code>TextStyle</code> in the app is built from
        these nine steps and these four weights, so the ramp is part of the brand rather than forty
        literal font sizes. A fork that changes only <code>fonts.body</code> keeps upstream's
        typography in a different typeface.</p>
      <div class="ramp">${ramp}</div>
      <div class="weight-row">${weightRow}</div>`,
  ].join("");
};

const shapeSection = (brand: Brand): string => {
  const { style, scale } = brand.theme.shape;
  const steps: ReadonlyArray<[string, number]> = [
    ["hairline", scale.hairline],
    ["xs", scale.xs],
    ["xsPlus", scale.xsPlus],
    ["sm", scale.sm],
    ["smPlus", scale.smPlus],
    ["md", scale.md],
    ["mdPlus", scale.mdPlus],
    ["lg", scale.lg],
    ["lgPlus", scale.lgPlus],
    ["xl", scale.xl],
    ["xlPlus", scale.xlPlus],
  ];

  const tiles = steps
    .map(
      ([name, value]) => `
          <figure class="shape-tile">
            <div class="shape-box" style="border-radius:${value}px"></div>
            <figcaption>${name} · ${value}px</figcaption>
          </figure>`
    )
    .join("");

  return `
      <p class="note">Style <code>${style}</code>. Every radius in the app sits on this scale - there are no
        off-scale one-offs left - so changing the style changes the silhouette of the whole product.</p>
      <div class="shape-row">${tiles}</div>`;
};

const spaceSection = (brand: Brand): string => {
  const { style, scale } = brand.theme.space;

  // Drawn as bars at their real width rather than listed as numbers: density is
  // a rhythm, and a column of "16" tells you nothing about whether the product
  // breathes.
  const bars = SPACE_STEPS.filter((step) => step !== "none")
    .map(
      (step) => `
          <div class="space-row">
            <div class="space-label">${step}</div>
            <div class="space-bar" style="width:${scale[step]}px"></div>
            <div class="space-measure">${scale[step]}px</div>
          </div>`
    )
    .join("");

  return `
      <p class="note">Density <code>${style}</code>. Every gap and every pad in the app is on this scale,
        so this is the knob that decides whether the product feels packed or airy - the axis that
        survives a palette swap and the one a fork is most likely to leave at upstream's value
        without noticing.</p>
      <div class="space-scale">${bars}</div>`;
};

/**
 * The in-app updater is the one setting whose *absence* is the interesting
 * state, so spell it out rather than rendering an empty cell.
 */
const describeUpdates = (brand: Brand): string => {
  const { playStoreAppId, appStoreId, updateFeed } = brand.urls;
  if (updateFeed !== null) {
    return `appcast: ${updateFeed}`;
  }
  const stores = [
    playStoreAppId === null ? null : `Play (${playStoreAppId})`,
    appStoreId === null ? null : `App Store (${appStoreId})`,
  ].filter((value) => value !== null);
  return stores.length === 0 ? "off - no store id, no feed" : stores.join(", ");
};

const diffRow = (label: string, from: string, to: string): string => {
  const changed = from !== to;
  return `
          <tr class="${changed ? "changed" : ""}">
            <td>${escapeHtml(label)}</td>
            <td><code>${escapeHtml(from)}</code></td>
            <td>${changed ? `<code>${escapeHtml(to)}</code>` : `<span class="same">unchanged</span>`}</td>
          </tr>`;
};

const diffSection = (input: PreviewInput): string => {
  const { brand, previous } = input;
  const tokenChanges = changedTokens(brand.theme.palette).length;

  const rows = [
    diffRow("App name", previous.copy.appName, brand.copy.appName),
    diffRow("Bundle id", previous.identifiers.bundleId, brand.identifiers.bundleId),
    diffRow("Dart package", previous.identifiers.dartPackage, brand.identifiers.dartPackage),
    diffRow("Accent (light)", hexToCss(previous.theme.brandAccentLight), hexToCss(brand.theme.brandAccentLight)),
    diffRow("Accent (dark)", hexToCss(previous.theme.brandAccentDark), hexToCss(brand.theme.brandAccentDark)),
    diffRow("Tint", `${previous.theme.tint}`, `${brand.theme.tint}`),
    diffRow("Shape", previous.theme.shape.style, brand.theme.shape.style),
    diffRow("Type scale", previous.theme.type.style, brand.theme.type.style),
    diffRow("Density", previous.theme.space.style, brand.theme.space.style),
    diffRow("Display face", previous.fonts.display, brand.fonts.display),
    diffRow("Body face", previous.fonts.body, brand.fonts.body),
    diffRow("API host", previous.urls.apiHostProd, brand.urls.apiHostProd),
    diffRow("In-app updates", describeUpdates(previous), describeUpdates(brand)),
  ].join("");

  // Shown next to the diff rather than in a corner: when a brand was matched to
  // a reference, "does this still look like them" is the question the diff is
  // being read to answer, and the answer needs the link in front of you.
  const reference =
    brand.reference === null
      ? ""
      : `
      <p class="note">Matched against <a href="${escapeHtml(brand.reference.url)}">${escapeHtml(
          brand.reference.url
        )}</a>${brand.reference.capturedAt === "" ? "" : ` (read ${escapeHtml(brand.reference.capturedAt)})`}${
          brand.reference.notes === ""
            ? ""
            : ` &mdash; ${escapeHtml(brand.reference.notes)}`
        }</p>`;

  return `${reference}
      <p class="note">Comparing against ${
        input.applied
          ? "the brand recorded in <code>.applied.json</code>"
          : "the upstream tree, since this repo has not been rebranded yet"
      }.</p>
      <table class="grid">
        <thead><tr><th></th><th>Now on disk</th><th>After apply</th></tr></thead>
        <tbody>${rows}</tbody>
      </table>
      <p class="note">${tokenChanges === 0
        ? "No colour token moves: the palette is upstream's, with only the accent replaced."
        : `${tokenChanges} colour token(s) move, from the accent${brand.theme.tint > 0 ? `, a tint of ${brand.theme.tint} (up to ${Math.round(brand.theme.tint * MAX_TINT * 100)}% of the accent mixed into the neutrals)` : ""}${Object.keys(brand.theme.overrides).length > 0 ? ` and ${Object.keys(brand.theme.overrides).length} pinned override(s)` : ""}.`}</p>`;
};

const factsSection = (brand: Brand): string => {
  const row = (label: string, value: string): string =>
    `<tr><td>${escapeHtml(label)}</td><td><code>${escapeHtml(value)}</code></td></tr>`;

  return `
      <table class="grid">
        <tbody>
          ${row("Bundle id", brand.identifiers.bundleId)}
          ${row("Dart package", brand.identifiers.dartPackage)}
          ${row("Kotlin package", brand.identifiers.kotlinPackage)}
          ${row("npm scope", brand.identifiers.npmScope)}
          ${row("Recorder plugin", brand.identifiers.recorder.dartPackage)}
          ${row("MCAP namespace", brand.identifiers.mcapSchemaNamespace)}
          ${row("systemd unit", `${brand.identifiers.systemdServiceName}.service`)}
          ${row("R2 buckets", `${brand.identifiers.r2Bucket}, ${brand.identifiers.r2BucketProd}`)}
          ${row("API hosts", `${brand.urls.apiHostDev}, ${brand.urls.apiHostProd}`)}
          ${row("Website", brand.urls.website)}
          ${row("Contact", brand.urls.contactEmail)}
          ${row("Source repo", brand.urls.sourceRepo)}
          ${row("In-app updates", describeUpdates(brand))}
        </tbody>
      </table>`;
};

// ---------------------------------------------------------------------------
// Document
// ---------------------------------------------------------------------------

export const buildPreviewHtml = (input: PreviewInput): string => {
  const { brand } = input;
  const { scale } = brand.theme.shape;

  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>${escapeHtml(brand.copy.appName)} — brand preview</title>
<style>
${fontFaces(input.fonts)}

:root {
  --font-display: "${brand.fonts.display}", Georgia, serif;
  --font-body: "${brand.fonts.body}", -apple-system, system-ui, sans-serif;
  --font-mono: "${brand.fonts.mono}", ui-monospace, monospace;
  --font-accent: "${brand.fonts.accent}", "${brand.fonts.display}", serif;

  --r-xs: ${scale.xs}px;
  --r-sm: ${scale.sm}px;
  --r-md: ${scale.md}px;
  --r-lg: ${scale.lg}px;
  --r-xl: ${scale.xl}px;
  --r-full: ${scale.full}px;

  --page: #0E0F11;
  --page-fg: #F2F3F5;
  --page-muted: #9A9DA3;
  --page-line: #26282C;
  --page-card: #17181B;
}

@media (prefers-color-scheme: light) {
  :root {
    --page: #FAFAFB;
    --page-fg: #18191B;
    --page-muted: #6B6E73;
    --page-line: #E3E4E7;
    --page-card: #FFFFFF;
  }
}

* { box-sizing: border-box; }

body {
  margin: 0;
  padding: 0 24px 96px;
  background: var(--page);
  color: var(--page-fg);
  font-family: var(--font-body);
  font-size: 15px;
  line-height: 1.55;
  -webkit-font-smoothing: antialiased;
}

.wrap { max-width: 1180px; margin: 0 auto; }

header.masthead {
  padding: 56px 0 32px;
  border-bottom: 1px solid var(--page-line);
  margin-bottom: 40px;
}
.masthead h1 {
  font-family: var(--font-display);
  font-size: 46px;
  font-weight: 500;
  margin: 0 0 6px;
  letter-spacing: -0.01em;
}
.masthead .tagline { color: var(--page-muted); margin: 0 0 20px; }
.masthead .meta { font-family: var(--font-mono); font-size: 12px; color: var(--page-muted); }
.disclaimer {
  margin-top: 20px;
  padding: 12px 16px;
  border: 1px solid var(--page-line);
  border-radius: var(--r-sm);
  background: var(--page-card);
  font-size: 13px;
  color: var(--page-muted);
}

section { margin: 0 0 56px; }
section > h2 {
  font-family: var(--font-display);
  font-size: 26px;
  font-weight: 500;
  margin: 0 0 4px;
}
section > .lede { color: var(--page-muted); margin: 0 0 22px; font-size: 14px; }
.group-title { font-size: 12px; text-transform: uppercase; letter-spacing: 0.08em; color: var(--page-muted); margin: 26px 0 10px; font-weight: 600; }
.note { font-size: 13px; color: var(--page-muted); }
.ok { font-size: 14px; }
code { font-family: var(--font-mono); font-size: 0.87em; }

/* ---- Icon + logo ---- */
.icon-row, .logo-row { display: flex; gap: 28px; align-items: flex-end; flex-wrap: wrap; }
.logo-row { margin-top: 32px; }
.icon-row figure, .logo-row figure { margin: 0; text-align: center; }
.icon-shape { display: grid; place-items: center; overflow: hidden; box-shadow: 0 2px 10px rgb(0 0 0 / 0.22); }
.icon-shape img { width: 100%; height: 100%; object-fit: contain; }
figcaption { font-size: 11px; color: var(--page-muted); margin-top: 8px; font-family: var(--font-mono); }
.logo-plate { width: 260px; height: 120px; display: grid; place-items: center; border-radius: var(--r-md); border: 1px solid var(--page-line); }
.logo-plate.light { background: ${hexToCss(brand.theme.palette.surfaceTertiary?.light ?? "0xFFF7F4ED")}; }
.logo-plate.dark { background: ${hexToCss(brand.theme.palette.surfaceTertiary?.dark ?? "0xFF2E2F31")}; }
.plate-logo { max-width: 180px; max-height: 76px; object-fit: contain; }
.logo-missing {
  display: grid; place-items: center;
  font-family: var(--font-mono); font-size: 10px; color: var(--page-muted);
  border: 1px dashed var(--page-line); border-radius: var(--r-xs);
  min-width: 80px; min-height: 40px; padding: 8px;
}

/* ---- Screens ---- */
.screens { display: flex; gap: 26px; flex-wrap: wrap; }
.screen { margin: 0; }
.phone {
  width: 268px; height: 552px;
  border-radius: 34px;
  padding: 10px;
  background: #1B1C1F;
  box-shadow: 0 12px 34px rgb(0 0 0 / 0.3);
}
.phone-inner { width: 100%; height: 100%; border-radius: 26px; overflow: hidden; position: relative; }

.phone.light {
${paletteVariables(brand, "light")}
}
.phone.dark {
${paletteVariables(brand, "dark")}
}

/* Launch screen */
.splash { width: 100%; height: 100%; display: flex; flex-direction: column; align-items: center; justify-content: center; padding: 28px; }
.splash-mark { flex: 1; display: grid; place-items: center; }
.splash-logo { max-width: 168px; max-height: 74px; object-fit: contain; }
.splash-wordmark { text-align: center; padding-bottom: 12px; }
.splash-title { font-family: var(--font-display); font-size: 24px; line-height: 1; }
.splash-subtitle { font-size: 11px; opacity: 0.85; margin-top: 2px; }

/* Sign-in sheet */
.sheet-backdrop { width: 100%; height: 100%; background: var(--c-surfacePrimary); display: flex; align-items: flex-end; }
.sheet {
  width: 100%;
  background: var(--c-surfaceSecondary);
  border-top-left-radius: var(--r-xl); border-top-right-radius: var(--r-xl);
  padding: 20px;
  color: var(--c-textPrimary);
}
.sheet-logo { width: 60px; height: 60px; border-radius: 50%; object-fit: cover; display: block; }
.sheet-title { font-family: var(--font-display); font-size: 24px; font-weight: 500; margin: 20px 0 0; line-height: 1.15; }
.accent-face { font-family: var(--font-accent); }
.sheet-body { font-size: 12px; color: var(--c-textSecondary); margin: 12px 0 20px; }
.button {
  border-radius: var(--r-sm);
  padding: 12px;
  text-align: center;
  font-size: 13px;
  font-weight: 500;
  margin-bottom: 10px;
}
.button.primary { background: var(--c-surfaceBlack); color: var(--c-textInversePrimary); }
.button.secondary { border: 1px solid var(--c-borderDefault); color: var(--c-textPrimary); }
.sheet-legal { font-size: 10px; color: var(--c-textTertiary); text-align: center; margin: 12px 0 4px; }
.link { color: var(--c-textPrimary); text-decoration: underline; }

/* App chrome */
.app { width: 100%; height: 100%; background: var(--c-surfacePrimary); color: var(--c-textPrimary); padding: 22px 16px 0; display: flex; flex-direction: column; }
.app-bar { display: flex; align-items: center; justify-content: space-between; margin-bottom: 16px; }
.app-title { font-family: var(--font-display); font-size: 22px; }
.badge {
  font-family: var(--font-mono); font-size: 8px; letter-spacing: 0.06em;
  border: 1px solid var(--c-brandAccent); color: var(--c-brandAccent);
  border-radius: var(--r-xs); padding: 3px 6px;
}
.card { display: flex; gap: 10px; background: var(--c-surfaceSecondary); border: 1px solid var(--c-borderDivider); border-radius: var(--r-md); padding: 10px; margin-bottom: 10px; }
.card-thumb { width: 56px; height: 42px; border-radius: var(--r-sm); background: var(--c-neutralLightGray); flex: none; }
.card-title { font-size: 12px; font-weight: 500; }
.card-meta { font-family: var(--font-mono); font-size: 10px; color: var(--c-textSecondary); margin-top: 2px; }
.chip-row { display: flex; gap: 6px; margin-top: 6px; }
.chip { font-size: 10px; border-radius: var(--r-full, 999px); padding: 4px 10px; border: 1px solid var(--c-borderDefault); color: var(--c-textSecondary); }
.chip-accent { background: var(--c-brandAccent); border-color: var(--c-brandAccent); color: ${readableOn(brand.theme.palette.brandAccent?.light ?? brand.theme.brandAccentLight)}; }
.row { padding: 13px 2px; border-bottom: 1px solid var(--c-borderDivider); font-size: 13px; }
.tab-bar { margin-top: auto; display: flex; justify-content: space-around; border-top: 1px solid var(--c-borderDivider); padding: 12px 0 18px; }
.tab { font-size: 10px; color: var(--c-textTertiary); }
.tab.active { color: var(--c-textPrimary); font-weight: 500; }
.profile-footer { margin-top: auto; padding: 18px 0 22px; text-align: center; }
.footer-link { font-size: 11px; color: var(--c-textSecondary); }
.footer-attribution { font-size: 10px; color: var(--c-textTertiary); margin-top: 8px; }

/* ---- Palette ---- */
.swatch-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(168px, 1fr)); gap: 12px; }
.swatch-pair { display: flex; height: 52px; border-radius: var(--r-sm); overflow: hidden; border: 1px solid var(--page-line); }
.swatch-half { flex: 1; display: grid; place-items: center; font-family: var(--font-mono); font-size: 10px; }
.swatch-name { font-family: var(--font-mono); font-size: 11px; margin-top: 6px; color: var(--page-muted); display: flex; align-items: center; gap: 6px; flex-wrap: wrap; }
.tag { font-size: 9px; text-transform: uppercase; letter-spacing: 0.05em; border: 1px solid var(--page-line); border-radius: 3px; padding: 1px 4px; color: var(--page-fg); }

/* ---- Tables ---- */
table.grid { width: 100%; border-collapse: collapse; font-size: 13px; }
table.grid th { text-align: left; font-size: 11px; text-transform: uppercase; letter-spacing: 0.06em; color: var(--page-muted); font-weight: 600; padding: 8px 10px; border-bottom: 1px solid var(--page-line); }
table.grid td { padding: 9px 10px; border-bottom: 1px solid var(--page-line); vertical-align: top; }
table.grid tr.changed td:last-child code { color: var(--page-fg); font-weight: 600; }
.same { color: var(--page-muted); font-size: 12px; }
tr.bad td { background: rgb(211 47 47 / 0.13); }
tr.inherited td { background: rgb(255 183 64 / 0.09); }

/* ---- Type + shape ---- */
.specimen { padding: 16px 0; border-bottom: 1px solid var(--page-line); }
.specimen-label { font-size: 11px; text-transform: uppercase; letter-spacing: 0.06em; color: var(--page-muted); margin-bottom: 8px; }
.specimen-sample { font-size: 30px; line-height: 1.25; }
.ramp { margin-top: 20px; border-top: 1px solid var(--page-line); }
.ramp-row { display: flex; gap: 16px; align-items: baseline; padding: 10px 0; border-bottom: 1px solid var(--page-line); }
.ramp-label { flex: 0 0 92px; font-size: 11px; color: var(--page-muted); text-align: right; }
.ramp-measure { font-family: var(--font-mono); font-size: 10px; opacity: 0.7; }
.ramp-sample { flex: 1; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.weight-row { display: flex; gap: 12px; flex-wrap: wrap; margin-top: 16px; }
.weight-cell { flex: 1 1 120px; padding: 12px; border: 1px solid var(--page-line); border-radius: 6px; font-size: 14px; }
.space-scale { margin-top: 16px; }
.space-row { display: flex; align-items: center; gap: 12px; padding: 5px 0; }
.space-label { flex: 0 0 72px; font-size: 11px; color: var(--page-muted); text-align: right; }
.space-bar { height: 14px; background: var(--c-brandAccent); border-radius: 2px; min-width: 1px; }
.space-measure { font-family: var(--font-mono); font-size: 10px; color: var(--page-muted); }
.face-display { font-family: var(--font-display); }
.face-body { font-family: var(--font-body); font-size: 17px; }
.face-mono { font-family: var(--font-mono); font-size: 20px; }
.face-accent { font-family: var(--font-accent); }
.shape-row { display: flex; gap: 20px; margin-top: 16px; flex-wrap: wrap; }
.shape-tile { margin: 0; text-align: center; }
.shape-box { width: 84px; height: 84px; background: var(--page-card); border: 1px solid var(--page-line); }

@media (max-width: 720px) {
  .phone { width: 232px; height: 478px; }
}
</style>
</head>
<body>
<div class="wrap">

  <header class="masthead">
    <h1>${escapeHtml(brand.copy.appName)}</h1>
    <p class="tagline">${escapeHtml(brand.brand.tagline)}</p>
    <p class="meta">${escapeHtml(brand.identifiers.bundleId)} · ${escapeHtml(brand.urls.website)} · generated ${escapeHtml(input.generatedAt)}</p>
    <div class="disclaimer">
      Rendered from <code>packages/brand/brand.json</code>. <strong>Nothing has been applied</strong> —
      no file in the app has changed. The screens are HTML approximations built from the real tokens,
      copy and artwork, not screenshots of a build; they are here to answer "does this colour work,
      is that mark legible", not to replace running the app.
    </div>
  </header>

  <section>
    <h2>Identity</h2>
    <p class="lede">The launcher icon under each platform's mask, and the mark that appears inside the app.</p>
    ${iconSection(input)}
  </section>

  <section>
    <h2>Screens</h2>
    <p class="lede">The four surfaces that carry brand marks, in both modes.</p>
    <div class="screens">
      ${splashScreen(input, "light")}
      ${splashScreen(input, "dark")}
      ${signInScreen(input, "light")}
      ${signInScreen(input, "dark")}
    </div>
    <div class="screens" style="margin-top:26px">
      ${homeScreen(input, "light")}
      ${homeScreen(input, "dark")}
      ${profileScreen(input, "light")}
      ${profileScreen(input, "dark")}
    </div>
  </section>

  <section>
    <h2>What changes</h2>
    <p class="lede">This config against what is on disk right now.</p>
    ${diffSection(input)}
  </section>

  <section>
    <h2>Palette</h2>
    <p class="lede">Every token on <code>C</code>, light on the left and dark on the right.
      <em>tinted</em> means the accent bled into it; <em>pinned</em> means you named it in <code>theme.overrides</code>.</p>
    ${paletteSection(brand)}
  </section>

  <section>
    <h2>Contrast</h2>
    <p class="lede">The pairs the UI actually renders, graded against WCAG 2.1.</p>
    ${contrastSection(brand)}
  </section>

  <section>
    <h2>Type</h2>
    <p class="lede">The four roles in the faces this config resolves to, then the ramp and the
      weights every style in the app is built from.</p>
    ${typeSection(brand)}
  </section>

  <section>
    <h2>Shape</h2>
    <p class="lede">The corner-radius scale the widget tree reads from.</p>
    ${shapeSection(brand)}
  </section>

  <section>
    <h2>Density</h2>
    <p class="lede">The spacing scale every gap and pad in the app reads from.</p>
    ${spaceSection(brand)}
  </section>

  <section>
    <h2>Identifiers</h2>
    <p class="lede">Derived from the name, bundle id and website. Several are effectively permanent once shipped.</p>
    ${factsSection(brand)}
  </section>

</div>
</body>
</html>
`;
};

/** Re-exported so `preview.ts` can report the same numbers it renders. */
export const previewSummary = (
  brand: Brand
): { changed: number; regressions: number; inherited: number } => {
  const findings = checkContrast(brand.theme.palette, BASE_PALETTE);
  return {
    changed: changedTokens(brand.theme.palette).length,
    regressions: findings.filter((finding) => finding.regression).length,
    inherited: findings.filter((finding) => !finding.regression).length,
  };
};

/** Kept next to the renderer so the grade legend and the table cannot drift. */
export const contrastLegend = (ratio: number): string => gradeContrast(ratio);

/** Exposed for tests: the ratio the mock sign-in sheet actually renders at. */
export const sheetContrast = (brand: Brand, mode: "light" | "dark"): number =>
  contrastRatio(
    brand.theme.palette.textPrimary?.[mode] ?? "0xFF000000",
    brand.theme.palette.surfaceSecondary?.[mode] ?? "0xFFFFFFFF"
  );
