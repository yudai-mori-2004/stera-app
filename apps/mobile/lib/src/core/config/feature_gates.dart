import "package:flutter/foundation.dart";
import "package:flutter_dotenv/flutter_dotenv.dart";
import "package:stera/src/core/config/app_config.dart";

/// Central switchboard for features that are hidden on the prod server.
///
/// This gates **UI visibility only** — the underlying services, native code,
/// and persisted settings are untouched. A feature hidden here can still be
/// enabled by a value already in KvStore; nothing clamps it. Flip a row to
/// `prod: true` to ship the feature.
enum GatedFeature { depth, arkitImu }

/// Per-environment visibility. `prod: false` is the kill switch.
class FeatureGate {
  final bool prod;
  final bool dev;

  const FeatureGate({required this.prod, required this.dev});
}

/// The one table to edit. Every [GatedFeature] needs a row.
const Map<GatedFeature, FeatureGate> featureGates = {
  GatedFeature.depth: FeatureGate(prod: false, dev: true),
  GatedFeature.arkitImu: FeatureGate(prod: false, dev: true),
};

class FeatureGates {
  /// Overrides environment resolution in tests. `flutter test` runs without a
  /// loaded `.env`, which otherwise resolves to prod and makes the dev path
  /// unreachable.
  @visibleForTesting
  static bool? debugOverrideIsProd;

  static bool isVisible(GatedFeature feature) {
    final gate = featureGates[feature];
    if (gate == null) return false;
    return _isProd ? gate.prod : gate.dev;
  }

  static bool isHidden(GatedFeature feature) => !isVisible(feature);

  /// Read from `build()` methods, so it must never throw. `AppConfig.config`
  /// casts `.env` values unconditionally and blows up if read before
  /// `dotenv.load` completes — an unknown environment is treated as prod,
  /// because a gate should fail towards hiding, never towards revealing.
  static bool get _isProd {
    if (debugOverrideIsProd != null) return debugOverrideIsProd!;
    if (!dotenv.isInitialized) return true;
    return AppConfig.config.environment == Environment.prod;
  }
}
