# Stera

the flutter capture app. records multimodal spatial data on-device.

writes synchronized rgb, imu, camera pose, depth, point cloud and mesh into a
single [mcap](https://mcap.dev) file per session using ros 2 message schemas,
then uploads sessions with a resumable multipart uploader. the upload half is
optional — see [no-auth mode](#no-auth-mode--no-backend-required).

- **ios** — arkit (`ARWorldTrackingConfiguration`), lidar depth + scene mesh
- **android** — arcore, depth api (no mesh, android hardware has no lidar)

the recorder itself is not in this app. it lives in the
[`stera_recorder`](../../packages/stera_recorder) plugin, which owns the dart
api and the swift/kotlin implementations. only its ui stays here.

## setup

needs the flutter sdk (`^3.9.2`, pinned to 3.44.6 in `.tool-versions`), xcode for
ios and the android sdk for android.

```bash
cp .env.example .env      # then fill in your own values
flutter pub get
```

`.env` is gitignored and loaded at runtime via `flutter_dotenv`.

### no-auth mode — no backend required

if you only want to record and inspect data locally, put a single line in `.env`:

```
NO_AUTH_MODE=true
```

that's a complete configuration. every other key below may be left empty or
removed entirely.

what you get:

| surface | no-auth mode |
| ------- | ------------ |
| login / onboarding | gone — the router has no auth redirect |
| home | `CapturePage`: record button + a grid of on-device recordings |
| mcap preview | unchanged, reached by tapping a recording |
| recorder settings | unchanged, in the header and in settings |
| profile | stripped to local settings — theme, keep-awake, recorder settings, storage |
| uploads | gone — no queue, no drift db, no better auth, no network |

recordings land in `ar_sessions/` on device; on ios they're reachable over usb
through finder or the files app, which is how you get `.mcap` files out without
an upload.

the flag is read by `AppConfig.noAuthMode`. it fails **closed**: an unreadable
`.env` gives you the normal authenticated app, never a silently different one.

two things to know:

- `.env` must still **exist** as a file. it's a declared flutter asset (see
  `pubspec.yaml`), so the bundler fails before any dart runs if it's missing.
- **flipping the flag needs `bun run pub-get:mobile`.** it regenerates
  `ios/Flutter/NoAuth.xcconfig`, which selects the entitlements file (below).

#### testing auth on a free apple account

the authed build can't sign onto a device with a personal team, so google
sign-in is untestable too. `APPLE_SIGN_IN=false` in `.env` drops the capability
and the button, leaving the rest of the auth flow (google, onboarding, upload)
working on a free account:

```
APPLE_SIGN_IN=false
```

then `bun run pub-get:mobile` and rebuild. **development only** — apple requires
sign in with apple from any app offering google sign-in, so never ship a store
build with it off. only a literal `false`/`0` disables it; anything else keeps
the capability.

#### ios signing on a free apple account

`ios/Runner/Runner.entitlements` declares the sign in with apple capability, and
personal development teams can't provision it — so the authed build will not sign
onto a device without a paid account. a no-auth build never calls sign in with
apple, so it signs with the empty `ios/Runner/RunnerNoAuth.entitlements` instead
and installs fine.

`tool/sync_ios_entitlements.dart` translates `NO_AUTH_MODE` into the
`STERA_CODE_SIGN_ENTITLEMENTS` build setting. it defaults to the full
entitlements, so a fresh clone — or a missing generated xcconfig — always keeps
sign in with apple.

### full mode — with auth and upload

leave `NO_AUTH_MODE` unset or `false`, and you'll need:

- **host / api version / auth base url** for the backend. that's
  [`apps/server`](../server) in this repo, see the root
  [quick start](../../README.md#quick-start) to run it locally
- **google sign-in oauth client ids**. `dart run tool/sync_google_client_ids.dart`
  pushes them into `android/app/src/main/res/values/strings.xml`
  (`default_web_client_id`) and `ios/Runner/Info.plist` as a reversed-client-id
  url scheme. also runs via `bun run pub-get:mobile`

auth is [better auth](https://better-auth.com) through `better_auth_flutter`,
with google sign-in and sign in with apple. the server side is
[`packages/auth`](../../packages/auth).

## run

```bash
flutter run
```

ios needs a physical device. arkit does not run in the simulator.

## build

```bash
flutter build ios --no-codesign
flutter build apk
```

## test & lint

```bash
flutter test
flutter analyze
```

## pulling recorded sessions off a device

```bash
scripts/pull_arcore_dataset.sh          # latest android session
scripts/pull_arcore_dataset.sh --all
scripts/pull_ios_dataset.sh             # ios
```

both accept `APP_ID` / `BUNDLE_ID` and `LOCAL_ROOT` as environment overrides.
`scripts/frame_drop_analysis.py` reports per-channel timing, jitter and gaps for
a recorded `.mcap`.

## conventions

native (swift/kotlin) code follows a strict contract / impl / method-channel
triad. no design value is a literal in a widget. see [`CLAUDE.md`](CLAUDE.md).
