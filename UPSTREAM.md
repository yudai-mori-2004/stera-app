# Upstream maintenance

RootLens is a white-label distribution of
[`fpv-labs/stera-app`](https://github.com/fpv-labs/stera-app). The app name,
bundle IDs, legal links, colours, and artwork belong to RootLens. Capture and
data compatibility remain Stera-native.

## Compatibility boundary

The following identifiers must remain unchanged unless FPV Labs publishes a
coordinated data-format migration:

- Dart app package: `stera`
- Recorder package: `stera_recorder`
- Recorder Kotlin package: `open.fpvlabs.stera.ar_recorder`
- MCAP schema namespace: `stera`
- MCAP writer library: `fpv_labs/1.0`

`packages/stera_recorder/` should match upstream. Product attribution is read
from the generated app-level `Attribution` class so the recorder package does
not need RootLens-specific edits.

## Update flow

The weekly `upstream sync` workflow opens a PR from `fpv-labs:main` when new
commits are available. It never auto-merges an update.

For each PR:

1. Read the upstream changes, especially native recorder and MCAP changes.
2. Resolve conflicts in favour of the compatibility boundary above. Keep
   RootLens values in `packages/brand/brand.json` and generated brand seams.
3. Run:

   ```bash
   bun install --frozen-lockfile
   bun run brand:verify
   bun run brand:test
   bun run check-types
   cd apps/mobile
   flutter analyze
   flutter test
   flutter build ios --debug --no-codesign
   ```

4. On a physical iPhone, record and stop a session, open its MCAP preview, and
   export/share the file. Merge only after that device test passes.
5. Record the merged upstream commit in the RootLens release notes.

The checked-in app defaults to RootLens-owned API hosts. Local capture uses
`NO_AUTH_MODE=true` and does not contact a backend. Connecting a production
build to FPV Labs-hosted services requires an explicit API, authentication,
data-ownership, and version-support agreement; adopting the Apache-licensed
code alone does not grant that service access.
