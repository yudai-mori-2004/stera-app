/**
 * Turns a sparse `BrandInput` into a fully-resolved `Brand`.
 *
 * The rule the whole engine leans on: **every field is either user-supplied or
 * derived, never both.** Derived fields are still written back to brand.json so
 * the file is a complete, auditable snapshot, but `derive()` recomputes them
 * every run. A hand-edit that disagrees with the derivation is an error, not a
 * silent override - except inside `theme.overrides`, which exists precisely so
 * there is one sanctioned place to disagree.
 */

import { deriveDarkAccent, parseHex } from "./color.ts";
import {
  FONT_ROLES,
  UPSTREAM_FONT_FAMILIES,
  isValidFamilyName,
} from "./fonts.ts";
import { TOKEN_NAMES, checkContrast, resolvePalette } from "./palette.ts";
import { SHAPE_SCALES, SHAPE_STEPS, resolveShapeScale } from "./shape.ts";
import { SPACE_SCALES, SPACE_STEPS, resolveSpaceScale } from "./space.ts";
import {
  TYPE_SCALES,
  TYPE_STEPS,
  TYPE_WEIGHT_ROLES,
  resolveTypeScale,
  resolveTypeWeights,
} from "./type.ts";
import type {
  Brand,
  BrandInput,
  BrandIosUsageDescriptions,
  FontSource,
  Hex,
  ShapeScale,
  ShapeStyle,
  SpaceScale,
  SpaceStyle,
  TokenPair,
  TypeScaleOverrides,
  TypeStyle,
  TypeWeights,
} from "./types.ts";

export { hexToCss, hexToRgba } from "./color.ts";

export class BrandConfigError extends Error {
  readonly field: string;

  constructor(field: string, message: string) {
    super(`brand.json: ${field}: ${message}`);
    this.name = "BrandConfigError";
    this.field = field;
  }
}

// ---------------------------------------------------------------------------
// String helpers
// ---------------------------------------------------------------------------

/** "Acme Vision!" -> "acme-vision" */
export const kebab = (input: string): string =>
  input
    .normalize("NFKD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .replace(/-{2,}/g, "-");

/** "Acme Vision" -> "acme_vision" */
export const snake = (input: string): string => kebab(input).replace(/-/g, "_");

/** "acme_vision_recorder" -> "AcmeVisionRecorder" */
export const pascal = (input: string): string =>
  kebab(input)
    .split("-")
    .filter(Boolean)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join("");

/**
 * Reserved words that cannot appear as a bare segment of a JVM package path.
 * `open` is deliberately absent - it is not a Java keyword, which is why
 * upstream's `open.fpvlabs.stera` is legal today.
 */
const JVM_KEYWORDS = new Set([
  "abstract", "assert", "boolean", "break", "byte", "case", "catch", "char",
  "class", "const", "continue", "default", "do", "double", "else", "enum",
  "extends", "final", "finally", "float", "for", "goto", "if", "implements",
  "import", "instanceof", "int", "interface", "long", "native", "new",
  "package", "private", "protected", "public", "return", "short", "static",
  "strictfp", "super", "switch", "synchronized", "this", "throw", "throws",
  "transient", "try", "void", "volatile", "while",
  // Kotlin hard keywords that are also illegal unescaped in a package path.
  "as", "fun", "in", "is", "null", "object", "typealias", "typeof", "val",
  "var", "when", "true", "false",
]);

const DART_RESERVED = new Set([
  "abstract", "as", "assert", "async", "await", "break", "case", "catch",
  "class", "const", "continue", "covariant", "default", "deferred", "do",
  "dynamic", "else", "enum", "export", "extends", "extension", "external",
  "factory", "false", "final", "finally", "for", "function", "get", "hide",
  "if", "implements", "import", "in", "interface", "is", "late", "library",
  "mixin", "new", "null", "on", "operator", "part", "required", "rethrow",
  "return", "sealed", "set", "show", "static", "super", "switch", "sync",
  "this", "throw", "true", "try", "typedef", "var", "void", "while", "with",
  "yield",
]);

const BUNDLE_ID_RE = /^[a-z][a-z0-9]*(\.[a-z][a-z0-9]*)+$/;
const DART_PACKAGE_RE = /^[a-z_][a-z0-9_]*$/;

/**
 * Maps one bundle-id segment onto a legal JVM package segment. Bundle ids allow
 * things a package path does not (leading digits after a dash, keywords), so
 * each segment is sanitized and keyword-suffixed rather than rejected.
 */
export const jvmSegment = (segment: string): string => {
  let out = segment.toLowerCase().replace(/[^a-z0-9_]/g, "_");
  if (out.length === 0) {
    throw new BrandConfigError("identifiers.bundleId", `empty path segment`);
  }
  if (/^[0-9]/.test(out)) {
    out = `_${out}`;
  }
  if (JVM_KEYWORDS.has(out)) {
    out = `${out}_`;
  }
  return out;
};

export const jvmPackage = (bundleId: string): string =>
  bundleId.split(".").map(jvmSegment).join(".");

// ---------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------

export const validateBundleId = (bundleId: string): void => {
  if (!BUNDLE_ID_RE.test(bundleId)) {
    throw new BrandConfigError(
      "identifiers.bundleId",
      `"${bundleId}" must be reverse-DNS: lowercase letters and digits, at least two dot-separated segments, each starting with a letter (e.g. "com.acmerobotics.vision")`
    );
  }
};

export const validateDartPackage = (name: string, field: string): void => {
  if (!DART_PACKAGE_RE.test(name)) {
    throw new BrandConfigError(
      field,
      `"${name}" must be a valid Dart package name: lowercase letters, digits and underscores, not starting with a digit`
    );
  }
  if (DART_RESERVED.has(name)) {
    throw new BrandConfigError(field, `"${name}" is a Dart reserved word`);
  }
};

/**
 * A Dart package name that collides with one of the app's own dependencies
 * would make `import "package:<name>/..."` ambiguous. The caller passes the
 * dependency names read from pubspec.yaml.
 */
export const validateNoDependencyCollision = (
  name: string,
  dependencies: readonly string[],
  field: string
): void => {
  if (dependencies.includes(name)) {
    throw new BrandConfigError(
      field,
      `"${name}" collides with an existing pubspec dependency`
    );
  }
};

/**
 * Parses any accepted colour spelling into the canonical `0xAARRGGBB`, or
 * reports which field was wrong. The parsing itself lives in `color.ts`; this
 * is only the error-reporting wrapper, so that colour maths does not have to
 * depend on the config layer.
 */
export const normalizeHex = (value: string, field: string): Hex => {
  const parsed = parseHex(value);
  if (parsed === null) {
    throw new BrandConfigError(
      field,
      `"${value}" is not a colour. Use "#RGB", "#RRGGBB", "#RRGGBBAA" or "0xAARRGGBB".`
    );
  }
  return parsed;
};

const normalizeUnitInterval = (
  value: number | undefined,
  field: string,
  fallback: number
): number => {
  if (value === undefined) {
    return fallback;
  }
  if (!Number.isFinite(value) || value < 0 || value > 1) {
    throw new BrandConfigError(field, `must be a number between 0 and 1`);
  }
  return value;
};

// ---------------------------------------------------------------------------
// Derivation
// ---------------------------------------------------------------------------

const stripTrailingSlash = (url: string): string => url.replace(/\/+$/, "");

const hostOf = (url: string, field: string): string => {
  try {
    return new URL(url).host;
  } catch {
    throw new BrandConfigError(field, `"${url}" is not a valid URL`);
  }
};

const usageDescriptions = (
  appName: string,
  override: Partial<BrandIosUsageDescriptions> | undefined
): BrandIosUsageDescriptions => ({
  camera:
    override?.camera ??
    `${appName} uses your camera to record and capture high-quality video for spatial AI training. Only when you provide consent.`,
  motion:
    override?.motion ??
    `${appName} uses motion sensors (accelerometer and gyroscope) to capture IMU data during AR recording for spatial AI training.`,
  photoLibrary:
    override?.photoLibrary ??
    `${appName} needs access to your photo library to select and upload videos for spatial AI training.`,
  photoLibraryAdd:
    override?.photoLibraryAdd ??
    `${appName} needs permission to save your recorded and processed videos to your gallery.`,
  microphone:
    override?.microphone ??
    "Voice commands are used to control recording hands-free.",
  speechRecognition:
    override?.speechRecognition ??
    "Voice commands are used to control recording hands-free.",
});

// ---------------------------------------------------------------------------
// Theme
// ---------------------------------------------------------------------------

/**
 * Validates `theme.overrides` and normalises its colours.
 *
 * The token name is checked against the real field list on `C`. It used not to
 * be, which meant a typo - or a token that simply does not exist - produced a
 * constant in `BrandPalette` that nothing read, and the fork saw no change and
 * no error. Every entry here now has to name a colour the app actually uses.
 */
const deriveOverrides = (
  input: BrandInput
): Record<string, TokenPair> => {
  const overrides: Record<string, TokenPair> = {};

  for (const [token, pair] of Object.entries(input.theme?.overrides ?? {})) {
    if (!TOKEN_NAMES.includes(token)) {
      throw new BrandConfigError(
        `theme.overrides.${token}`,
        `"${token}" is not a colour token. Valid tokens: ${TOKEN_NAMES.join(", ")}`
      );
    }
    if (!pair?.light || !pair?.dark) {
      throw new BrandConfigError(
        `theme.overrides.${token}`,
        "must have both a `light` and a `dark` colour"
      );
    }
    overrides[token] = {
      light: normalizeHex(pair.light, `theme.overrides.${token}.light`),
      dark: normalizeHex(pair.dark, `theme.overrides.${token}.dark`),
    };
  }

  return overrides;
};

const deriveShape = (input: BrandInput): Brand["theme"]["shape"] => {
  const style = (input.theme?.shape?.style ?? "soft") as ShapeStyle;
  if (!(style in SHAPE_SCALES)) {
    throw new BrandConfigError(
      "theme.shape.style",
      `"${style}" is not a shape style. Use one of: ${Object.keys(SHAPE_SCALES).join(", ")}`
    );
  }

  const configured = input.theme?.shape?.scale ?? {};
  const overrides: Partial<ShapeScale> = {};
  for (const step of SHAPE_STEPS) {
    const value = configured[step];
    if (value === undefined) {
      continue;
    }
    if (!Number.isFinite(value) || value < 0) {
      throw new BrandConfigError(
        `theme.shape.scale.${step}`,
        "must be a non-negative number of logical pixels"
      );
    }
    overrides[step] = value;
  }

  return { style, scale: resolveShapeScale(style, overrides) };
};

const deriveSpace = (input: BrandInput): Brand["theme"]["space"] => {
  const style = (input.theme?.space?.style ?? "default") as SpaceStyle;
  if (!(style in SPACE_SCALES)) {
    throw new BrandConfigError(
      "theme.space.style",
      `"${style}" is not a density. Use one of: ${Object.keys(SPACE_SCALES).join(", ")}`
    );
  }

  const configured = input.theme?.space?.scale ?? {};
  for (const key of Object.keys(configured)) {
    if (!(SPACE_STEPS as readonly string[]).includes(key)) {
      throw new BrandConfigError(
        `theme.space.scale.${key}`,
        `not a step on the scale. Use one of: ${SPACE_STEPS.join(", ")}`
      );
    }
  }

  const overrides: Partial<SpaceScale> = {};
  for (const step of SPACE_STEPS) {
    const value = configured[step];
    if (value === undefined) {
      continue;
    }
    if (!Number.isFinite(value) || value < 0) {
      throw new BrandConfigError(
        `theme.space.scale.${step}`,
        "must be a non-negative number of logical pixels"
      );
    }
    overrides[step] = value;
  }

  return { style, scale: resolveSpaceScale(style, overrides) };
};

/**
 * Carried, not acted on. No transform reads this; it exists so that "the tint is
 * 0.45 because their background is a warm off-white" survives into
 * `.applied.json` and the next conversation, instead of looking like a number
 * someone liked.
 */
const deriveReference = (input: BrandInput): Brand["reference"] => {
  const reference = input.reference;
  if (reference === undefined || reference === null) {
    return null;
  }
  if (typeof reference.url !== "string" || reference.url.length === 0) {
    throw new BrandConfigError("reference.url", "a reference needs a url");
  }
  return {
    url: reference.url,
    kind: reference.kind ?? "other",
    capturedAt: reference.capturedAt ?? "",
    notes: reference.notes ?? "",
  };
};

const deriveType = (input: BrandInput): Brand["theme"]["type"] => {
  const style = (input.theme?.type?.style ?? "default") as TypeStyle;
  if (!(style in TYPE_SCALES)) {
    throw new BrandConfigError(
      "theme.type.style",
      `"${style}" is not a type style. Use one of: ${Object.keys(TYPE_SCALES).join(", ")}`
    );
  }

  const configured = input.theme?.type?.scale ?? {};

  // Unknown keys are errors, not no-ops, for the same reason `theme.overrides`
  // rejects an unknown token: a typo that silently does nothing is a fork that
  // thinks it moved its type scale and shipped upstream's.
  for (const key of Object.keys(configured)) {
    if (!(TYPE_STEPS as readonly string[]).includes(key)) {
      throw new BrandConfigError(
        `theme.type.scale.${key}`,
        `not a step on the ramp. Use one of: ${TYPE_STEPS.join(", ")}`
      );
    }
  }

  const overrides: TypeScaleOverrides = {};
  for (const step of TYPE_STEPS) {
    const value = configured[step];
    if (value === undefined) {
      continue;
    }
    for (const key of ["size", "lineHeight"] as const) {
      const measure = value[key];
      if (measure === undefined) {
        continue;
      }
      if (!Number.isFinite(measure) || measure <= 0) {
        throw new BrandConfigError(
          `theme.type.scale.${step}.${key}`,
          "must be a positive number of logical pixels"
        );
      }
    }
    overrides[step] = value;
  }

  const configuredWeights = input.theme?.type?.weights ?? {};
  for (const key of Object.keys(configuredWeights)) {
    if (!(TYPE_WEIGHT_ROLES as readonly string[]).includes(key)) {
      throw new BrandConfigError(
        `theme.type.weights.${key}`,
        `not a weight role. Use one of: ${TYPE_WEIGHT_ROLES.join(", ")}`
      );
    }
  }

  const weights: Partial<TypeWeights> = {};
  for (const role of TYPE_WEIGHT_ROLES) {
    const value = configuredWeights[role];
    if (value === undefined) {
      continue;
    }
    // Flutter has no FontWeight between the hundreds; a 550 would round to one
    // of its neighbours silently, and the fork would never learn which.
    if (!Number.isInteger(value) || value < 100 || value > 900 || value % 100 !== 0) {
      throw new BrandConfigError(
        `theme.type.weights.${role}`,
        "must be a multiple of 100 between 100 and 900 - Flutter has no FontWeight in between"
      );
    }
    weights[role] = value;
  }

  return {
    style,
    scale: resolveTypeScale(style, overrides),
    weights: resolveTypeWeights(weights),
  };
};

// ---------------------------------------------------------------------------
// Fonts
// ---------------------------------------------------------------------------

/** What a human may write for one font file: a bare path, or a full entry. */
type FontSourceInput = string | Partial<FontSource>;

const normalizeFontSource = (
  entry: FontSourceInput,
  field: string
): FontSource => {
  const source = typeof entry === "string" ? { path: entry } : entry;
  const path = source.path?.trim();
  if (!path) {
    throw new BrandConfigError(field, "needs a `path` to a font file");
  }
  if (source.weight !== undefined && source.weight !== null) {
    if (!Number.isInteger(source.weight) || source.weight < 1 || source.weight > 1000) {
      throw new BrandConfigError(`${field}.weight`, "must be an integer from 1 to 1000");
    }
  }
  const style = source.style ?? "normal";
  if (style !== "normal" && style !== "italic") {
    throw new BrandConfigError(`${field}.style`, `must be "normal" or "italic"`);
  }
  return { path, weight: source.weight ?? null, style };
};

/**
 * Resolves the four typeface roles.
 *
 * The important check is the last one. Flutter treats an unknown `fontFamily`
 * as "use the platform default" and renders without complaint, so a fork that
 * sets `fonts.display: "Inter"` without supplying Inter would ship a build
 * where the display face silently reverted to San Francisco or Roboto. That has
 * to fail here, loudly, with the two ways to fix it.
 */
const deriveFonts = (input: BrandInput): Brand["fonts"] => {
  const configuredFiles = (input.fonts?.files ?? {}) as Record<
    string,
    readonly FontSourceInput[]
  >;

  const files: Record<string, FontSource[]> = {};
  for (const [family, entries] of Object.entries(configuredFiles)) {
    if (!isValidFamilyName(family)) {
      throw new BrandConfigError(
        `fonts.files.${family}`,
        `"${family}" must be letters and digits only, starting with a letter - it has to match the pubspec family name exactly`
      );
    }
    if (!Array.isArray(entries) || entries.length === 0) {
      throw new BrandConfigError(
        `fonts.files.${family}`,
        "must be a non-empty array of font files"
      );
    }
    files[family] = entries.map((entry, index) =>
      normalizeFontSource(entry, `fonts.files.${family}[${index}]`)
    );
  }

  const roles = {
    display: input.fonts?.display ?? "EBGaramond",
    body: input.fonts?.body ?? "Geist",
    mono: input.fonts?.mono ?? "GeistMono",
    accent: input.fonts?.accent ?? "Handjet",
  };

  for (const role of FONT_ROLES) {
    const family = roles[role];
    if (!isValidFamilyName(family)) {
      throw new BrandConfigError(
        `fonts.${role}`,
        `"${family}" must be letters and digits only, starting with a letter`
      );
    }
    if (files[family] === undefined && !UPSTREAM_FONT_FAMILIES.includes(family)) {
      throw new BrandConfigError(
        `fonts.${role}`,
        `"${family}" is neither bundled with the app nor supplied by this config. ` +
          `Add the font files under fonts.files.${family}, or name one of: ${UPSTREAM_FONT_FAMILIES.join(", ")}. ` +
          `Flutter falls back to the system face for an unknown family without reporting an error, so this cannot be a warning.`
      );
    }
  }

  return {
    ...roles,
    files,
    replaceBundled: input.fonts?.replaceBundled ?? false,
  };
};

export interface DeriveOptions {
  /** Dependency names from apps/mobile/pubspec.yaml, for collision checking. */
  pubspecDependencies?: readonly string[];
  /** Upstream brand, used only to reject a no-op rename. */
  upstream?: Brand;
  /**
   * Resolve the palette even when it regresses contrast.
   *
   * For `brand:preview` only. Refusing to render the page whose entire job is
   * to show you the problem would be a strange way to help - the preview draws
   * the failing pairs in red and says what `brand:apply` will do about them.
   * The engine itself never passes this.
   */
  ignoreContrast?: boolean;
}

export const derive = (input: BrandInput, options: DeriveOptions = {}): Brand => {
  const name = input.brand?.name?.trim();
  if (!name) {
    throw new BrandConfigError("brand.name", "is required");
  }

  const slug = input.brand?.slug ?? kebab(name);
  if (slug.length === 0) {
    throw new BrandConfigError(
      "brand.name",
      `"${name}" contains no alphanumeric characters, so no slug can be derived`
    );
  }
  const shortName = input.brand?.shortName ?? (name.split(/\s+/)[0] as string);

  const bundleId = input.identifiers?.bundleId?.trim();
  if (!bundleId) {
    throw new BrandConfigError("identifiers.bundleId", "is required");
  }
  validateBundleId(bundleId);
  if (options.upstream && bundleId === options.upstream.identifiers.bundleId) {
    throw new BrandConfigError(
      "identifiers.bundleId",
      "is identical to the upstream bundle id; choose your own"
    );
  }

  const dartPackage = input.identifiers?.dartPackage ?? snake(slug);
  validateDartPackage(dartPackage, "identifiers.dartPackage");
  validateNoDependencyCollision(
    dartPackage,
    options.pubspecDependencies ?? [],
    "identifiers.dartPackage"
  );

  const kotlinPackage = input.identifiers?.kotlinPackage ?? jvmPackage(bundleId);

  const recorderDart =
    input.identifiers?.recorder?.dartPackage ?? `${dartPackage}_recorder`;
  validateDartPackage(recorderDart, "identifiers.recorder.dartPackage");

  const website = stripTrailingSlash(input.urls?.website ?? "");
  if (!website) {
    throw new BrandConfigError("urls.website", "is required");
  }
  const contactEmail = input.urls?.contactEmail?.trim();
  if (!contactEmail) {
    throw new BrandConfigError("urls.contactEmail", "is required");
  }
  const sourceRepo = input.urls?.sourceRepo?.trim();
  if (!sourceRepo) {
    throw new BrandConfigError("urls.sourceRepo", "is required");
  }

  const websiteHost = hostOf(website, "urls.website");
  const appName = input.copy?.appName ?? name;
  const legalEntity = input.brand?.legalEntity ?? name;
  const splashSubtitle = input.copy?.splashSubtitle ?? `by ${legalEntity}`;

  const accentLight = normalizeHex(
    input.theme?.brandAccentLight ?? "0xFFE8A33D",
    "theme.brandAccentLight"
  );
  // Unspecified, the dark accent is lifted off the light one rather than copied.
  // The same hue at the same lightness reads rich on a near-white page and
  // muddy on a near-black one, and a fork should not have to know that.
  const accentDark =
    input.theme?.brandAccentDark === undefined
      ? deriveDarkAccent(accentLight)
      : normalizeHex(input.theme.brandAccentDark, "theme.brandAccentDark");

  const overrides = deriveOverrides(input);
  const tint = normalizeUnitInterval(input.theme?.tint, "theme.tint", 0);
  const allowLowContrast = input.theme?.allowLowContrast ?? false;

  const palette = resolvePalette({ accentLight, accentDark, tint, overrides });

  // Tinting moves surfaces toward the accent, which can quietly walk body text
  // below AA - the sort of regression that ships because it looked fine on the
  // screen of whoever picked the colour. Only regressions are fatal; a pair the
  // upstream palette already fails is inherited, not caused, and `brand:preview`
  // reports those so they are visible without being blocking.
  const regressions = checkContrast(palette).filter((finding) => finding.regression);
  if (regressions.length > 0 && !allowLowContrast && options.ignoreContrast !== true) {
    const detail = regressions
      .map(
        (finding) =>
          `${finding.foreground} on ${finding.background} (${finding.mode}) is ${finding.ratio.toFixed(2)}:1, ` +
          `down from ${finding.baseline.toFixed(2)}:1 and below the ${finding.minimum}:1 needed for ${finding.what}`
      )
      .join("; ");
    throw new BrandConfigError(
      tint > 0 ? "theme.tint" : "theme.overrides",
      `the resolved palette regresses contrast: ${detail}. ` +
        `Lower theme.tint, pin the affected tokens in theme.overrides, or set theme.allowLowContrast: true to ship it anyway.`
    );
  }

  return {
    engineVersion: 1,

    brand: {
      name,
      shortName,
      slug,
      tagline: input.brand?.tagline ?? "infra for spatial intelligence",
      legalEntity,
      copyrightYear: input.brand?.copyrightYear ?? 2026,
    },

    identifiers: {
      bundleId,
      androidApplicationId: input.identifiers?.androidApplicationId ?? bundleId,
      androidNamespace: input.identifiers?.androidNamespace ?? bundleId,
      kotlinPackage,
      dartPackage,
      npmScope: input.identifiers?.npmScope ?? `@${slug}`,
      repoName: input.identifiers?.repoName ?? slug,
      recorder: {
        rename: input.identifiers?.recorder?.rename ?? true,
        dartPackage: recorderDart,
        kotlinPackage:
          input.identifiers?.recorder?.kotlinPackage ??
          `${kotlinPackage}.ar_recorder`,
        pluginClass:
          input.identifiers?.recorder?.pluginClass ?? `${pascal(recorderDart)}Plugin`,
        podName: input.identifiers?.recorder?.podName ?? recorderDart,
        swiftObjcTarget:
          input.identifiers?.recorder?.swiftObjcTarget ?? `${recorderDart}_objc`,
        examplePackage:
          input.identifiers?.recorder?.examplePackage ??
          `${kotlinPackage}.recorder_example`,
        exampleIosBundleId:
          input.identifiers?.recorder?.exampleIosBundleId ??
          `${bundleId}.recorderExample`,
      },
      mcapSchemaNamespace:
        input.identifiers?.mcapSchemaNamespace ?? dartPackage,
      mcapWriterLibrary:
        input.identifiers?.mcapWriterLibrary ?? `${dartPackage}/1.0`,
      driftDatabaseName: input.identifiers?.driftDatabaseName ?? dartPackage,
      bookmarkKeyPrefix:
        input.identifiers?.bookmarkKeyPrefix ?? `${bundleId}.bookmark.`,
      systemdServiceName:
        input.identifiers?.systemdServiceName ?? `${slug}-server`,
      deployDirName: input.identifiers?.deployDirName ?? slug,
      r2Bucket: input.identifiers?.r2Bucket ?? `${slug}-uploads`,
      r2BucketProd: input.identifiers?.r2BucketProd ?? `${slug}-uploads-prod`,
    },

    urls: {
      website,
      termsAndConditions: input.urls?.termsAndConditions ?? `${website}/terms`,
      privacyPolicy: input.urls?.privacyPolicy ?? `${website}/privacy`,
      contactEmail,
      discordInvite: input.urls?.discordInvite ?? null,
      sourceRepo: stripTrailingSlash(sourceRepo),
      apiHostDev: input.urls?.apiHostDev ?? `app-dev.${websiteHost}`,
      apiHostProd: input.urls?.apiHostProd ?? `app.${websiteHost}`,
      // Deliberately not defaulted to `bundleId`: an id you have not actually
      // published under makes the updater check a listing that isn't yours.
      // Opting in is a one-line edit; opting out of a wrong default is not.
      playStoreAppId: input.urls?.playStoreAppId ?? null,
      appStoreId: input.urls?.appStoreId ?? null,
      updateFeed: input.urls?.updateFeed ?? null,
    },

    apple: {
      developmentTeam: input.apple?.developmentTeam ?? null,
      signInServiceId: input.apple?.signInServiceId ?? `${bundleId}.signin`,
      backgroundTaskPrefix: input.apple?.backgroundTaskPrefix ?? bundleId,
    },

    theme: {
      brandAccentLight: accentLight,
      brandAccentDark: accentDark,
      launchBackgroundLight: normalizeHex(
        input.theme?.launchBackgroundLight ?? "0xFFF7F4ED",
        "theme.launchBackgroundLight"
      ),
      launchBackgroundDark: normalizeHex(
        input.theme?.launchBackgroundDark ?? "0xFF2E2F31",
        "theme.launchBackgroundDark"
      ),
      launchForegroundLight: normalizeHex(
        input.theme?.launchForegroundLight ?? "0xFF18191B",
        "theme.launchForegroundLight"
      ),
      launchForegroundDark: normalizeHex(
        input.theme?.launchForegroundDark ?? "0xFFFFFFFF",
        "theme.launchForegroundDark"
      ),
      tint,
      allowLowContrast,
      overrides,
      palette,
      shape: deriveShape(input),
      type: deriveType(input),
      space: deriveSpace(input),
    },

    fonts: deriveFonts(input),

    assets: {
      iconSource: input.assets?.iconSource ?? null,
      iconForeground: input.assets?.iconForeground ?? null,
      iconBackgroundColor: normalizeHex(
        input.assets?.iconBackgroundColor ?? "0xFFF7F4ED",
        "assets.iconBackgroundColor"
      ),
      iconMonochrome: input.assets?.iconMonochrome ?? null,
      // The in-app logo falls back to the app icon rather than to nothing.
      // Leaving it null used to mean "keep upstream's artwork", so a fork that
      // supplied only an icon shipped a home-screen icon of its own and a
      // splash screen, sign-in sheet and onboarding modal still showing Stera's
      // mark. Inheriting the icon is wrong at worst; showing the upstream logo
      // is wrong always.
      logoLight:
        input.assets?.logoLight ??
        input.assets?.iconForeground ??
        input.assets?.iconSource ??
        null,
      logoDark:
        input.assets?.logoDark ??
        input.assets?.iconForeground ??
        input.assets?.iconSource ??
        null,
      splashTexture: input.assets?.splashTexture ?? null,
    },

    copy: {
      appName,
      appNameShort: input.copy?.appNameShort ?? shortName,
      appTitle: input.copy?.appTitle ?? `${appName} ${splashSubtitle}`,
      splashTitle: input.copy?.splashTitle ?? appName,
      splashSubtitle,
      loginTagline:
        input.copy?.loginTagline ??
        input.brand?.tagline ??
        "infra for spatial intelligence",
      iosUsageDescriptions: usageDescriptions(
        appName,
        input.copy?.iosUsageDescriptions
      ),
    },

    attribution: {
      enabled: input.attribution?.enabled ?? true,
      upstreamName: input.attribution?.upstreamName ?? "Stera",
      upstreamOrg: input.attribution?.upstreamOrg ?? "FPV Labs",
      upstreamRepo:
        input.attribution?.upstreamRepo ??
        "https://github.com/fpv-labs/stera-app",
      text: input.attribution?.text ?? "Powered by Stera",
      showInProfileFooter: input.attribution?.showInProfileFooter ?? true,
      showInReadme: input.attribution?.showInReadme ?? true,
      showInAttributionFile: input.attribution?.showInAttributionFile ?? true,
      showInMcapMetadata: input.attribution?.showInMcapMetadata ?? true,
    },

    compat: {
      keepMcapAliases: input.compat?.keepMcapAliases ?? true,
      renameDriftDatabase: input.compat?.renameDriftDatabase ?? true,
      renameBookmarkPrefix: input.compat?.renameBookmarkPrefix ?? true,
    },

    reference: deriveReference(input),

    legacy: {
      iosBundleId: input.legacy?.iosBundleId ?? bundleId,
      playStoreAppId: input.legacy?.playStoreAppId ?? bundleId,
    },
  };
};
