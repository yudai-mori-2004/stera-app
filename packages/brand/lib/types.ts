/**
 * Core types for the white-label engine.
 *
 * Two shapes matter here:
 *
 * - `BrandInput` is what a human writes in `packages/brand/brand.json`. Almost everything
 *   is optional; the interview only has to supply the handful of fields that
 *   cannot be guessed.
 * - `Brand` is the fully-resolved result of `derive(input)`. Every field is
 *   present. Transforms only ever see a `Brand`, never a `BrandInput`, so they
 *   never have to think about defaults.
 *
 * The engine is a pure function of `(prev: Brand, next: Brand)`. `prev` comes
 * from `packages/brand/.applied.json`, or from the `UPSTREAM_BRAND` literal in
 * `apply.ts` on the very first run. That is what makes re-running safe: run 1
 * maps Stera -> Acme, run 2 maps Acme -> Acme2, and there is no special case
 * for "the first one".
 */

export type Hex = string;

export interface BrandIdentity {
  name: string;
  shortName: string;
  slug: string;
  tagline: string;
  legalEntity: string;
  copyrightYear: number;
}

export interface RecorderIdentifiers {
  rename: boolean;
  dartPackage: string;
  kotlinPackage: string;
  pluginClass: string;
  podName: string;
  swiftObjcTarget: string;
  examplePackage: string;
  exampleIosBundleId: string;
}

export interface BrandIdentifiers {
  bundleId: string;
  androidApplicationId: string;
  androidNamespace: string;
  kotlinPackage: string;
  dartPackage: string;
  npmScope: string;
  repoName: string;
  recorder: RecorderIdentifiers;
  mcapSchemaNamespace: string;
  mcapWriterLibrary: string;
  driftDatabaseName: string;
  bookmarkKeyPrefix: string;
  systemdServiceName: string;
  deployDirName: string;
  r2Bucket: string;
  r2BucketProd: string;
}

export interface BrandUrls {
  website: string;
  termsAndConditions: string;
  privacyPolicy: string;
  contactEmail: string;
  discordInvite: string | null;
  sourceRepo: string;
  apiHostDev: string;
  apiHostProd: string;
  /**
   * Where the in-app updater looks, and where it sends the user. All three are
   * null for a fork that has not published anywhere, which switches the update
   * check off entirely rather than pointing it at somebody else's release.
   */
  playStoreAppId: string | null;
  appStoreId: string | null;
  updateFeed: string | null;
}

export interface BrandApple {
  developmentTeam: string | null;
  signInServiceId: string;
  backgroundTaskPrefix: string;
}

/** A design token's value in each mode. */
export interface TokenPair {
  light: Hex;
  dark: Hex;
}

/** Every colour token on `C`, resolved. Keys are the field names in colors.dart. */
export type Palette = Record<string, TokenPair>;

export type ShapeStyle = "sharp" | "soft" | "rounded" | "pill";

/**
 * Every step the widget tree uses. The `*Plus` entries are the half-steps
 * between the named ones - see `shape.ts` for why they exist.
 */
export interface ShapeScale {
  /** Grabbers, progress bars: a stroke that happens to be slightly soft. */
  hairline: number;
  xs: number;
  xsPlus: number;
  sm: number;
  smPlus: number;
  md: number;
  mdPlus: number;
  lg: number;
  lgPlus: number;
  xl: number;
  xlPlus: number;
  /** "Circle or stadium", not a radius. Never scaled by the style. */
  full: number;
}

export interface BrandShape {
  style: ShapeStyle;
  /** The style's scale, with any per-step overrides applied. */
  scale: ShapeScale;
}

export type SpaceStyle = "tight" | "default" | "comfortable";

/**
 * Every step the widget tree uses. Dense on purpose - see `space.ts` for why a
 * tidier four-step scale would have been the wrong trade.
 */
export type SpaceStep =
  | "none"
  | "xxs"
  | "xs"
  | "xsPlus"
  | "sm"
  | "smPlus"
  | "md"
  | "mdPlus"
  | "lg"
  | "lgPlus"
  | "xl"
  | "xlPlus"
  | "xxl"
  | "huge";

export type SpaceScale = Record<SpaceStep, number>;

export interface BrandSpace {
  style: SpaceStyle;
  /** The style's scale, with any per-step overrides applied. */
  scale: SpaceScale;
}

export type TypeStyle = "compact" | "default" | "spacious";

/**
 * The steps of the type ramp. `xl3Plus` is the half-step the app's page titles
 * sit on - see `type.ts` for why a half-step earns its place.
 */
export type TypeStep =
  | "xs"
  | "sm"
  | "md"
  | "lg"
  | "xl"
  | "xl2"
  | "xl3"
  | "xl3Plus"
  | "xl4";

/** One step: a size and a line height, both in logical pixels. */
export interface TypeStepValue {
  size: number;
  /** Absolute, not a multiplier. Flutter's ratio is computed at generation. */
  lineHeight: number;
}

export type TypeScale = Record<TypeStep, TypeStepValue>;

/**
 * What a fork may pin. Partial at both levels: overriding a step's size while
 * letting its line height follow the chosen style is the common case, and
 * `Partial<TypeScale>` alone would demand both.
 */
export type TypeScaleOverrides = Partial<Record<TypeStep, Partial<TypeStepValue>>>;

/**
 * The four weights the widget tree uses, by role. Values are the numeric
 * `FontWeight.wNNN` argument, 100..900 in steps of 100.
 */
export interface TypeWeights {
  regular: number;
  medium: number;
  semibold: number;
  bold: number;
}

export interface BrandType {
  style: TypeStyle;
  /** The style's table, with any per-step overrides applied. */
  scale: TypeScale;
  weights: TypeWeights;
}

export interface BrandTheme {
  brandAccentLight: Hex;
  brandAccentDark: Hex;
  launchBackgroundLight: Hex;
  launchBackgroundDark: Hex;
  launchForegroundLight: Hex;
  launchForegroundDark: Hex;
  /**
   * How much of the accent bleeds into the neutral surfaces, borders and muted
   * text, 0..1. 0 keeps the upstream greys exactly.
   */
  tint: number;
  /**
   * Ship a palette that fails the WCAG contrast contract. Off by default: a
   * tint that walks body text below AA is a regression, not a brand decision,
   * and it is invisible on the screen of whoever chose the colour.
   */
  allowLowContrast: boolean;
  /** Override any named token on `C` in apps/mobile/lib/src/core/theme/colors.dart. */
  overrides: Record<string, TokenPair>;
  /**
   * The full resolved palette: accent, then tint, then overrides. Derived, not
   * configured - `60-theme` writes every entry into `brand_palette.dart` and
   * rewrites `colors.dart` to read from it.
   */
  palette: Palette;
  shape: BrandShape;
  type: BrandType;
  space: BrandSpace;
}

/** One file backing a font family, mirroring a pubspec `fonts:` asset entry. */
export interface FontSource {
  /** Repo-relative path, e.g. `packages/brand/source/fonts/Inter.ttf`. */
  path: string;
  /** The pubspec `weight:` key. Null for a variable font. */
  weight: number | null;
  style: "normal" | "italic";
}

export interface BrandFonts {
  display: string;
  body: string;
  mono: string;
  accent: string;
  /**
   * Family name -> the files to bundle for it. A family named by one of the
   * four roles must either appear here or already be declared in the upstream
   * pubspec; Flutter falls back to the platform face without complaining, so
   * the engine refuses rather than shipping a silent regression.
   */
  files: Record<string, FontSource[]>;
  /** Drop the upstream typefaces that no declared family references. */
  replaceBundled: boolean;
}

export interface BrandAssets {
  iconSource: string | null;
  iconForeground: string | null;
  iconBackgroundColor: Hex;
  iconMonochrome: string | null;
  logoLight: string | null;
  logoDark: string | null;
  splashTexture: string | null;
}

export interface BrandIosUsageDescriptions {
  camera: string;
  motion: string;
  photoLibrary: string;
  photoLibraryAdd: string;
  microphone: string;
  speechRecognition: string;
}

export interface BrandCopy {
  appName: string;
  appNameShort: string;
  /** MaterialApp `title:` - upstream "Stera by FPV Labs". */
  appTitle: string;
  /** Splash headline - upstream "Stera". */
  splashTitle: string;
  /** Splash second line - upstream "by FPV Labs". */
  splashSubtitle: string;
  loginTagline: string;
  iosUsageDescriptions: BrandIosUsageDescriptions;
}

export interface BrandAttribution {
  enabled: boolean;
  upstreamName: string;
  upstreamOrg: string;
  upstreamRepo: string;
  text: string;
  showInProfileFooter: boolean;
  showInReadme: boolean;
  showInAttributionFile: boolean;
  showInMcapMetadata: boolean;
}

/**
 * What the brand was matched against. Inert - no transform reads it. It is
 * carried so the provenance of a design decision outlives the conversation that
 * produced it; a fork whose tint is 0.45 because a reference's background was
 * warm reads as an arbitrary number six months later, and the next person
 * "fixes" it.
 */
export interface BrandReference {
  url: string;
  kind: "site" | "design-system" | "brand-kit" | "screenshot" | "other";
  /** ISO date. A live site drifts; this says how stale the match may be. */
  capturedAt: string;
  /** What matched, and what had no equivalent here. */
  notes: string;
}

/** Compatibility decisions recorded once by `00-preflight`. */
export interface BrandCompat {
  /** Keep decoding the previous `<ns>/msg/*` MCAP schema names. */
  keepMcapAliases: boolean;
  /** Rename the on-disk drift sqlite file (existing installs start empty). */
  renameDriftDatabase: boolean;
  /** Rename the security-scoped bookmark prefix (invalidates saved bookmarks). */
  renameBookmarkPrefix: boolean;
}

/** Fully resolved brand. Every field present. */
export interface Brand {
  engineVersion: number;
  brand: BrandIdentity;
  identifiers: BrandIdentifiers;
  urls: BrandUrls;
  apple: BrandApple;
  theme: BrandTheme;
  fonts: BrandFonts;
  assets: BrandAssets;
  copy: BrandCopy;
  attribution: BrandAttribution;
  compat: BrandCompat;
  /** Null when the fork was not matched to anything. */
  reference: BrandReference | null;
  /**
   * Extra literals that only exist in the upstream tree and have no principled
   * derivation - the historical iOS bundle id and Play Store id, which differ
   * from the Android applicationId. Present on `prev` so the token engine can
   * find them; on `next` they all collapse to `identifiers.bundleId`.
   */
  legacy: {
    iosBundleId: string;
    playStoreAppId: string;
  };
}

/** What a human writes. `derive()` turns this into a `Brand`. */
export type BrandInput = DeepPartial<Brand> & {
  brand: Pick<BrandIdentity, "name"> & Partial<BrandIdentity>;
  identifiers: Pick<BrandIdentifiers, "bundleId"> & DeepPartial<BrandIdentifiers>;
  urls: Pick<BrandUrls, "website" | "contactEmail" | "sourceRepo"> & Partial<BrandUrls>;
};

export type DeepPartial<T> = {
  [K in keyof T]?: T[K] extends readonly unknown[]
    ? T[K]
    : T[K] extends object | undefined
      ? DeepPartial<NonNullable<T[K]>>
      : T[K];
};

// ---------------------------------------------------------------------------
// Transform plumbing
// ---------------------------------------------------------------------------

/**
 * A single filesystem effect. Transforms return these; they never touch disk
 * themselves. The runner collects every `Change`, checks the whole set for
 * conflicts, and only then applies - which is what gives `--dry-run` for free
 * and makes two transforms fighting over one file a hard error instead of a
 * silent last-writer-wins.
 */
export type Change =
  | { kind: "write"; path: string; contents: string | Uint8Array; why?: string }
  | { kind: "move"; from: string; to: string; why?: string }
  | { kind: "delete"; path: string; why?: string }
  | { kind: "exec"; cmd: string[]; cwd: string; why: string };

export interface Logger {
  info(message: string): void;
  warn(message: string): void;
  error(message: string): void;
  debug(message: string): void;
}

export interface FileIndex {
  /** Repo-relative paths from `git ls-files`, minus the denylist. */
  all(): string[];
  /** Text-substitutable files: `all()` minus binaries and never-rewrite paths. */
  rewritable(): string[];
  /** Paths under a repo-relative prefix. */
  under(prefix: string): string[];
  /** Read a tracked file as UTF-8, cached. */
  read(path: string): Promise<string>;
  exists(path: string): boolean;
}

export interface Ctx {
  root: string;
  prev: Brand;
  next: Brand;
  tokens: TokenRule[];
  files: FileIndex;
  log: Logger;
  flags: EngineFlags;
  /**
   * Paths claimed by a specific transform, which the broad content sweep must
   * leave alone. Without this, the sweep and (say) the MCAP compatibility
   * transform would both write `ros2_message_decoder.dart` and the run would
   * abort as a plan conflict. Populated by the runner before planning.
   */
  owned: Set<string>;
}

export interface EngineFlags {
  dryRun: boolean;
  only: string[] | null;
  skip: string[];
  allowDirty: boolean;
  breakMcapCompat: boolean;
  noVerify: boolean;
  force: boolean;
  fromBaseline: string | null;
}

export interface Transform {
  id: string;
  title: string;
  /** Transform ids that must run before this one. */
  needs?: string[];
  /**
   * Repo-relative paths this transform writes exclusively. Declaring a path
   * here removes it from the broad content sweep, so the transform is fully
   * responsible for it - including running the token rewrite itself.
   */
  owns?(prev: Brand, next: Brand): string[];
  enabled?(ctx: Ctx): boolean;
  plan(ctx: Ctx): Promise<Change[]>;
}

// ---------------------------------------------------------------------------
// Token rules
// ---------------------------------------------------------------------------

/**
 * One rename rule. `kind` decides how the match is anchored:
 *
 * - `literal` matches the exact string anywhere. Used for tokens that are
 *   already unambiguous because they carry their own delimiter
 *   (`package:stera/`, `@stera/`, `open.fpvlabs.stera`).
 * - `word` matches only when not adjacent to `[A-Za-z0-9_]` on either side.
 *   Used for the bare tokens (`stera`, `Stera`) that would otherwise corrupt
 *   `sisteransi` in bun.lock or `steraRecorderExample` in the plugin example.
 */
export interface TokenRule {
  kind: "literal" | "word";
  from: string;
  to: string;
  /** Human-readable reason, surfaced in --dry-run output. */
  label: string;
}
