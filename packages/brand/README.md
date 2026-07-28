# White-label engine

Turns this repository into a different product: new name, icons, theme,
application identifiers, package names and deployment config, driven from a
single `packages/brand/brand.json`.

```bash
bun install                 # required first - see "sharp" below
bun run brand:accent <art>  # suggest an accent colour from your logo
bun run brand:preview       # render brand.json as a page you can look at
bun run brand:check         # print the plan, touch nothing
bun run brand:apply         # do it
bun run brand:verify        # structural checks
```

Or run `/whitelabel` in Claude Code, which conducts the interview, writes
`brand.json` for you, drives the preview loop, and walks through the manual
steps afterwards. Give it a reference — your marketing site, a design system, a
brand kit — and it reads the tokens off that and maps them onto the fields
below, instead of asking you for hex codes you would have to go look up.

The engine never commits. Review `git diff` and commit when you are happy.

## Start with the preview

`bun run brand:preview` writes `preview.html` — a self-contained page rendered
from `brand.json` that **applies nothing**. It shows the launcher icon under
each platform's mask, the in-app mark on light and dark plates, mock splash /
sign-in / home / profile screens in both modes, every colour token with its
WCAG grade, the type specimens, the radius scale, and a table of what changes
against what is on disk.

That is the loop this package is built around: edit `brand.json`, re-render,
look, repeat — then apply once. Before it existed the first look at a rebrand
was `flutter build` after ~360 files had already been rewritten, which is a
poor place to discover that the accent is unreadable or the wordmark vanishes
in dark mode.

It reads only, never needs `sharp`, and works on a dirty tree, so run it as
often as you like. `preview.html` is gitignored.

## How it works

`apply.ts` is a function of `(prev, next)`:

- `next` is `packages/brand/brand.json`, resolved through `lib/derive.ts`.
- `prev` is whatever brand is currently applied, read from `packages/brand/.applied.json`
  — or, on the very first run, the `UPSTREAM_BRAND` literal in `lib/upstream.ts`.

That is the whole trick. After run 1 the string `stera` no longer exists
anywhere, so a grep-replace would have nothing to find; recording the applied
brand makes run 2 (`Acme → Acme2`) the same operation as run 1
(`Stera → Acme`), with no special case for "the first one".

Transforms **only read**. Each returns a list of `Change`s; the runner collects
the whole plan, rejects it if two transforms want the same file, and only then
writes. `--dry-run` is just "stop before the writing part".

## Layout

| Path | What |
|---|---|
| `brand.json` | Your configuration. The only file you should edit. |
| `brand.schema.json` | JSON Schema — gives editors autocomplete and inline docs. |
| `.applied.json` | State ledger. Do not edit; deleting it makes the next run assume the tree is still upstream. |
| `lib/tokens.ts` | The rename engine. Read this one first. |
| `lib/derive.ts` | Sparse config → fully resolved brand. |
| `lib/palette.ts` | The app's colour tokens as data: base values, tint weights, contrast contract. |
| `lib/color.ts` | Colour maths: parsing, mixing, WCAG contrast. No dependencies on anything else here. |
| `lib/shape.ts` | The corner-radius scale. |
| `lib/type.ts` | The type ramp and the weight roles. |
| `lib/space.ts` | The spacing scale. |
| `lib/fonts.ts` | Typeface roles and the pubspec `fonts:` block. |
| `lib/dartsweep.ts` | Broad Dart rewrites (radii, font families) that ride along with the token sweep. |
| `lib/paths.ts` | Directory renames. |
| `lib/generate.ts` | Builders for the files the engine owns. |
| `lib/previewhtml.ts` | The preview renderer. |
| `transforms/` | The registry, in execution order. |
| `generated/` | Rasterised icon masters. Committed, so CI needs neither sharp nor your source art. |
| `source/` | Your artwork. Gitignored. |
| `docs/whitelabel-guide.html` | Step-by-step guide for whoever is forking. Open it in a browser. |

## The guide

`docs/whitelabel-guide.html` is a self-contained walkthrough aimed at the person
doing the rebrand — open it directly, no server needed. It is styled with this
app's own design tokens and set in its own typefaces, so it looks like the thing
it documents.

Edit `docs/guide.src.html`, then rebuild:

```bash
bun run brand:guide
```

The build inlines the Latin-subset woff2 faces from `docs/fonts/` as data URIs.
That is not premature optimisation: a published page runs under a CSP that
blocks font CDNs, so a linked webfont would fall back to Georgia in silence.
`docs/build.ts` records the `pyftsubset` command for regenerating those subsets
if the app's fonts ever change.

## The two things most likely to bite you

**`bun install` first.** Without `node_modules`, Bun auto-installs `sharp` on
first import and can resolve it to a WebAssembly build that crashes mid-run with
an out-of-bounds memory access. `00-preflight` refuses to start if dependencies
are missing.

**Word boundaries are load-bearing.** `bun.lock` contains `sisteransi`. A naive
`s/stera/acme/g` corrupts it into a package that does not exist and breaks
`bun install` with an error pointing nowhere near the rebrand. `lib/tokens.ts`
scans left to right, longest rule first, and anchors bare tokens on
`[A-Za-z0-9_]` on both sides. `bun test packages/brand/` proves it, and the lockfiles are
regenerated rather than rewritten regardless.

## In-app updates are off until you ask for them

`urls.playStoreAppId`, `urls.appStoreId` and `urls.updateFeed` all default to
`null`, and with all three unset the app never checks for a new version and
never prompts. That is the correct state for a fork that has not shipped
anywhere yet, and it is deliberately not derived from `bundleId`: an id you have
not actually published under points the updater at somebody else's listing, and
the symptom — your users being told to install a stranger's app — appears only in
production. `checkUpdateFeedWired` in `verify.ts` fails on any URL literal left
in `app_update.dart` for the same reason.

Once you have published, set the store id you published under (it must equal
`identifiers.bundleId`, because the lookup keys off the id the running app was
built with) and re-run `brand:apply`. If you distribute outside the stores,
point `urls.updateFeed` at a [Sparkle-style appcast
XML](https://sparkle-project.org/documentation/publishing/) instead — it takes
precedence over both store ids on both platforms.

## Staying branded

The first `brand:apply` writes `.github/workflows/brand.yml` — once; after that
it is the fork's file. It runs `bun test packages/brand/` and `bun run
brand:verify` on every PR.

This is aimed at one failure, which is cumulative and invisible: a fork rebrands,
verifies green, and later merges upstream. The merge brings a widget carrying
`Color(0xFF18191B)`, a `fontSize: 14` and the string "Stera". All three compile,
pass the tests, and are indistinguishable from the other four hundred files in
the diff. `brand:verify` finds them in seconds; nothing else finds them until
someone opens the app.

## Seams

The first run does a one-time refactor: every brand literal in `apps/mobile`
moves into generated files, and the call sites start reading from them.

- `lib/src/core/config/constants/brand.dart` — names, copy, links
- `lib/src/core/theme/brand_palette.dart` — **every** colour token, light and dark
- `lib/src/core/theme/brand_shape.dart` — the corner-radius scale, read through
  `theme/app_radii.dart` (`AppRadii.md`), which is what widgets import
- `lib/src/core/theme/brand_fonts.dart` — the four typeface roles
- `lib/src/core/theme/brand_type.dart` — the type ramp and the four weights, read
  through `theme/app_type.dart` (`AppType`) and `theme/app_text_theme.dart`
- `lib/src/core/theme/brand_space.dart` — the spacing scale, read through
  `theme/app_spacing.dart` (`AppSpacing`), which is what widgets import
- `lib/src/core/config/constants/attribution.dart` — upstream credit

```dart
// before                              // after
Text("Stera", ...)                     Text(Brand.splashTitle, ...)
textPrimary: const Color(0xFF18191B)   textPrimary: BrandPalette.textPrimaryLight
BorderRadius.circular(12)              BorderRadius.circular(AppRadii.md)
Colors.white                           context.colors.neutralWhite
fontFamily: "EBGaramond"               fontFamily: BrandFonts.display
fontSize: 14                           fontSize: AppType.md
FontWeight.w600                        AppType.semibold
EdgeInsets.all(16)                     EdgeInsets.all(AppSpacing.lg)
SizedBox(height: 12)                   SizedBox(height: AppSpacing.md)
```

After that, changing the brand regenerates a handful of files instead of
regexing thirty. Each seam is marker-guarded, so a second run is a no-op. Those
files carry a `DO NOT EDIT` header and are hash-tracked in `.applied.json` —
hand-edit one and the next run refuses to start rather than silently reverting
you.

The radius, spacing and font-family rewrites are broad rather than surgical
(~100 files and ~600 call sites between them), so they run as a stage of the `20-rewrite-content` sweep instead
of as their own transform — see `lib/dartsweep.ts` for why that keeps the plan
conflict-free.

## Theme

Five knobs, in the order you would reach for them.

**`theme.brandAccentLight`** — one hex. `bun run brand:accent <artwork>` reads a
suggestion straight off your logo, and the dark-mode variant is derived by
lifting lightness rather than copying the light one.

**`theme.tint`** (0–1, default 0) — how much of the accent bleeds into the
neutral surfaces, borders and muted text. This is the one that answers "it still
looks like the same app": at 0 you get upstream's greys exactly, at 0.6 the page
background is visibly your colour. Semantic colours (red, green, blue) and the
black/white anchors never take tint, because an error that has drifted
brand-ward stops reading as an error.

**`theme.shape.style`** — `sharp`, `soft` (upstream), `rounded` or `pill`.
Every corner in the app follows it. The scale has a step for each radius the
tree actually uses, including the ones that used to be "deliberate one-offs" —
the 20px bottom-sheet top, the 30px pill button, the 1.5px grabber — because in
practice those were not one-offs at all: *every* sheet in the app is a 20, so
leaving 20 off the scale meant a fork asking for `sharp` got sharp cards and
rounded sheets. Override a single step under `theme.shape.scale`.

**`theme.type.style`** — `compact`, `default` (upstream) or `spacious`, plus
`theme.type.weights` for the four weights the tree uses. `fonts.*` decides which
typefaces the app draws with; this decides how big they are, how tightly they
are set and how heavy they run. It matters because a fork that changes only
`fonts.body` ships upstream's exact typography in someone else's typeface, which
is the most convincing way to look rebranded without being it. Nine steps, one
per size the widget tree uses, on the same principle as the radius scale: pin an
individual one under `theme.type.scale.<step>`, either measure alone.

**`theme.space.style`** — `tight`, `default` (upstream) or `comfortable`. How
much air the product has. This is the quietest of the five and the one a fork is
most likely to leave alone without noticing: a fork that moves colour, shape and
type but not density keeps upstream's exact rhythm, and nobody can name why the
app still feels like the one it forked. Fourteen steps, one per value the widget
tree uses; pin one under `theme.space.scale.<step>`.

## Nothing in a widget is a literal

The four rules that make the theme reach the product, rather than reaching 90%
of it:

- radii come from `AppRadii` (`context`-free, so `const` survives),
- colours come from `context.colors`,
- font sizes and weights come from `context.textTheme` or `AppType`,
- gaps and padding come from `AppSpacing`.

`bun run brand:verify` fails on any `BorderRadius.circular(12)`, `Color(0xFF…)`,
`Colors.white`, `fontSize: 14`, `FontWeight.w600`, `EdgeInsets.all(16)` or
`SizedBox(height: 12)` under `apps/mobile/lib/` outside `core/theme/`, and it
runs
that one check even before a fork exists, so upstream cannot regress it.
`Colors.transparent` is exempt — it is the absence of a colour, not a choice of
one.

This matters more than it looks. The failure it prevents is not a rebrand that
breaks; it is a rebrand that succeeds, verifies green, and leaves four widgets
in upstream's colours because someone matched the surrounding code six months
ago. That is invisible in a diff and obvious in the product.

`theme.overrides` pins an individual token and beats everything above it. An
unknown token name is now an error — it used to generate a constant that nothing
read, which is the whole reason a fork could set twenty overrides and see no
change.

### Contrast

The resolved palette is graded against the pairs the UI actually renders. A pair
that **met WCAG AA upstream and no longer does** blocks the run; lower the tint,
pin the token, or set `theme.allowLowContrast: true`.

A pair upstream already fails is reported and does not block — `borderDefault`
on `surfacePrimary` is 1.9:1 by design, a hairline rather than a component
outline, and refusing to rebrand over an inherited design decision would mean
refusing to run on an unmodified config.

## Fonts

`fonts.display/body/mono/accent` name families. Swapping the display face is the
cheapest change that stops a fork looking like the app it forked. To use a
family the app does not already bundle, supply the files:

```json
"fonts": {
  "display": "Inter",
  "files": { "Inter": ["packages/brand/source/fonts/Inter.ttf"] }
}
```

The engine copies them into `apps/mobile/assets/fonts/` and regenerates the
pubspec `fonts:` block. Naming a family that is neither bundled nor supplied is
a hard error, because Flutter renders an unknown family as the system face
without reporting anything — a warning would be a bug generator.

`fonts.replaceBundled: true` deletes the upstream faces no declared family still
uses, for forks that cannot redistribute them.

## Attribution

`attribution.dart`, `ATTRIBUTION.md`, `LICENSE` and the README credits block are
excluded from the rename engine, so the upstream credit survives a rebrand
instead of being renamed along with everything else. `verify.ts` asserts both
directions: that the old brand name appears nowhere outside those files, **and**
that it still appears inside them.

Setting `attribution.enabled: false` hides the in-app credit. It does not remove
your obligation to retain `LICENSE` and the copyright notice.

## Compatibility

Three renames break compatibility with data the pre-rebrand app wrote. All are
harmless for a fresh fork and destructive for an update-in-place, so they are
explicit in `brand.json`:

| Setting | If changed |
|---|---|
| `identifiers.mcapSchemaNamespace` | Existing `.mcap` recordings stop decoding. `compat.keepMcapAliases` (default on) keeps the old schema names working. |
| `identifiers.driftDatabaseName` | Existing installs start with an empty local database. |
| `identifiers.bookmarkKeyPrefix` | Saved iOS security-scoped folder bookmarks are invalidated. |

## What the engine will not do

It will not touch signing material (`DEVELOPMENT_TEAM` is **blanked**, not
inherited — a build signed against the upstream team is worse than one that
fails to sign), write real `.env` files, rewrite lockfiles textually, delete the
upstream licence, or run on a dirty tree without `--allow-dirty`.

It also does not touch `default_web_client_id` or the Google URL scheme:
`apps/mobile/tool/sync_google_client_ids.dart` owns those, deriving them from
your `.env`. Two tools writing one file is how you get a merge conflict in a
generated artefact.

Everything it cannot do for you lands in `packages/brand/TODO.md`.

## Options

### apply.ts

```
--dry-run              Print the plan and exit.
--only=<ids>           Run only these transforms.
--skip=<ids>           Skip these.
--allow-dirty          Proceed with uncommitted changes.
--break-mcap-compat    Drop the legacy MCAP schema aliases.
--force                Overwrite generated files that were hand-edited.
--list                 List transform ids.
```

### preview.ts

```
--brand=<path>         Read this config instead of brand.json.
--out=<path>           Write here instead of preview.html.
--open                 Open the result when it is written.
```
