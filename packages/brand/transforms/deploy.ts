/**
 * `85-env-deploy`, `95-lockfiles` and `99-finish`.
 *
 * The token sweep already renamed `stera-open` to the fork's repo name
 * everywhere, but it cannot know that `api.example.com` should become the
 * fork's own hostname, or that `stera-uploads` is an R2 bucket rather than a
 * word - those are not brand *tokens*, they are configuration values that
 * happen to contain one. This transform owns the handful of files where that
 * distinction matters.
 *
 * Nothing here writes a real `.env`. Only the committed `.example` files are
 * touched, and every secret stays a placeholder.
 */

import { join } from "node:path";

import { applyTokens } from "../lib/tokens.ts";
import type { Brand, Change, Ctx, Transform } from "../lib/types.ts";

const SERVER_ENV = "apps/server/.env.example";
const SERVER_ENV_PROD = "apps/server/.env.prod.example";
const MOBILE_ENV = "apps/mobile/.env.example";
const NGINX = "deploy/nginx.conf";

const serviceUnitPath = (brand: Brand): string =>
  `deploy/${brand.identifiers.systemdServiceName}.service`;

/** Replaces `KEY=<anything>` in a dotenv file, leaving comments alone. */
const setEnv = (text: string, key: string, value: string): string => {
  const pattern = new RegExp(`^${key}=.*$`, "m");
  return pattern.test(text) ? text.replace(pattern, `${key}=${value}`) : text;
};

const replaceHosts = (text: string, prev: Brand, next: Brand): string => {
  let out = text;
  const pairs: Array<[string, string]> = [
    [prev.urls.apiHostDev, next.urls.apiHostDev],
    [prev.urls.apiHostProd, next.urls.apiHostProd],
    [prev.urls.website.replace(/^https?:\/\//, ""), next.urls.website.replace(/^https?:\/\//, "")],
  ];
  for (const [from, to] of pairs) {
    if (from.length > 0 && from !== to) {
      out = out.split(from).join(to);
    }
  }
  return out;
};

export const envDeploy: Transform = {
  id: "85-env-deploy",
  title: "Rewrite environment templates and deployment config",
  needs: ["20-rewrite-content"],

  owns(_prev: Brand, next: Brand): string[] {
    return [SERVER_ENV, SERVER_ENV_PROD, MOBILE_ENV, NGINX, serviceUnitPath(next)];
  },

  async plan(ctx: Ctx): Promise<Change[]> {
    const changes: Change[] = [];
    const { prev, next } = ctx;

    const owned = async (
      path: string,
      edit: (source: string) => string
    ): Promise<void> => {
      if (!ctx.files.exists(path)) {
        // The systemd unit is read at its post-move path, which the index -
        // built before the move - does not know about. Fall back to disk.
        const absolute = join(ctx.root, path);
        if (!(await Bun.file(absolute).exists())) {
          ctx.log.debug(`skip ${path}: not present`);
          return;
        }
      }
      const source = await readEither(ctx, path);
      const result = applyTokens(edit(source), ctx.tokens).text;
      if (result !== source) {
        changes.push({ kind: "write", path, contents: result });
      }
    };

    await owned(SERVER_ENV, (source) => {
      let out = replaceHosts(source, prev, next);
      out = setEnv(out, "BETTER_AUTH_URL", `https://${next.urls.apiHostDev}`);
      out = setEnv(out, "APPLE_CLIENT_ID", next.apple.signInServiceId);
      out = setEnv(out, "APPLE_APP_BUNDLE_IDENTIFIER", next.identifiers.bundleId);
      out = setEnv(out, "R2_BUCKET", next.identifiers.r2Bucket);
      return out;
    });

    await owned(SERVER_ENV_PROD, (source) => {
      let out = replaceHosts(source, prev, next);
      out = setEnv(out, "BETTER_AUTH_URL", `https://${next.urls.apiHostProd}`);
      out = setEnv(
        out,
        "TRUSTED_ORIGINS",
        `https://${next.urls.apiHostProd},https://appleid.apple.com`
      );
      out = setEnv(out, "CORS_ALLOWED_ORIGINS", `https://${next.urls.apiHostProd}`);
      out = setEnv(out, "APPLE_CLIENT_ID", next.apple.signInServiceId);
      out = setEnv(out, "APPLE_APP_BUNDLE_IDENTIFIER", next.identifiers.bundleId);
      out = setEnv(out, "R2_BUCKET", next.identifiers.r2BucketProd);
      return out;
    });

    await owned(MOBILE_ENV, (source) => {
      let out = replaceHosts(source, prev, next);
      out = setEnv(out, "DEV_HOST", next.urls.apiHostDev);
      out = setEnv(out, "DEV_AUTH_BASE_URL", `https://${next.urls.apiHostDev}/api/auth`);
      // Google client ids are deliberately left as placeholders: they belong to
      // apps/mobile/tool/sync_google_client_ids.dart, which derives the native
      // config from the developer's own `.env`. Two writers, one file, no.
      return out;
    });

    // Host substitution only - deliberately no `server_name` override. Upstream
    // serves the same host that `.env.example` points `BETTER_AUTH_URL` at, and
    // the file names it in three places (the "copy to" comment, the certbot
    // command, and server_name). Forcing one of them to the prod host while
    // `replaceHosts` maps the other two to the dev host produces a config whose
    // own instructions contradict it.
    await owned(NGINX, (source) => replaceHosts(source, prev, next));

    await owned(serviceUnitPath(next), (source) =>
      source
        .replace(/^Description=.*$/m, `Description=${next.copy.appName} API Server`)
        .split(`/home/ubuntu/${prev.identifiers.deployDirName}/`)
        .join(`/home/ubuntu/${next.identifiers.deployDirName}/`)
    );

    return changes;
  },
};

const readEither = async (ctx: Ctx, path: string): Promise<string> => {
  if (ctx.files.exists(path)) {
    return ctx.files.read(path);
  }
  return Bun.file(join(ctx.root, path)).text();
};

// ---------------------------------------------------------------------------
// 95-lockfiles
// ---------------------------------------------------------------------------

/**
 * Regenerates lockfiles rather than rewriting them.
 *
 * `bun.lock` contains the string `sisteransi`. Textual substitution of the
 * brand token would corrupt it into a package name that does not exist, and
 * `bun install --frozen-lockfile` would then fail in CI with an error that
 * points nowhere near the rebrand. So the lockfiles are on the never-rewrite
 * list and are rebuilt from the manifests instead.
 */
export const lockfiles: Transform = {
  id: "95-lockfiles",
  title: "Regenerate lockfiles from the renamed manifests",
  needs: ["20-rewrite-content"],

  async plan(ctx: Ctx): Promise<Change[]> {
    const changes: Change[] = [
      {
        kind: "exec",
        cmd: ["bun", "install"],
        cwd: ctx.root,
        why: "rebuild bun.lock with the new workspace scope",
      },
    ];

    const recorder = `packages/${ctx.next.identifiers.recorder.dartPackage}`;
    for (const dir of ["apps/mobile", recorder, `${recorder}/example`]) {
      changes.push({
        kind: "exec",
        cmd: ["flutter", "pub", "get"],
        cwd: join(ctx.root, dir),
        why: `rebuild ${dir}/pubspec.lock`,
      });
    }

    return changes;
  },
};

// ---------------------------------------------------------------------------
// 99-finish
// ---------------------------------------------------------------------------

const buildTodoMd = (brand: Brand): string => {
  const b = brand.identifiers.bundleId;
  const teamLine =
    brand.apple.developmentTeam === null
      ? `- [ ] **Apple team id.** \`DEVELOPMENT_TEAM\` was blanked rather than left pointing at the upstream team. Set \`apple.developmentTeam\` in packages/brand/brand.json and re-run, or set it in Xcode.`
      : `- [x] Apple team id set to \`${brand.apple.developmentTeam}\`.`;

  return `# Manual steps

The rebrand rewrote everything it can rewrite safely. What remains needs
credentials or accounts that only you can create. Generated by
\`bun run brand:apply\` - re-run to refresh.

## Signing and store identity

${teamLine}
- [ ] **Apple App ID.** Register \`${b}\` at developer.apple.com.
- [ ] **Sign in with Apple.** Create the Services ID \`${brand.apple.signInServiceId}\`
      and a key, then fill \`APPLE_CLIENT_ID\`, \`APPLE_TEAM_ID\`, \`APPLE_KEY_ID\` and
      \`APPLE_PRIVATE_KEY\` in \`apps/server/.env\`.
- [ ] **Background modes.** \`${brand.apple.backgroundTaskPrefix}.upload.finalize\` is
      already declared in Info.plist, but the Background Modes capability must be
      enabled on the target in Xcode.
- [ ] **Android keystore.** Generate one and write \`apps/mobile/android/key.properties\`.
      Without it the release build throws at \`build.gradle.kts\` - the file is
      gitignored and the engine never touches it.
- [ ] **In-app updates.** Off until you say where your releases live. Once you have
      published, set \`urls.playStoreAppId\` (it must equal
      \`${brand.identifiers.androidApplicationId}\`) and/or \`urls.appStoreId\` in
      packages/brand/brand.json and re-run. If you ship outside the stores, point
      \`urls.updateFeed\` at a Sparkle-style appcast XML instead - it wins over both.
      Leaving all three unset is correct for an unpublished fork: the app then
      never checks for updates and never prompts.

## Services

- [ ] **Google OAuth.** Create web, iOS and Android (SHA-1) clients. Put the ids in
      \`apps/mobile/.env\`, then run \`bun run pub-get:mobile\` to sync them into
      \`strings.xml\` and \`Info.plist\`. The rebrand engine deliberately does not
      touch those two values - \`tool/sync_google_client_ids.dart\` owns them.
- [ ] **Cloudflare R2.** Create \`${brand.identifiers.r2Bucket}\` and
      \`${brand.identifiers.r2BucketProd}\`, then fill the \`R2_*\` variables.
- [ ] **Postgres.** Set \`DATABASE_URL\` and \`DIRECT_URL\`.
- [ ] **DNS.** Point \`${brand.urls.apiHostProd}\` at the server. \`deploy/nginx.conf\`
      and the certbot command in DEPLOY.md are already filled in.
- [ ] **systemd.** \`sudo cp deploy/${brand.identifiers.systemdServiceName}.service /etc/systemd/system/\`.
      The unit assumes the repo lives at \`/home/ubuntu/${brand.identifiers.deployDirName}\`.

## Assets and licences

- [ ] **Artwork.** ${
    brand.assets.iconSource === null
      ? "No icon was supplied, so a placeholder monogram is in use. Drop a square PNG (1024px) or an SVG at `packages/brand/source/icon.png` and re-run."
      : `Icons were generated from \`${brand.assets.iconSource}\`. Check them on a device - small sizes rarely survive automatic downscaling unaltered.`
  }
- [ ] **Fonts.** The app bundles EB Garamond, Handjet, Geist, Geist Mono and
      JetBrains Mono, and will now redistribute them under your name. Confirm
      their licences permit that, or set \`fonts.replaceBundled: true\`.
- [ ] **Attribution.** \`LICENSE\` and \`packages/brand/ATTRIBUTION.md\` retain the upstream
      copyright. Keeping them is a licence condition, not a courtesy.

## Repo setup (pre-existing, not caused by the rebrand)

- [ ] \`cp apps/mobile/.env.example apps/mobile/.env\` and fill it in. \`.env\` is
      gitignored but declared as a Flutter asset, so \`dart analyze\` warns until
      it exists.
- [ ] \`apps/mobile/android/key.properties\` must exist **even for a debug build**.
      \`android/app/build.gradle.kts\` reads it unconditionally
      (\`keystoreProperties["keyAlias"] as String\`), so \`flutter build apk --debug\`
      fails with \`null cannot be cast to non-null type kotlin.String\` on any
      fresh clone until you create it.

## Keeping it branded

- [ ] **CI.** \`.github/workflows/brand.yml\` was written for you (once - it is
      yours to edit now). It runs \`brand:verify\` on every PR, which is what
      catches an upstream merge quietly reintroducing upstream's colours,
      radii, type values or identifiers. If you do not use GitHub Actions, run
      \`bun test packages/brand/ && bun run brand:verify\` from whatever you do
      use. Delete it and the next \`brand:apply\` writes it back.

## Before you commit

- [ ] \`bun run brand:verify --full\`
- [ ] \`cd apps/mobile && flutter build apk --debug\`
- [ ] Review \`git diff\`. The engine never commits.
`;
};

const BRAND_WORKFLOW = ".github/workflows/brand.yml";

/**
 * A CI job for the fork, not for upstream.
 *
 * The failure it catches is specific and cumulative: a fork rebrands, verifies
 * green, then six months later merges upstream and picks up a widget carrying
 * `Color(0xFF18191B)` and the literal string "Stera". Both are things
 * `brand:verify` finds in seconds and nothing else finds at all - they compile,
 * they pass tests, and they are invisible in a diff of four hundred files. The
 * fork only learns when someone opens the app and sees upstream's grey.
 *
 * Written once and then left alone. It is not a generated file: a fork should be
 * free to add its own jobs to it, and hash-tracking a workflow would make that
 * an error. Deleting it means the next `brand:apply` writes it back, which is
 * the price of not having a knob nobody would ever set.
 */
const buildBrandWorkflow = (brand: Brand): string => `# Checks that ${brand.brand.name} stays ${brand.brand.name}.
#
# \`brand:verify\` catches what no compiler will: a widget that reintroduces a
# literal colour or radius, a stale upstream identifier that came back with a
# merge, a Kotlin package that stopped matching its directory. Written by
# \`bun run brand:apply\`; yours to edit from here.
name: brand

on:
  pull_request:
  push:
    branches: [main]

jobs:
  verify:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - uses: oven-sh/setup-bun@v2
      - run: bun install --frozen-lockfile
      - run: bun test packages/brand/
      - run: bun run brand:verify
`;

export const finish: Transform = {
  id: "99-finish",
  title: "Write the manual-steps checklist",
  needs: ["85-env-deploy"],

  async plan(ctx: Ctx): Promise<Change[]> {
    const changes: Change[] = [
      { kind: "write", path: "packages/brand/TODO.md", contents: buildTodoMd(ctx.next) },
    ];

    // Create-if-absent rather than write-always: once it exists it belongs to
    // the fork, and overwriting it every run would silently discard whatever
    // jobs they added next to ours.
    if (!(await Bun.file(join(ctx.root, BRAND_WORKFLOW)).exists())) {
      changes.push({
        kind: "write",
        path: BRAND_WORKFLOW,
        contents: buildBrandWorkflow(ctx.next),
        why: "CI so a later upstream merge cannot silently reintroduce upstream's design values",
      });
    }

    return changes;
  },
};
