import "dart:async";
import "dart:developer" as dev;

import "package:better_auth_flutter/better_auth_flutter.dart" as ba;
import "package:flutter/widgets.dart";
import "package:google_sign_in/google_sign_in.dart";
import "package:provider/provider.dart";
import "package:stera/src/core/common/widgets/video_thumbnail/video_thumbnail.dart";
import "package:stera/src/core/router/app_router.dart";
import "package:stera/src/modules/auth/data/models/app_auth_type.dart";
import "package:stera/src/modules/auth/data/models/user.dart";
import "package:stera/src/modules/auth/data/repo/auth_repo.dart";
import "package:stera/src/modules/auth/data/repo/user_repo.dart";
import "package:stera/src/modules/upload/providers/upload_provider.dart";
import "package:stera/src/services/api/enums/error_type.dart";
import "package:stera/src/services/api/models/api_failure.dart";
import "package:stera/src/services/api/token_service.dart";
import "package:stera/src/services/kv_store/kv_store.dart";

class AuthProvider extends ChangeNotifier {
  User? _user;
  User? get user => _user;
  set user(User? value) {
    _user = value;
    notifyListeners();
  }

  bool get isLoggedIn => user != null;

  bool _isNewUser = false;
  bool get isNewUser => _isNewUser;
  set isNewUser(bool value) {
    _isNewUser = value;
    notifyListeners();
  }

  bool _loading = false;
  bool get loading => _loading;
  set loading(bool value) {
    _loading = value;
    notifyListeners();
  }

  /// Name returned by Sign in with Apple on first auth. Used by onboarding to
  /// skip the name screen — Apple HIG forbids re-asking for info Authentication
  /// Services already provided.
  String? _pendingDisplayName;
  String? get pendingDisplayName => _pendingDisplayName;
  set pendingDisplayName(String? value) {
    _pendingDisplayName = value;
    notifyListeners();
  }

  Future<Failure?> onAuth({
    required AppAuthType type,
    GoogleSignInAuthenticationEvent? event,
    String? phoneNumber,
    String? otp,
  }) async {
    switch (type) {
      case AppAuthType.google:
        if (event == null) {
          return Failure(
            code: ErrorType.validation,
            message: "Google sign-in event is required.",
          );
        }
        loading = true;
        try {
          final (res, err) = await AuthRepo.signInWithGoogle(event);
          if (err != null) return err;
          if (res == null && !ba.BetterAuthFlutter.authState.isAuthenticated) {
            return Failure(
              code: ErrorType.unknown,
              message: "Verification failed. Please try again.",
            );
          }
          if (!ba.BetterAuthFlutter.authState.isAuthenticated) {
            await ba.BetterAuthFlutter.refreshSession();
          }
          return await _hydrateUserAfterSignIn();
        } finally {
          loading = false;
        }
      case AppAuthType.apple:
        loading = true;
        try {
          final (res, appleFullName, err) = await AuthRepo.signInWithApple();
          if (err != null) return err;
          if (res == null && !ba.BetterAuthFlutter.authState.isAuthenticated) {
            return Failure(
              code: ErrorType.unknown,
              message: "Verification failed. Please try again.",
            );
          }
          if (!ba.BetterAuthFlutter.authState.isAuthenticated) {
            await ba.BetterAuthFlutter.refreshSession();
          }
          if (appleFullName != null) _pendingDisplayName = appleFullName;
          return await _hydrateUserAfterSignIn();
        } finally {
          loading = false;
        }
      case AppAuthType.phone:
        return Failure(
          code: ErrorType.validation,
          message: "Phone sign-in is no longer supported.",
        );
    }
  }

  Future<Failure?> _hydrateUserAfterSignIn() async {
    final (fetchedUser, fetchErr) = await UserRepo.upsertProfile();

    if (fetchErr != null || fetchedUser == null) {
      dev.log("AUTH: profile hydrate failed: ${fetchErr?.message}");
      await ba.BetterAuthFlutter.client.signOut();
      await ba.BetterAuthFlutter.clearCookies();
      return fetchErr ??
          Failure(
            code: ErrorType.unknown,
            message: "Could not connect to server. Please try again.",
          );
    }

    user = fetchedUser;
    isNewUser = !(KvStore.get<bool>(KvStoreKeys.onboardingComplete) ?? false);

    final ctx = AppRouter.navigatorKey.currentContext;
    if (ctx != null && ctx.mounted) {
      unawaited(ctx.read<UploadProvider>().picker.recoverOrphanedSessions());
    }

    return null;
  }

  Future<void> forceRefreshUser() async {
    try {
      final cachedUser = await UserRepo.loadCachedUser();
      user ??= cachedUser;

      final (updatedUser, err) = await UserRepo.getMe();
      if (err != null) return;
      user = updatedUser;
    } catch (e) {
      dev.log("AUTH: forceRefreshUser error: $e");
      await logout();
    }
  }

  Future<Failure?> updateCurrentUserProfile({
    String? name,
    String? city,
    String? country,
    int? age,
  }) async {
    if (_user == null) {
      return Failure(code: ErrorType.unknown, message: "User not found");
    }

    final (updatedUser, err) = await UserRepo.updateProfile(
      name: name,
      city: city,
      country: country,
      age: age,
    );

    if (err != null) return err;

    user = updatedUser;
    return null;
  }

  Future<void> logout() async {
    user = null;
    isNewUser = false;
    _pendingDisplayName = null;

    await AuthRepo.logout();
    _clearLocalCaches();
  }

  Future<Failure?> delete() async {
    if (_user == null) {
      return Failure(code: ErrorType.unknown, message: "User not found");
    }

    final err = await AuthRepo.deleteAccount();

    if (err != null) return err;

    user = null;
    isNewUser = false;
    _pendingDisplayName = null;

    _clearLocalCaches();

    return null;
  }

  Future<void> init() async {
    if (!ba.BetterAuthFlutter.authState.isAuthenticated) {
      await ba.BetterAuthFlutter.refreshSession();
    }

    if (!ba.BetterAuthFlutter.authState.isAuthenticated) {
      return;
    }

    final hasProfile = TokenService.hasAppUserId();

    if (!hasProfile) {
      isNewUser = true;
      return;
    }

    user = await UserRepo.loadCachedUser();

    final (fetchedUser, err) = await UserRepo.getMe();
    if (err == null && fetchedUser != null) {
      user = fetchedUser;
    }

    isNewUser = !(KvStore.get<bool>(KvStoreKeys.onboardingComplete) ?? false);
  }

  void _clearLocalCaches() {
    VideoThumbnail.clearCache();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  }

  void reset() {
    user = null;
    isNewUser = false;
    loading = false;
    _pendingDisplayName = null;
  }
}
