/**
 * The upstream (Stera / FPV Labs) brand, expressed in the same shape as any
 * fork's.
 *
 * This is the `prev` value on the very first run. Because it is a normal
 * `Brand`, run 1 (Stera -> Acme) goes through exactly the same code path as run
 * 2 (Acme -> Acme2); there is no "initial rename" special case anywhere in the
 * engine.
 *
 * Every value here is a fact about the upstream tree, so it is written out
 * literally rather than derived - `derive()` would produce a *tidier* Stera than
 * the one that actually exists on disk, and the token engine needs the messy
 * truth. The three-way app-id disagreement below is real and is the thing a
 * rebrand normalises:
 *
 *   Android applicationId   open.fpvlabs.stera
 *   iOS PRODUCT_BUNDLE_ID   com.fpvlabs.fpvlabs
 *   Play Store update URL   com.fpvlabs.fpv
 */

import { BASE_PALETTE } from "./palette.ts";
import { SHAPE_SCALES, UPSTREAM_SHAPE_STYLE } from "./shape.ts";
import { SPACE_SCALES, UPSTREAM_SPACE_STYLE } from "./space.ts";
import {
  TYPE_SCALES,
  UPSTREAM_TYPE_STYLE,
  UPSTREAM_TYPE_WEIGHTS,
} from "./type.ts";
import type { Brand } from "./types.ts";

/**
 * sha256 of the upstream artwork that a rebrand must replace.
 *
 * These exist so `verify.ts` can tell "the fork supplied its own mark" from
 * "the engine warned, nobody read the warning, and the sign-in sheet still
 * shows Stera's logo". A name and a bundle id are easy to check by grep; a PNG
 * that never changed is invisible until someone opens the app.
 */
export const UPSTREAM_ASSET_HASHES: Readonly<Record<string, string>> = {
  "apps/mobile/assets/icon/logo_light.png":
    "7fd66301426aff7aee5075ed3f1dcd95891a508c3e9ae7c09f5112abbe579ee9",
  "apps/mobile/assets/icon/logo_dark.png":
    "a4ff255051940f8fef7aa7af4e9954ccdc9dcf8beca6a56c74078ecde857f257",
  "apps/mobile/ios/Runner/Assets.xcassets/LaunchLogo.imageset/logo_light.png":
    "7fd66301426aff7aee5075ed3f1dcd95891a508c3e9ae7c09f5112abbe579ee9",
  "apps/mobile/ios/Runner/Assets.xcassets/LaunchLogo.imageset/logo_dark.png":
    "a4ff255051940f8fef7aa7af4e9954ccdc9dcf8beca6a56c74078ecde857f257",
  "assets/logo_light.png":
    "7fd66301426aff7aee5075ed3f1dcd95891a508c3e9ae7c09f5112abbe579ee9",
  "assets/logo_dark.png":
    "a4ff255051940f8fef7aa7af4e9954ccdc9dcf8beca6a56c74078ecde857f257",
};

export const UPSTREAM_BRAND: Brand = {
  engineVersion: 1,

  brand: {
    name: "Stera",
    shortName: "Stera",
    slug: "stera",
    tagline: "infra for spatial intelligence",
    legalEntity: "FPV Labs",
    copyrightYear: 2026,
  },

  identifiers: {
    // The Android applicationId is treated as upstream's canonical id; the iOS
    // and Play Store ids live in `legacy` because they disagree with it.
    bundleId: "open.fpvlabs.stera",
    androidApplicationId: "open.fpvlabs.stera",
    androidNamespace: "open.fpvlabs.stera",
    kotlinPackage: "open.fpvlabs.stera",
    dartPackage: "stera",
    npmScope: "@stera",
    repoName: "stera-open",
    recorder: {
      rename: true,
      dartPackage: "stera_recorder",
      kotlinPackage: "open.fpvlabs.stera.ar_recorder",
      pluginClass: "SteraRecorderPlugin",
      podName: "stera_recorder",
      swiftObjcTarget: "stera_recorder_objc",
      examplePackage: "open.fpvlabs.stera_recorder_example",
      exampleIosBundleId: "open.fpvlabs.steraRecorderExample",
    },
    mcapSchemaNamespace: "stera",
    mcapWriterLibrary: "fpv_labs/1.0",
    driftDatabaseName: "stera",
    bookmarkKeyPrefix: "open.fpvlabs.stera.bookmark.",
    systemdServiceName: "stera-server",
    deployDirName: "stera-open",
    r2Bucket: "stera-uploads",
    r2BucketProd: "stera-uploads-prod",
  },

  urls: {
    website: "https://www.fpvlabs.ai",
    termsAndConditions: "https://www.fpvlabs.ai/terms",
    privacyPolicy: "https://www.fpvlabs.ai/privacy",
    contactEmail: "contact@fpvlabs.ai",
    discordInvite: "https://www.fpvlabs.ai/discord",
    sourceRepo: "https://github.com/fpv-labs/stera-app",
    apiHostDev: "api.example.com",
    apiHostProd: "app.fpvlabs.ai",
    // Upstream ships no update feed of its own: the ids it used to carry
    // belonged to the closed-source FPV Labs app, not to this repo. `legacy`
    // below still remembers them so the token sweep can scrub any leftovers.
    playStoreAppId: null,
    appStoreId: null,
    updateFeed: null,
  },

  apple: {
    // Null because the upstream tree really does ship a blank
    // `DEVELOPMENT_TEAM` - signing material is not published. Set
    // `apple.developmentTeam` in brand.json, or set it in Xcode.
    developmentTeam: null,
    signInServiceId: "open.fpvlabs.stera.signin",
    backgroundTaskPrefix: "open.fpvlabs.stera",
  },

  theme: {
    brandAccentLight: "0xFFE8A33D",
    brandAccentDark: "0xFFFFB740",
    launchBackgroundLight: "0xFFF7F4ED",
    launchBackgroundDark: "0xFF2E2F31",
    launchForegroundLight: "0xFF18191B",
    launchForegroundDark: "0xFFFFFFFF",
    tint: 0,
    allowLowContrast: false,
    overrides: {},
    // The literals in colors.dart, verbatim. `prev.theme.palette` is what
    // `60-theme` matches against when it rewrites that file into references,
    // so this has to be the messy truth on disk, not a tidied derivation.
    palette: BASE_PALETTE,
    shape: {
      style: UPSTREAM_SHAPE_STYLE,
      scale: SHAPE_SCALES[UPSTREAM_SHAPE_STYLE],
    },
    type: {
      style: UPSTREAM_TYPE_STYLE,
      scale: TYPE_SCALES[UPSTREAM_TYPE_STYLE],
      weights: UPSTREAM_TYPE_WEIGHTS,
    },
    space: {
      style: UPSTREAM_SPACE_STYLE,
      scale: SPACE_SCALES[UPSTREAM_SPACE_STYLE],
    },
  },

  fonts: {
    display: "EBGaramond",
    body: "Geist",
    mono: "GeistMono",
    accent: "Handjet",
    files: {},
    replaceBundled: false,
  },

  assets: {
    iconSource: null,
    iconForeground: null,
    iconBackgroundColor: "0xFFF7F4ED",
    iconMonochrome: null,
    logoLight: null,
    logoDark: null,
    splashTexture: null,
  },

  copy: {
    appName: "Stera",
    appNameShort: "Stera",
    appTitle: "Stera by FPV Labs",
    splashTitle: "Stera",
    splashSubtitle: "by FPV Labs",
    loginTagline:
      "Collect multimodal videos, upload them securely and get high fidelity data though our processing suite for robotics and world model training",
    iosUsageDescriptions: {
      camera:
        "FPV Labs uses your camera to record and capture high-quality video for spatial AI training. Only when you provide consent.",
      motion:
        "FPV Labs uses motion sensors (accelerometer and gyroscope) to capture IMU data during AR recording for spatial AI training.",
      photoLibrary:
        "FPV Labs needs access to your photo library to select and upload videos for spatial AI training.",
      photoLibraryAdd:
        "FPV Labs needs permission to save your recorded and processed videos to your gallery.",
      microphone: "Voice commands are used to control recording hands-free.",
      speechRecognition:
        "Voice commands are used to control recording hands-free.",
    },
  },

  attribution: {
    enabled: false,
    upstreamName: "Stera",
    upstreamOrg: "FPV Labs",
    upstreamRepo: "https://github.com/fpv-labs/stera-app",
    text: "Powered by Stera",
    showInProfileFooter: false,
    showInReadme: false,
    showInAttributionFile: false,
    showInMcapMetadata: false,
  },

  compat: {
    keepMcapAliases: true,
    renameDriftDatabase: true,
    renameBookmarkPrefix: true,
  },

  // Upstream is nobody's fork, so it was matched to nothing.
  reference: null,

  legacy: {
    iosBundleId: "com.fpvlabs.fpvlabs",
    playStoreAppId: "com.fpvlabs.fpv",
  },
};
