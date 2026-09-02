<h1 align="center">
  <img alt="RootLens" src="assets/logo_light.png" height="32" align="center" style="vertical-align: middle;">
  &nbsp;RootLens App
</h1>

<p align="center">by <a href="https://rootlens.io">RootLens</a> · powered by <a href="#credits">stera-app</a></p>

<p align="center">
  <a href="https://pub.dev/packages/stera_recorder"><img alt="pub.dev" src="https://img.shields.io/pub/v/stera_recorder?color=4c8bf5&logo=dart"></a>
  <a href="https://rootlens.io"><img alt="Platforms" src="https://img.shields.io/badge/platform-iOS%20%7C%20Android-4c8bf5"></a>
  <a href="https://flutter.dev"><img alt="Flutter" src="https://img.shields.io/badge/Flutter-3.44.6-02569B?logo=flutter&logoColor=white"></a>
  <a href="https://bun.sh"><img alt="Bun" src="https://img.shields.io/badge/Bun-1.3.14-000000?logo=bun&logoColor=white"></a>
  <a href="https://www.apache.org/licenses/LICENSE-2.0"><img alt="License" src="https://img.shields.io/badge/license-Apache--2.0-blue"></a>
</p>

<p align="center">
  <a href="https://rootlens.io">Website</a> ·
  <a href="https://fpvlabs.ai/stera/docs">Upstream documentation</a> ·
  <a href="https://github.com/fpv-labs/stera-sdk">Processing SDK</a>
</p>

`stera-app` is an open-source, mobile-native stack for collecting high-fidelity,
long-horizon egocentric and spatial data on commodity hardware. It includes the
mobile app, native recording engine, upload backend, standalone recorder
example, and tooling needed to release your own capture app.

This repository is the RootLens distribution of that stack. Product identity,
application IDs, legal links, and visual assets are RootLens-specific; the
`stera_recorder` package and the MCAP schema/writer identifiers stay compatible
with upstream.

Point a phone at what you are doing and RootLens records RGB, depth, camera pose,
IMU, point clouds, and meshes into one [MCAP](https://mcap.dev) file per
session, then uploads it for processing. Capture runs through ARKit on iOS and
ARCore on Android. No custom rig, mount, or capture PC is required.

<p align="center"><strong>Capture → Process → Evaluate → Export</strong></p>

RootLens App produces self-contained recordings that can be used with your own
data pipeline or processed with
[stera-sdk](https://github.com/fpv-labs/stera-sdk). The SDK can turn raw
recordings into world-anchored 6-DoF trajectories, 21-joint MANO hand poses,
hierarchical action language, scene geometry, and clean training episodes for
embodied AI, VLAs, and world models.

RootLens is designed for data operations teams launching collection programs,
academic labs building experiment-specific datasets, and robotics companies
scaling capture across contributors, tasks, and environments.

## Features

- **Multimodal capture:** records RGB, depth, pose, IMU, point clouds, and
  meshes against one timeline in a portable MCAP session.
- **Native spatial tracking:** ARKit on iOS and ARCore on Android through a
  shared Flutter recorder plugin.
- **Hands-free operation:** voice commands and audio cues let contributors
  start and stop while their hands remain on the task.
- **Resilient uploads:** local session previews and resumable uploads to
  Cloudflare R2.
- **Long-session safeguards:** recording health, storage, battery, and thermal
  monitoring help surface failures while a session can still be repeated.
- **Self-hosted backend:** Bun, Hono, PostgreSQL, Better Auth, and presigned
  object-storage uploads.
- **Built-in white-labeling:** one brand file drives product identity, themes,
  icons, native identifiers, and deployment configuration.

## Capture output

RootLens aligns multiple asynchronous sensor streams onto one shared timeline:

- RGB video
- 6-DoF camera pose
- IMU, including accelerometer and gyroscope measurements
- depth and point clouds where supported by the device
- scene mesh on LiDAR-equipped iOS devices

Each completed capture is self-contained:

```text
session_<timestamp>[_<device>]/
├── session_data_<timestamp>[_<device>].mcap
├── metadata.json
└── thumbnail.jpg
```

Recordings use ROS 2 message schemas inside MCAP. They can be inspected and
replayed directly with tools such as [Foxglove](https://foxglove.dev), or opened
for downstream processing with [stera-sdk](https://github.com/fpv-labs/stera-sdk).

The contributor loop stays deliberately small: start a recording, perform the
activity naturally, stop and review the session, then upload it or move it to a
workstation. Multipart uploads resume after an interruption instead of sending
the entire capture again.

## Capture settings

The app exposes the controls that materially affect fidelity, file size,
battery use, and thermal load:

| Setting | Options | Default |
| --- | --- | --- |
| RGB resolution | 720p, 1080p, or 4K on supported iOS devices | 1080p |
| RGB, depth, and point-cloud sampling | 15, 30, or 60 Hz at 720p/1080p; 5, 10, 15, or 30 Hz at 4K | 30 Hz |
| IMU sampling | 50 or 100 Hz | 100 Hz |
| ARKit session frame rate | 30 or 60 fps, subject to resolution and device support | 30 fps |
| Focus and exposure | Automatic or locked | Automatic |
| Voice commands and audio cues | On or off | On |

Higher settings are not automatically better. More pixels and faster sampling
increase storage pressure, power draw, and heat; for long-horizon collection, a
lower-fidelity session that completes is often more valuable than a
maximum-fidelity session cut short by thermal throttling. Treat the defaults as
a practical starting point and tune them for the task and device fleet.

## Quick start

There are two ways to run RootLens. The recorder can run standalone with no
backend at all, or you can bring up the full stack with authentication and
uploads.

### Recorder only, without a backend

If you only need to capture and inspect data locally, you can skip PostgreSQL,
OAuth credentials, and object storage entirely. One line of configuration is a
complete setup:

```bash
git clone https://github.com/yudai-mori-2004/stera-app.git
cd stera-app
bun install

printf 'NO_AUTH_MODE=true\n' > apps/mobile/.env

bun run pub-get:mobile
cd apps/mobile
flutter run
```

The app boots straight into the capture screen: record sessions, browse them,
open any session in the MCAP preview, and change recorder settings. There is no
login, no upload queue, and no network activity.

Recordings are written to `ar_sessions/` on the device. On iOS they are
reachable over USB through Finder or the Files app, which is how you move
`.mcap` files onto a machine running
[stera-sdk](https://github.com/fpv-labs/stera-sdk).

Two constraints are worth knowing. The `.env` file must still exist, because it
is a declared Flutter asset and the bundler fails before any Dart code runs if
the file is missing. And changing the flag requires re-running
`bun run pub-get:mobile`, which regenerates the iOS build configuration.

### Prerequisites

The full stack additionally requires:

- [Bun](https://bun.sh) 1.3.14
- [Flutter](https://flutter.dev) 3.44.6 stable
- PostgreSQL
- Xcode for iOS development or the Android SDK for Android development

### Run the API

```bash
git clone https://github.com/yudai-mori-2004/stera-app.git
cd stera-app
bun install

cp apps/server/.env.example apps/server/.env
cp apps/mobile/.env.example apps/mobile/.env
# Fill in the database, storage, OAuth, and host configuration.

bun run db:migrate
bun run dev:server
```

### Run the mobile app

In a second terminal:

```bash
bun run pub-get:mobile
cd apps/mobile
flutter run
```

Use a physical device. ARKit does not run in the iOS Simulator, and ARCore does
not run in the Android emulator. Depth and mesh availability depend on device
hardware support.

> **iOS with a free Apple account:** the authenticated build declares the Sign
> in with Apple capability, which personal development teams cannot provision,
> so it will not sign onto a device without a paid account. A `NO_AUTH_MODE`
> build signs with empty entitlements instead and installs normally. The
> selection is driven from `.env` by `bun run pub-get:mobile`, so re-run it
> after changing the flag.

## Repository layout

| Path | Purpose |
| --- | --- |
| `apps/mobile` | Flutter capture app: recording UI, MCAP previews, and optional authentication and resumable uploads (see `NO_AUTH_MODE`) |
| `apps/server` | Bun + Hono API: Better Auth, asset management, and R2 presigned uploads |
| `packages/stera_recorder` | Native capture plugin implemented with Swift/ARKit and Kotlin/ARCore |
| `packages/brand` | White-label engine that rebrands the repository from one JSON file |
| `packages/auth` | Better Auth factory |
| `packages/db` | Drizzle schema and PostgreSQL migrations |
| `packages/env` | Validated server environment configuration |
| `packages/types` | Shared Zod request and response schemas |
| `packages/config` | Shared TypeScript configuration |
| `deploy` | nginx and systemd configuration for EC2 deployment |

See [DEPLOY.md](./DEPLOY.md) for the self-hosted API deployment guide.
RootLens's upstream-sync and compatibility policy is documented in
[UPSTREAM.md](./UPSTREAM.md).

## Use the recorder on its own

`packages/stera_recorder` is the sensor layer behind the product UI. It exposes
a small Dart API while its native Swift/ARKit and Kotlin/ARCore implementations
handle multi-rate scheduling, sensor alignment, pose and tracking state, IMU
batching, depth and point-cloud generation, non-blocking MCAP writes, and
runtime safeguards.

The recorder is published as
[`stera_recorder`](https://pub.dev/packages/stera_recorder) on pub.dev. Add it
to any Flutter app with:

```bash
flutter pub add stera_recorder
```

You can embed it without adopting the RootLens UI or backend. To work from this
repository instead, run the included one-screen example:

```bash
cd packages/stera_recorder/example
flutter run
```

See the [recorder package guide](./packages/stera_recorder/README.md) for
platform requirements, installation, permissions, and API usage.

## What you can build

- **Research-specific recorders** with task prompts, event markers, new sensor
  channels, or study metadata.
- **Distributed collection programs** connected to your own authentication,
  storage, and review workflow.
- **On-device quality control** for tracking, sensor, battery, thermal, and
  storage failures.
- **New capture interfaces** for hands-free, mounted, assisted, or headless
  workflows.
- **End-to-end data systems** that connect capture to `stera-sdk` processing,
  evaluation, and export.

The system boundary is explicit: the app owns the contributor experience, the
recorder owns synchronized sensor capture, and MCAP is the contract between
capture and everything downstream. Each layer can evolve without requiring the
others to be rewritten.

## White-labeling

Fork RootLens and make it your own product by editing
`packages/brand/brand.json`. That file controls the name, icons, colors, type
scale, corner radii, spacing, bundle IDs, package names, and deployment
configuration across the repository.

For a guided workflow in Claude Code, run `/whitelabel`. It collects your
brand choices, writes the brand configuration, renders a preview, and walks
through the manual platform steps after applying it. You can also give it a
marketing site to use as a reference for colors, typography, and radii.

Preview the result before applying it:

```bash
bun run brand:preview   # Render a preview without changing the app
bun run brand:check     # Print the planned changes
bun run brand:apply     # Apply the brand across the repository
bun run brand:verify    # Run structural brand checks
```

The preview includes platform icon masks, key app screens in light and dark
modes, color tokens with WCAG grades, type specimens, and the radius scale.
`brand:verify` also catches hardcoded colors or radii that bypass the generated
theme.

Read the [white-labeling guide](./packages/brand/README.md) for the complete
workflow.

## Research and data

- [**MobileEgo Anywhere: Open Infrastructure for Long-Horizon Egocentric Data
  on Commodity Hardware**](https://arxiv.org/abs/2605.05945): the research
  behind collecting hour-plus egocentric trajectories on mobile devices.
- [**stera-10m**](https://huggingface.co/datasets/fpvlabs/stera-10m): 200 hours,
  584 sessions, and approximately 10 million RGB frames captured with this
  infrastructure.

## Documentation

- 📚 [Documentation](https://fpvlabs.ai/stera/docs)
- 📱 [Capture documentation](https://fpvlabs.ai/stera/docs/capture)
- 🚀 [Quickstart](https://fpvlabs.ai/stera/docs/process/get-started/quickstart)
- ⚙️ [API reference](https://fpvlabs.ai/stera/docs/process/api)
- 🛠️ [Installation](https://fpvlabs.ai/stera/docs/process/get-started/installation)

## Contributing

Read [CONTRIBUTING.md](./CONTRIBUTING.md) before opening a pull request. At a
minimum, changes must pass:

```bash
bun run check
bun run check-types
bun run brand:verify

cd apps/mobile
flutter analyze
flutter test
```

Never commit secrets. Real `.env` files, Apple `.p8` keys, keystores, and
Firebase or Google service files are ignored; only placeholder examples belong
in the repository.

To report a security issue in this fork, email [contact@rootlens.io](mailto:contact@rootlens.io)
instead of opening a public issue.

## License

Apache 2.0. Upstream copyright and RootLens modifications are documented in
[LICENSE](./LICENSE), [NOTICE](./NOTICE), and the credits below.

Bundled fonts are licensed under SIL OFL 1.1. The linked upstream dataset is licensed
under CC BY-NC 4.0; see [NOTICE](./NOTICE) for details.

<!-- brand:attribution:start -->

## Credits

Powered by Stera — built on [Stera](https://github.com/fpv-labs/stera-app) by FPV Labs.

The upstream work is described in [MobileEgo Anywhere](https://arxiv.org/abs/2605.05945), and the
[Stera-10M](https://huggingface.co/datasets/fpvlabs/stera-10m) dataset is released separately under CC BY-NC 4.0.

<!-- brand:attribution:end -->
