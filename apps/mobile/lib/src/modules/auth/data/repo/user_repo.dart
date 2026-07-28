import "dart:developer";

import "package:better_auth_flutter/better_auth_flutter.dart" as ba;
import "package:stera/src/core/config/constants/app_endpoints.dart";
import "package:stera/src/modules/auth/data/models/user.dart";
import "package:stera/src/services/api/api.dart";
import "package:stera/src/services/api/enums/error_type.dart";
import "package:stera/src/services/api/enums/method_type.dart";
import "package:stera/src/services/api/models/api_failure.dart";
import "package:stera/src/services/api/network_utils.dart";
import "package:stera/src/services/kv_store/kv_store.dart";

class UserRepo {
  static User _fromBetterAuthUser(ba.User user, {bool? isContributor}) {
    return User(
      id: user.id,
      email: user.email,
      phone: user.phoneNumber,
      name: user.name.isEmpty ? null : user.name,
      avatarUrl: user.image,
      platformRole: user.role,
      city: null,
      country: KvStore.get<String>(KvStoreKeys.country),
      age: null,
      isContributor:
          isContributor ??
          (KvStore.get<bool>(KvStoreKeys.onboardingComplete) ?? false),
      createdAt: user.createdAt,
    );
  }

  /// Hydrates app user state from the Better Auth session after sign-in.
  ///
  /// Optionally reconciles against `GET /users/me`. Onboarding completion is a
  /// local flag — there is no contributor service in v1.
  static Future<(User?, Failure?)> upsertProfile() async {
    try {
      var baUser = ba.BetterAuthFlutter.authState.user;
      if (baUser == null) {
        await ba.BetterAuthFlutter.refreshSession();
        baUser = ba.BetterAuthFlutter.authState.user;
      }
      if (baUser == null) {
        return (null, Failure.unAuthorized());
      }

      final user = _fromBetterAuthUser(baUser);
      await KvStore.set(KvStoreKeys.profileId, user.id);
      await KvStore.set(KvStoreKeys.user, user.toJson());
      return (user, null);
    } catch (e) {
      if (isNetworkError(e)) return (null, Failure.networkError());
      return (null, Failure.fromException(e));
    }
  }

  /// Completes onboarding: updates the Better Auth display name and stores
  /// country locally. Marks the user as onboarded (replaces contributor
  /// registration from the old fpv-auth flow).
  static Future<Failure?> registerContributor({
    required String name,
    required String country,
  }) async {
    try {
      final result = await ba.BetterAuthFlutter.client.updateUser(name: name);
        if (result case ba.Failure(:final error)) {
        return Failure(code: ErrorType.unknown, message: error.message);
      }

      await KvStore.set(KvStoreKeys.country, country);
      await KvStore.set(KvStoreKeys.onboardingComplete, true);

      return null;
    } catch (e) {
      if (isNetworkError(e)) return Failure.networkError();
      return Failure.fromException(e);
    }
  }

  static Future<(User?, Failure?)> getMe() async {
    try {
      final (res, err) = await Api.sendRequest(
        AppEndpoints.usersMe, // /users/me
        method: MethodType.get,
        authenticated: true,
      );

      if (err != null) {
        // Fall back to the in-memory Better Auth user if the API is unreachable.
        final baUser = ba.BetterAuthFlutter.authState.user;
        if (baUser != null) {
          final user = _fromBetterAuthUser(baUser);
          await KvStore.set(KvStoreKeys.profileId, user.id);
          await KvStore.set(KvStoreKeys.user, user.toJson());
          return (user, null);
        }
        return (null, err);
      }

      final data =
          (res as Map<String, dynamic>)["data"] as Map<String, dynamic>;
      // The session is the fallback for the join date on older servers that
      // don't send `createdAt` yet.
      final createdAt = data["createdAt"] != null
          ? DateTime.tryParse(data["createdAt"] as String)
          : ba.BetterAuthFlutter.authState.user?.createdAt;
      final user = User(
        id: data["id"] as String,
        email: data["email"] as String?,
        phone: null,
        name: data["fullName"] as String?,
        avatarUrl: data["avatarUrl"] as String?,
        platformRole: null,
        city: null,
        country: KvStore.get<String>(KvStoreKeys.country),
        age: null,
        isContributor:
            KvStore.get<bool>(KvStoreKeys.onboardingComplete) ?? false,
        createdAt: createdAt,
      );

      await KvStore.set(KvStoreKeys.profileId, user.id);
      await KvStore.set(KvStoreKeys.user, user.toJson());
      return (user, null);
    } catch (e) {
      if (isNetworkError(e)) return (null, Failure.networkError());
      return (null, Failure.fromException(e));
    }
  }

  static Future<(User?, Failure?)> updateProfile({
    String? name,
    String? city,
    String? country,
    int? age,
  }) async {
    try {
      if (name != null) {
        final result = await ba.BetterAuthFlutter.client.updateUser(name: name);
        if (result case ba.Failure(:final error)) {
          return (null, Failure(code: ErrorType.unknown, message: error.message));
        }
      }
      if (country != null) {
        await KvStore.set(KvStoreKeys.country, country);
      }
      return await getMe();
    } catch (e) {
      if (isNetworkError(e)) return (null, Failure.networkError());
      return (null, Failure.fromException(e));
    }
  }

  static Future<User?> loadCachedUser() async {
    try {
      final userJson = KvStore.get<String>(KvStoreKeys.user);
      if (userJson == null) return null;
      return User.fromJson(userJson);
    } catch (e) {
      log("UserRepo: cache parse failed (stale data?), clearing: $e");
      await KvStore.remove(KvStoreKeys.user);
      await KvStore.remove(KvStoreKeys.profileId);
      return null;
    }
  }
}
