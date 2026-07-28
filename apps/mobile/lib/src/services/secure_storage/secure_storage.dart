import "package:flutter_secure_storage/flutter_secure_storage.dart";

class SecureStorageKeys {
  static const String accessToken = "access_token";
  static const String refreshToken = "refresh_token";
  static const String onboardingToken = "onboarding_token";
  static const String tokenExpiry = "token_expiry";
}

class SecureStorage {
  static FlutterSecureStorage? _storage;
  static FlutterSecureStorage? get storage => _storage;

  static Future<void> init() async {
    // flutter_secure_storage 10.x defaults to AES-GCM; EncryptedSharedPreferences
    // is deprecated and ignored. Existing values migrate on first access.
    _storage = const FlutterSecureStorage();
  }

  static Future<void> set(String key, String value) async {
    if (storage == null) await init();
    await _storage?.write(key: key, value: value);
  }

  static Future<String?> get(String key, {String? defaultValue}) async {
    if (storage == null) await init();
    final value = await _storage?.read(key: key);
    return value ?? defaultValue;
  }

  static Future<void> remove(String key) async {
    if (storage == null) await init();
    await _storage?.delete(key: key);
  }

  static Future<void> clear() async {
    if (storage == null) await init();
    await _storage?.deleteAll();
  }

  static Future<bool> containsKey(String key) async {
    if (storage == null) await init();
    return await _storage?.containsKey(key: key) ?? false;
  }

  static Future<Map<String, String>> getAll() async {
    if (storage == null) await init();
    return await _storage?.readAll() ?? {};
  }
}
