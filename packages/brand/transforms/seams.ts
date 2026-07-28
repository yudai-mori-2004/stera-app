/**
 * `60-theme`, `65-copy` and `80-attribution`.
 *
 * These are the only transforms that change program *structure* rather than
 * just strings, and they run exactly once. On the first rebrand they hoist
 * every brand literal out of the widget tree and into three generated files;
 * from then on, changing the brand is a matter of regenerating those files.
 * Every edit is guarded by a marker (the presence of the generated import), so
 * a second run is a strict no-op rather than a double application.
 *
 * Because a seam transform owns its files, it also performs the token rewrite
 * that the broad sweep would otherwise have done - the sweep skips owned paths.
 * Seam substitutions run *before* the token rewrite, matching the known
 * upstream literals, so they never have to guess what the new brand name is.
 */

import {
  addDartImport,
  isRadiusSweepTarget,
  rewriteFontFamilies,
  rewriteRadii,
  rewriteSpacing,
} from "../lib/dartsweep.ts";
import {
  ATTRIBUTION_DART_PATH,
  BRAND_DART_PATH,
  BRAND_FONTS_PATH,
  BRAND_PALETTE_PATH,
  BRAND_SHAPE_PATH,
  BRAND_SPACE_PATH,
  BRAND_TYPE_PATH,
  COLORS_DART_PATH,
  INFO_PLIST_PATH,
  LAUNCH_BACKGROUND_COLORSET,
  LAUNCH_FOREGROUND_COLORSET,
  STORYBOARD_PATH,
  STRINGS_XML_PATH,
  buildAttributionDart,
  buildBrandDart,
  buildBrandFontsDart,
  buildBrandPaletteDart,
  buildBrandShapeDart,
  buildBrandSpaceDart,
  buildBrandTypeDart,
  buildColorsetJson,
  patchColorsDart,
  patchInfoPlist,
  patchStoryboard,
  patchStringsXml,
} from "../lib/generate.ts";
import { applyTokens } from "../lib/tokens.ts";
import type { Brand, Change, Ctx, Transform } from "../lib/types.ts";

// ---------------------------------------------------------------------------
// Dart import helper
// ---------------------------------------------------------------------------

const importLine = (dartPackage: string, path: string): string =>
  `import "package:${dartPackage}/${path}";`;

const addImport = addDartImport;

/** Applies literal substitutions in order; returns the text plus a hit count. */
const substitute = (
  source: string,
  pairs: ReadonlyArray<[string, string]>
): { text: string; hits: number } => {
  let text = source;
  let hits = 0;
  for (const [from, to] of pairs) {
    if (!text.includes(from)) {
      continue;
    }
    text = text.split(from).join(to);
    hits += 1;
  }
  return { text, hits };
};

/**
 * Reads a file, applies seam substitutions, then the token rewrite, and returns
 * a write Change only if something actually changed.
 */
const seam = async (
  ctx: Ctx,
  path: string,
  edit: (source: string) => string,
  order: "edit-then-rename" | "rename-then-edit" = "edit-then-rename"
): Promise<Change[]> => {
  if (!ctx.files.exists(path)) {
    ctx.log.warn(`seam target ${path} not found - skipping`);
    return [];
  }
  const original = await ctx.files.read(path);

  // Order matters, and which one you want depends on what the edit produces.
  //
  // `edit-then-rename` is the default: the edit matches known *upstream*
  // literals ("Stera", the old URLs), so it must see the file before the
  // rename, and its output is then renamed along with everything else.
  //
  // `rename-then-edit` is for edits that emit text which must survive the
  // rename untouched - the attribution block being the whole reason this
  // option exists. Generating "Powered by Stera" and then running the token
  // engine over it produces "Powered by Acme Vision", which defeats the point.
  const renamed =
    order === "edit-then-rename"
      ? applyTokens(edit(original), ctx.tokens).text
      : edit(applyTokens(original, ctx.tokens).text);

  // Owning a file removes it from the broad sweep, so the radius rewrite that
  // `20-rewrite-content` performs has to happen here too - otherwise the eight
  // or so seam-owned widgets would be the only ones in the app still carrying
  // literal corner radii.
  const final = isRadiusSweepTarget(path)
    ? rewriteSpacing(
        rewriteRadii(renamed, ctx.next.identifiers.dartPackage).text,
        ctx.next.identifiers.dartPackage
      ).text
    : renamed;

  return final === original ? [] : [{ kind: "write", path, contents: final }];
};

// ---------------------------------------------------------------------------
// 60-theme
// ---------------------------------------------------------------------------

const TEXT_THEME_PATH = "apps/mobile/lib/src/core/theme/app_text_theme.dart";

export const theme: Transform = {
  id: "60-theme",
  title: "Generate the design tokens and wire the theme to them",
  needs: ["20-rewrite-content"],

  owns(): string[] {
    return [
      COLORS_DART_PATH,
      TEXT_THEME_PATH,
      LAUNCH_BACKGROUND_COLORSET,
      LAUNCH_FOREGROUND_COLORSET,
      STORYBOARD_PATH,
    ];
  },

  async plan(ctx: Ctx): Promise<Change[]> {
    const changes: Change[] = [
      {
        kind: "write",
        path: BRAND_PALETTE_PATH,
        contents: buildBrandPaletteDart(ctx.next),
      },
      {
        kind: "write",
        path: BRAND_SHAPE_PATH,
        contents: buildBrandShapeDart(ctx.next),
      },
      {
        kind: "write",
        path: BRAND_FONTS_PATH,
        contents: buildBrandFontsDart(ctx.next),
      },
      {
        kind: "write",
        path: BRAND_TYPE_PATH,
        contents: buildBrandTypeDart(ctx.next),
      },
      {
        kind: "write",
        path: BRAND_SPACE_PATH,
        contents: buildBrandSpaceDart(ctx.next),
      },
      {
        kind: "write",
        path: LAUNCH_BACKGROUND_COLORSET,
        contents: buildColorsetJson(
          ctx.next.theme.launchBackgroundLight,
          ctx.next.theme.launchBackgroundDark
        ),
      },
      {
        kind: "write",
        path: LAUNCH_FOREGROUND_COLORSET,
        contents: buildColorsetJson(
          ctx.next.theme.launchForegroundLight,
          ctx.next.theme.launchForegroundDark
        ),
      },
    ];

    // colors.dart: hoist every colour literal into the generated palette. Until
    // this existed only `brandAccent` was reachable from brand.json, which is
    // why setting a brand colour used to recolour a badge and nothing else.
    const paletteImport = importLine(
      ctx.next.identifiers.dartPackage,
      "src/core/theme/brand_palette.dart"
    );

    changes.push(
      ...(await seam(ctx, COLORS_DART_PATH, (source) => {
        const patch = patchColorsDart(source, ctx.prev);
        if (patch.rewritten === 0) {
          return source;
        }
        for (const drift of patch.drifted) {
          ctx.log.warn(
            `${COLORS_DART_PATH}: ${drift}. A hand-edited colour is being replaced by the ` +
              `value from brand.json - put it in theme.overrides to keep it.`
          );
        }
        ctx.log.info(`  hoisted ${patch.rewritten} colour literal(s) into BrandPalette`);
        return addImport(patch.text, paletteImport);
      }))
    );

    // app_text_theme.dart: the app's only file naming a typeface. `fonts.*` has
    // been in the schema since the beginning with nothing reading it; this is
    // what makes it real.
    changes.push(
      ...(await seam(ctx, TEXT_THEME_PATH, (source) => {
        const { text, hits } = rewriteFontFamilies(
          source,
          ctx.prev.fonts,
          ctx.next.identifiers.dartPackage
        );
        if (hits > 0) {
          ctx.log.info(`  routed ${hits} font family reference(s) through BrandFonts`);
        }
        return text;
      }))
    );

    changes.push(
      ...(await seam(ctx, STORYBOARD_PATH, (source) => patchStoryboard(source, ctx.next)))
    );

    return changes;
  },
};

// ---------------------------------------------------------------------------
// 65-copy
// ---------------------------------------------------------------------------

const M = "apps/mobile/lib/src";

export const copySeamTargets = (prev: Brand): Array<{
  path: string;
  needs: string;
  pairs: ReadonlyArray<[string, string]>;
}> => [
  {
    path: `${M}/core/config/constants/app_constants.dart`,
    needs: "Brand.termsAndConditions",
    pairs: [
      [
        `static const String termsAndConditions = "${prev.urls.termsAndConditions}";`,
        "static const String termsAndConditions = Brand.termsAndConditions;",
      ],
      [
        `static const String privacyPolicy = "${prev.urls.privacyPolicy}";`,
        "static const String privacyPolicy = Brand.privacyPolicy;",
      ],
      [
        `static const String contactEmail = "${prev.urls.contactEmail}";`,
        "static const String contactEmail = Brand.contactEmail;",
      ],
      [
        `static const String discordInvite = "${prev.urls.discordInvite ?? ""}";`,
        'static const String discordInvite = Brand.discordInvite ?? "";',
      ],
      [
        `static const String sourceRepo = "${prev.urls.sourceRepo}";`,
        "static const String sourceRepo = Brand.sourceRepo;",
      ],
    ],
  },
  {
    path: `${M}/modules/startup/ui/startup_view.dart`,
    needs: "Brand.appTitle",
    pairs: [[`title: "${prev.copy.appTitle}",`, "title: Brand.appTitle,"]],
  },
  {
    path: `${M}/modules/startup/ui/splash_view.dart`,
    needs: "Brand.splashTitle",
    pairs: [
      [
        `Text("${prev.copy.splashTitle}", style: context.textTheme.head3XlGaramond)`,
        "Text(Brand.splashTitle, style: context.textTheme.head3XlGaramond)",
      ],
      [
        `Text("${prev.copy.splashSubtitle}", style: context.textTheme.bodyXs)`,
        "Text(Brand.splashSubtitle, style: context.textTheme.bodyXs)",
      ],
    ],
  },
  {
    path: `${M}/modules/home/ui/home_page.dart`,
    needs: "Brand.appName",
    pairs: [[`text1: "${prev.copy.appName}",`, "text1: Brand.appName,"]],
  },
  {
    path: `${M}/modules/home/ui/widgets/app_update_bottomsheet.dart`,
    needs: "Brand.appName",
    pairs: [
      [
        `"A new version of ${prev.copy.appName} is ready to install."`,
        '"A new version of ${Brand.appName} is ready to install."',
      ],
    ],
  },
  {
    path: `${M}/modules/home/ui/widgets/recording_guide_bottomsheet.dart`,
    needs: "Brand.appName",
    pairs: [
      [`title: "Upload in ${prev.copy.appName}",`, 'title: "Upload in ${Brand.appName}",'],
      [
        `"Open ${prev.copy.appName} and tap the + on the bottom bar.",`,
        '"Open ${Brand.appName} and tap the + on the bottom bar.",',
      ],
    ],
  },
  {
    path: `${M}/modules/auth/ui/widgets/login_modal.dart`,
    needs: "Brand.loginTagline",
    pairs: [[`"${prev.copy.loginTagline}",`, "Brand.loginTagline,"]],
  },
  {
    // Unlike the pairs above, these match fixed literals rather than the
    // previous brand's strings: the un-seamed tree ships all three as `null`,
    // which is what keeps the updater off until a fork configures it.
    path: `${M}/core/common/utils/app_update.dart`,
    needs: "Brand.updateFeedUrl",
    pairs: [
      [
        "static const String? _updateFeedUrl = null;",
        "static const String? _updateFeedUrl = Brand.updateFeedUrl;",
      ],
      [
        "static const String? _playStoreUrl = null;",
        "static const String? _playStoreUrl = Brand.playStoreUrl;",
      ],
      [
        "static const String? _appStoreUrl = null;",
        "static const String? _appStoreUrl = Brand.appStoreUrl;",
      ],
    ],
  },
];

export const copy: Transform = {
  id: "65-copy",
  title: "Generate brand strings and route the UI through them",
  needs: ["20-rewrite-content"],

  owns(prev: Brand): string[] {
    return [
      ...copySeamTargets(prev).map((target) => target.path),
      STRINGS_XML_PATH,
      INFO_PLIST_PATH,
    ];
  },

  async plan(ctx: Ctx): Promise<Change[]> {
    const changes: Change[] = [
      { kind: "write", path: BRAND_DART_PATH, contents: buildBrandDart(ctx.next) },
    ];

    const brandImport = importLine(
      ctx.next.identifiers.dartPackage,
      "src/core/config/constants/brand.dart"
    );

    let seamed = 0;
    for (const target of copySeamTargets(ctx.prev)) {
      const result = await seam(ctx, target.path, (source) => {
        if (source.includes(target.needs)) {
          return source;
        }
        const { text, hits } = substitute(source, target.pairs);
        if (hits === 0) {
          ctx.log.warn(
            `${target.path}: no brand literal matched. The upstream copy may have changed; ` +
              `check whether a string needs hoisting into brand.dart by hand.`
          );
          return source;
        }
        seamed += 1;
        return addImport(text, brandImport);
      });
      changes.push(...result);
    }

    if (seamed > 0) {
      ctx.log.info(`  hoisted brand literals out of ${seamed} Dart file(s)`);
    }

    changes.push(
      ...(await seam(ctx, STRINGS_XML_PATH, (source) => patchStringsXml(source, ctx.next))),
      ...(await seam(ctx, INFO_PLIST_PATH, (source) => patchInfoPlist(source, ctx.next)))
    );

    return changes;
  },
};

// ---------------------------------------------------------------------------
// 80-attribution
// ---------------------------------------------------------------------------

const PROFILE_FOOTER_PATH = `${M}/modules/profile/ui/widgets/profile_footer.dart`;
const BADGE_PATH = `${M}/core/common/widgets/open_source_badge.dart`;
const ATTRIBUTION_MD_PATH = "packages/brand/ATTRIBUTION.md";
const README_PATH = "README.md";

const README_START = "<!-- brand:attribution:start -->";
const README_END = "<!-- brand:attribution:end -->";

const buildAttributionMd = (brand: Brand): string => {
  const a = brand.attribution;
  return `# Attribution

${brand.copy.appName} is a fork of [${a.upstreamName}](${a.upstreamRepo}) by ${a.upstreamOrg}.

The upstream copyright notice and licence are retained in \`LICENSE\` and in
\`packages/${brand.identifiers.recorder.dartPackage}/LICENSE\`. Those files are excluded from the
rebrand engine and must not be rewritten - retaining them is a licence condition,
not a courtesy.

## What was rebranded

This fork was produced with \`bun run brand:apply\`, which rewrote the product
name, application identifiers, package names, theme accent and launch assets
from the values in \`packages/brand/brand.json\`. See \`packages/brand/README.md\` for how to change
them again.
`;
};

// The paper and the dataset belong to the upstream project, so their URLs are
// fixed here rather than derived. The rest of README.md goes through the rename
// sweep, which would turn `Stera-10M` into `Acme-10M` and the Hugging Face link
// into a 404 — a fork citing a dataset that does not exist is worse than a fork
// that never cited one. `packages/brand/` is in NEVER_REWRITE, so these survive.
const UPSTREAM_PAPER_URL = "https://arxiv.org/abs/2605.05945";
const UPSTREAM_DATASET_URL = "https://huggingface.co/datasets/fpvlabs/stera-10m";
const UPSTREAM_DATASET_NAME = "Stera-10M";

const readmeCredits = (brand: Brand): string =>
  [
    README_START,
    "",
    "## Credits",
    "",
    `${brand.attribution.text} — built on [${brand.attribution.upstreamName}](${brand.attribution.upstreamRepo}) by ${brand.attribution.upstreamOrg}.`,
    "",
    `The upstream work is described in [MobileEgo Anywhere](${UPSTREAM_PAPER_URL}), and the`,
    `[${UPSTREAM_DATASET_NAME}](${UPSTREAM_DATASET_URL}) dataset is released separately under CC BY-NC 4.0.`,
    "",
    README_END,
  ].join("\n");

export const attribution: Transform = {
  id: "80-attribution",
  title: "Retain credit to the upstream project",
  needs: ["65-copy"],

  owns(): string[] {
    return [PROFILE_FOOTER_PATH, BADGE_PATH, README_PATH];
  },

  async plan(ctx: Ctx): Promise<Change[]> {
    const a = ctx.next.attribution;
    const changes: Change[] = [
      {
        kind: "write",
        path: ATTRIBUTION_DART_PATH,
        contents: buildAttributionDart(ctx.next),
      },
    ];

    if (a.showInAttributionFile) {
      changes.push({
        kind: "write",
        path: ATTRIBUTION_MD_PATH,
        contents: buildAttributionMd(ctx.next),
      });
    }

    // The badge says "OPEN SOURCE", which stays true after a fork, so the
    // widget survives intact - only its doc comment names the old brand.
    changes.push(...(await seam(ctx, BADGE_PATH, (source) => source)));

    const brandImport = importLine(
      ctx.next.identifiers.dartPackage,
      "src/core/config/constants/brand.dart"
    );
    const attributionImport = importLine(
      ctx.next.identifiers.dartPackage,
      "src/core/config/constants/attribution.dart"
    );

    changes.push(
      ...(await seam(ctx, PROFILE_FOOTER_PATH, (source) => {
        let text = source;

        if (!text.includes("Brand.appName")) {
          text = substitute(text, [
            [
              `semanticLabel: "View ${ctx.prev.copy.appName} source code on GitHub",`,
              'semanticLabel: "View ${Brand.appName} source code on GitHub",',
            ],
            [
              `"${ctx.prev.copy.appName} is open source — view the code on GitHub",`,
              '"${Brand.appName} is open source — view the code on GitHub",',
            ],
          ]).text;
          text = addImport(text, brandImport);
        }

        if (a.showInProfileFooter && !text.includes("Attribution.text")) {
          // Sits beneath the existing "view the source" pressable, so the fork's
          // own repo link stays primary and the upstream credit reads as a
          // footnote rather than competing with it.
          const anchor = "          ),\n        ],\n      ),\n    );";
          const credit = `          ),
          if (Attribution.enabled && Attribution.showInProfileFooter)
            Pressable(
              behavior: HitTestBehavior.opaque,
              semanticLabel:
                  "Visit \${Attribution.upstreamName}, the upstream project",
              onTap: () =>
                  AppUrlLauncher.launchUrl(Attribution.upstreamRepo),
              child: Text(
                Attribution.text,
                textAlign: TextAlign.center,
                style: context.textTheme.bodyXs.copyWith(
                  color: context.colors.textTertiary,
                ),
              ),
            ),
        ],
      ),
    );`;
          if (text.includes(anchor)) {
            text = text.replace(anchor, credit);
            text = addImport(text, attributionImport);
          } else {
            ctx.log.warn(
              `${PROFILE_FOOTER_PATH}: could not find the insertion point for the attribution line. ` +
                `Add it by hand, or set attribution.showInProfileFooter to false.`
            );
          }
        }

        return text;
      }))
    );

    if (a.showInReadme) {
      changes.push(
        ...(await seam(
          ctx,
          README_PATH,
          (source) => {
            const block = readmeCredits(ctx.next);
            const start = source.indexOf(README_START);
            const end = source.indexOf(README_END);
            if (start !== -1 && end !== -1) {
              return (
                source.slice(0, start) + block + source.slice(end + README_END.length)
              );
            }
            return `${source.trimEnd()}\n\n${block}\n`;
          },
          // The credit names the upstream project on purpose; inserting it
          // after the rename is what keeps it saying "Stera".
          "rename-then-edit"
        ))
      );
    }

    return changes;
  },
};
