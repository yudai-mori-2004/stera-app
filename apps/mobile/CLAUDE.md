# Coding Practices

## Project layout

- `lib/src/core/` — config, router, theme, shared widgets/utils
- `lib/src/modules/<feature>/` — feature code (`data/`, `providers/`, `ui/`, `view_models/`)
- `lib/src/services/<service>/` — cross-cutting services (api, db, upload, ar_recorder, …)
- `ios/Runner/<module>/` — Swift native modules
- `android/app/src/main/kotlin/open/fpvlabs/stera/<module>/` — Kotlin native modules

The AR recorder is **not** in this app: it lives in the `stera_recorder` plugin
(`packages/stera_recorder`), which owns its Dart API, its Swift/Kotlin code, its
channel constants and its persisted setting keys. Only its UI
(`lib/src/modules/ar_recorder/ui/`) stays here, built on the app's design system.

## Two build modes

`NO_AUTH_MODE=true` in `.env` produces an auth-free, upload-free build: record,
MCAP preview and recorder settings only. Read it via `AppConfig.noAuthMode`,
which never throws and fails **closed** — an unreadable `.env` yields the normal
authenticated app.

What differs, and what it means for a change you're making:

- **A smaller provider set.** `main.dart` registers only `ArRecorderProvider` and
  `RecordingsProvider` (`_noAuthProviders`). A `context.read<AuthProvider>()` /
  `<UploadProvider>` / `<UploadedVideosProvider>` on a widget reachable from
  `CapturePage`, `ProfilePage` or the MCAP preview throws
  `ProviderNotFoundException` in that build and nowhere else.
- **`/root` builds `CapturePage`, not `NavigationPage`.** Same route path, so
  existing navigation keeps working; there is no bottom nav and no upload tab.
- **The router has no redirect** and `StartupViewModel` skips Better Auth,
  `AuthRepo`, `ConnectivityService` and every upload step.
- **The network is off at the choke point.** `Api.sendRequest` returns a failure
  before building a request, so nothing reaches the wire.

If you touch the auth, upload or startup path, exercise both modes. The
`CapturePage` widget test pins the provider contract — keep it passing rather
than widening the no-auth provider list to make a new read work.

iOS signing: `Runner.entitlements` (Sign in with Apple) can't be provisioned by a
free Apple team, so a no-auth build signs with the empty
`RunnerNoAuth.entitlements`. `tool/sync_ios_entitlements.dart` picks between them
from `.env` at `pub-get` time — **flipping the flag requires re-running
`bun run pub-get:mobile`** before the next iOS build.

## Native code (iOS Swift + Android Kotlin) — required

All native functionality MUST follow the **module triad**:

1. **Contract** — `Foo.swift` protocol / `Foo.kt` interface. Platform-idiomatic API plus a delegate/callback for async results. **No Flutter imports.** The iOS and Android contracts stay semantically identical.
2. **Implementation** — `FooImpl`. All platform API work (ARKit, PHPicker, MediaStore, …). Reports back via the delegate. **Never touches `FlutterMethodChannel` / `FlutterResult`.**
3. **MethodChannelHandler** — the **only** file that imports Flutter. Owns the channel name as a private constant; switches on `call.method` with a default of `FlutterMethodNotImplemented`; guards re-entrancy (a pending result in flight fails with `ALREADY_ACTIVE` — never drop or overwrite one); clears `pendingResult` on every path; uses `[weak self]` on iOS.

New native features ship the same three files on BOTH platforms (parity rule), and Impls crossing ~800 lines get decomposed into interface+impl collaborators.

**Registration points:**

- iOS — handlers are instantiated in `SceneDelegate.swift` and held as properties so they live as long as the scene. App-level callbacks (background `URLSession` wakeups) stay in `AppDelegate.swift`.
- Android — handlers are instantiated in `MainActivity.configureFlutterEngine`, keeping references for any handler that needs activity results.

**Dart side:** each native module has one service under `lib/src/services/` owning a channel-name constant that must exactly match the native constant. Methods return `(value, Failure?)`; `PlatformException.code` maps to `ErrorType`. Error codes are SCREAMING_SNAKE and part of the contract.

Channel and method names are centralised in `lib/src/core/enums/platform_channels.dart` and `lib/src/core/enums/platform_channel_methods.dart` — add them there, don't inline raw strings. Plugin-owned channels are the exception: `stera_recorder` keeps its own in `lib/src/channels/ar_recorder_channels.dart`.

**Registration in plugins:** a plugin registers through `GeneratedPluginRegistrant` — `FlutterPlugin.register(with:)` on iOS, `FlutterPlugin` + `ActivityAware` on Android — instead of `SceneDelegate` / `MainActivity`.

## House rules

- No commented-out code in commits — delete it; git is the archive.
- Empty directories don't survive review.
- Persisted strings (KvStore keys, MCAP topic/schema names, method-channel names) are immutable once shipped; rename the Dart identifier, not the stored value.
- `flutter analyze` must be clean before a change is considered done.
- **No design value is a literal in a widget.** Colours come from
  `context.colors` (`context.darkColors` for chrome over the camera or a video),
  corner radii from `AppRadii`, font sizes and weights from `context.textTheme`
  or `AppType`, gaps and padding from `AppSpacing` — never `Color(0xFF…)`,
  `Colors.white`, `Colors.black`, `BorderRadius.circular(12)`, `fontSize: 14`,
  `FontWeight.w600`, `EdgeInsets.all(16)` or `SizedBox(height: 12)`. All four
  resolve from `packages/brand/brand.json`, so a literal is a widget that
  silently opts out of the theme every other widget follows. `bun run
  brand:verify` fails the build on one. `Colors.transparent` is the only
  exception.
- Prefer a **named style** on `context.textTheme` to assembling one: it pairs a
  size with a weight, a line height and a colour that were designed together.
  `AppType` is for the two cases a named style cannot serve — a `copyWith` that
  changes only the weight, and chrome over video where the size is doing layout
  work.
- A `CustomPainter` has no `BuildContext`: take the colours as constructor
  fields (see `_Scene3DPainter`) and compare them in `shouldRepaint`.
