import "dart:convert";
import "dart:developer" as dev;
import "dart:math";

import "package:better_auth_flutter/better_auth_flutter.dart" as ba;
import "package:crypto/crypto.dart";
import "package:google_sign_in/google_sign_in.dart";
import "package:sign_in_with_apple/sign_in_with_apple.dart";
import "package:stera/src/core/config/app_config.dart";
import "package:stera/src/core/config/constants/app_endpoints.dart";
import "package:stera/src/modules/auth/helpers/auth_helper.dart";
import "package:stera/src/services/api/api.dart";
import "package:stera/src/services/api/enums/error_type.dart";
import "package:stera/src/services/api/enums/method_type.dart";
import "package:stera/src/services/api/models/api_failure.dart";
import "package:stera/src/services/api/network_utils.dart";
import "package:stera/src/services/db/upload_db.dart";
import "package:stera/src/services/kv_store/kv_store.dart";
import "package:stera/src/services/secure_storage/secure_storage.dart";

class AuthRepo {
  static final GoogleSignIn googleSignIn = GoogleSignIn.instance;

  /// Nonce handed to Google, stored between authenticate() and
  /// signInWithGoogle(). Google echoes it verbatim into the id token's `nonce`
  /// claim and Better Auth compares the two literally, so the same string must
  /// go to both — unlike Apple, there is no hash step here.
  static String? _googleNonce;

  /// Guard against concurrent Google auth flows. A second `authenticate()`
  /// while the first ASWebAuthenticationSession is still alive causes
  /// AppAuth to deliver the OAuth callback to a finalized session and crash
  /// with an `OIDExternalUserAgentSession` NSException.
  static bool _googleAuthInFlight = false;

  static bool get isGoogleAuthInFlight => _googleAuthInFlight;

  static void markGoogleAuthCompleted() {
    _googleAuthInFlight = false;
  }

  static String _generateNonce([int length = 32]) {
    const charset =
        "0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._";
    final random = Random.secure();
    return List.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }

  static Future<void> init({String? nonce}) async {
    try {
      await googleSignIn.initialize(
        serverClientId: AppConfig.config.googleWebClientId,
        clientId: AppConfig.config.googleIosClientId,
        nonce: nonce,
      );
    } catch (e) {
      dev.log("Google Sign-In initialization failed: $e");
    }
  }

  static Failure _mapBetterError(ba.BetterError e) {
    if (e.isNetworkError) return Failure.networkError();
    if (e.isUnauthorized) return Failure.unAuthorized();
    if (e.code == ba.BetterErrorCodes.rateLimited || e.statusCode == 429) {
      return Failure.tooManyRequests();
    }
    if (e.code == ba.BetterErrorCodes.cancelled) {
      return Failure(code: ErrorType.cancelled, message: e.message);
    }
    if (e.statusCode != null && e.statusCode! >= 500) {
      return Failure.serviceUnavailable();
    }
    return Failure(code: ErrorType.unknown, message: e.message);
  }

  static Future<(ba.SignInSocialResponse?, Failure?)> signInWithGoogle(
    GoogleSignInAuthenticationEvent event,
  ) async {
    _googleAuthInFlight = false;
    try {
      final GoogleSignInAccount? googleUser = switch (event) {
        GoogleSignInAuthenticationEventSignIn(:final user) => user,
        GoogleSignInAuthenticationEventSignOut() => null,
      };

      if (googleUser == null) {
        return (
          null,
          Failure(
            code: ErrorType.cancelled,
            message: "Google sign-in was cancelled.",
          ),
        );
      }

      final idToken = googleUser.authentication.idToken;
      if (idToken == null) {
        return (
          null,
          Failure(
            code: ErrorType.invalidToken,
            message: "Google did not return an ID token.",
          ),
        );
      }

      final nonce = _googleNonce;
      _googleNonce = null;

      final result = await retryOnNetworkError(
        () => ba.BetterAuthFlutter.client.signInSocial(
          body: ba.SignInSocialBody.of(
            provider: ba.SocialProvider.google,
            idToken: ba.SocialIdTokenBody(token: idToken, nonce: nonce),
          ),
        ),
      );

      return switch (result) {
        ba.Success(:final data) => (data, null),
        ba.Failure(:final error) => (null, _mapBetterError(error)),
      };
    } catch (e) {
      dev.log("Error signing in with Google: $e");
      if (isUpstreamOutage(e)) return (null, Failure.serviceUnavailable());
      if (isNetworkError(e)) return (null, Failure.networkError());
      return (null, Failure.fromException(e));
    }
  }

  static Future<void> authenticateWithGoogle() async {
    if (_googleAuthInFlight) return;
    _googleAuthInFlight = true;
    try {
      final nonce = _generateNonce();
      _googleNonce = nonce;
      await init(nonce: nonce);
      await googleSignIn.authenticate();
    } catch (e) {
      _googleNonce = null;
      _googleAuthInFlight = false;
      dev.log("Google Sign-In authenticate failed: $e");
    }
  }

  static Future<(ba.SignInSocialResponse?, String?, Failure?)>
  signInWithApple() async {
    try {
      // Apple's convention: hand Apple the hash, hand the server the
      // pre-image. Better Auth's apple provider hashes before comparing.
      final rawNonce = _generateNonce();
      final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );

      final idToken = credential.identityToken;
      if (idToken == null) {
        return (
          null,
          null,
          Failure(
            code: ErrorType.invalidToken,
            message: "Apple did not return an ID token.",
          ),
        );
      }

      final result = await retryOnNetworkError(
        () => ba.BetterAuthFlutter.client.signInSocial(
          body: ba.SignInSocialBody.of(
            provider: ba.SocialProvider.apple,
            idToken: ba.SocialIdTokenBody(token: idToken, nonce: rawNonce),
          ),
        ),
      );

      final appleFullName = [credential.givenName, credential.familyName]
          .whereType<String>()
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .join(" ");

      return switch (result) {
        ba.Success(:final data) => (
          data,
          appleFullName.isEmpty ? null : appleFullName,
          null,
        ),
        ba.Failure(:final error) => (null, null, _mapBetterError(error)),
      };
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        return (
          null,
          null,
          Failure(
            code: ErrorType.cancelled,
            message: "Apple sign-in was cancelled.",
          ),
        );
      }
      return (null, null, Failure.fromException(e));
    } catch (e) {
      dev.log("Error signing in with Apple: $e");
      if (isUpstreamOutage(e)) {
        return (null, null, Failure.serviceUnavailable());
      }
      if (isNetworkError(e)) return (null, null, Failure.networkError());
      return (null, null, Failure.fromException(e));
    }
  }

  static Future<void> logout() async {
    try {
      await ba.BetterAuthFlutter.client.signOut();
    } catch (e) {
      dev.log("Error signing out from Better Auth: $e");
    }
    try {
      await ba.BetterAuthFlutter.clearCookies();
    } catch (e) {
      dev.log("Error clearing Better Auth cookies: $e");
    }
    try {
      await googleSignIn.signOut();
    } catch (e) {
      dev.log("Error signing out from Google: $e");
    }
    await AuthHelper.reset();
    await KvStore.clear();
    await SecureStorage.clear();
    await UploadDb.instance.clear();
  }

  static Future<Failure?> deleteAccount() async {
    try {
      final (_, err) = await Api.sendRequest(
        AppEndpoints.deleteAccount,
        method: MethodType.delete,
      );

      if (err != null) return err;

      await logout();

      return null;
    } catch (e) {
      return Failure.fromException(e);
    }
  }
}
