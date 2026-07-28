import "dart:developer";

import "package:better_auth_flutter/better_auth_flutter.dart" as ba;
import "package:provider/provider.dart";
import "package:stera/src/core/common/widgets/app_toast.dart";
import "package:stera/src/core/config/app_config.dart";
import "package:stera/src/core/router/app_router.dart";
import "package:stera/src/modules/auth/providers/auth_provider.dart";
import "package:stera/src/services/api/models/api_failure.dart";
import "package:stera/src/services/kv_store/kv_store.dart";

/// Cookie bridge between [ba.BetterAuthFlutter]'s jar and the hand-rolled
/// [Api] client. Session cookies are the auth credential — there is no bearer
/// token to refresh.
class TokenService {
  /// Headers to merge onto an outgoing API request (`Cookie: …`), or empty
  /// when there is no session.
  static Future<(Map<String, String>?, Failure?)> getAuthHeaders({
    required Uri uri,
  }) async {
    try {
      final headers = await ba.BetterAuthFlutter.getAuthHeaders(uri: uri);
      if (headers.isEmpty) {
        return (null, Failure.unAuthorized());
      }
      return (headers, null);
    } catch (e) {
      log("TokenService: getAuthHeaders failed: $e");
      return (null, Failure.unAuthorized());
    }
  }

  /// Persist any `Set-Cookie` headers the API returned so rotated session
  /// cookies stay in Better Auth's jar.
  static Future<void> saveCookiesFromResponse(
    Uri uri,
    List<String> setCookieHeaders,
  ) async {
    if (setCookieHeaders.isEmpty) return;
    try {
      await ba.BetterAuthFlutter.saveCookiesFromResponse(
        uri,
        setCookieHeaders,
      );
    } catch (e) {
      log("TokenService: saveCookiesFromResponse failed: $e");
    }
  }

  static bool isLoggedIn() {
    return ba.BetterAuthFlutter.authState.isAuthenticated;
  }

  static Future<void> handleSessionExpired() async {
    // No session to expire, and `AuthProvider` isn't registered — the
    // `ctx.read<AuthProvider>()` below would throw `ProviderNotFoundException`.
    if (AppConfig.noAuthMode) return;

    if (AppRouter.isOnPublicRoute()) {
      log("TokenService: On public route, skipping session expiry handling");
      return;
    }

    log("TokenService: Session expired, logging out user...");
    final ctx = AppRouter.navigatorKey.currentContext;
    if (ctx != null) {
      final ap = ctx.read<AuthProvider>();
      await ap.logout();
    }
    AppToast.show(title: "Session expired. Please login again to continue.");
  }

  /// Locally stored Better Auth user id (set after first successful hydrate).
  static String? getAppUserId() {
    return KvStore.get<String>(KvStoreKeys.profileId);
  }

  static bool hasAppUserId() {
    return KvStore.get<String>(KvStoreKeys.profileId) != null;
  }
}
