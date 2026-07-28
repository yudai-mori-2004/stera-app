import "package:flutter_dotenv/flutter_dotenv.dart";
import "package:flutter_test/flutter_test.dart";
import "package:stera/src/core/config/app_config.dart";

void main() {
  tearDown(() {
    dotenv.clean();
    AppConfig.debugResetConfigCache();
    AppConfig.debugOverrideNoAuthMode = null;
  });

  group("ConfigModel.fromMap", () {
    test("missing keys fall back to empty strings rather than throwing", () {
      final config = ConfigModel.fromMap(const {});

      expect(config.prodHost, "");
      expect(config.prodAuthBaseUrl, "");
      expect(config.prodApiVersion, "");
      expect(config.devHost, "");
      expect(config.devAuthBaseUrl, "");
      expect(config.devApiVersion, "");
      expect(config.googleWebClientId, "");
      expect(config.googleIosClientId, "");
    });

    test("an unknown or absent ENVIRONMENT resolves to prod", () {
      expect(ConfigModel.fromMap(const {}).environment, Environment.prod);
      expect(
        ConfigModel.fromMap(const {"ENVIRONMENT": "staging"}).environment,
        Environment.prod,
      );
      expect(
        ConfigModel.fromMap(const {"ENVIRONMENT": "dev"}).environment,
        Environment.dev,
      );
    });
  });

  group("AppConfig.config", () {
    test("never throws before dotenv is loaded", () {
      expect(dotenv.isInitialized, isFalse);

      expect(() => AppConfig.config, returnsNormally);
      expect(AppConfig.config.prodHost, "");
      expect(AppConfig.host, "");
      expect(AppConfig.authBaseUrl, "");
      expect(AppConfig.apiVersion, "");
    });

    test("a pre-load read does not poison the cache", () {
      // Reading first, then loading, is the ordering that a naive `_cache ??=`
      // would freeze an empty model for the rest of the process.
      expect(AppConfig.config.prodHost, "");

      dotenv.loadFromString(envString: "PROD_HOST=api.example.com");

      expect(AppConfig.config.prodHost, "api.example.com");
    });
  });

  group("AppConfig.noAuthMode", () {
    test("is false when dotenv has not been loaded", () {
      expect(dotenv.isInitialized, isFalse);
      expect(AppConfig.noAuthMode, isFalse);
    });

    test("is false when the key is absent or empty", () {
      dotenv.loadFromString(envString: "ENVIRONMENT=dev");
      expect(AppConfig.noAuthMode, isFalse);

      dotenv.clean();
      dotenv.loadFromString(envString: "NO_AUTH_MODE=", isOptional: true);
      expect(AppConfig.noAuthMode, isFalse);
    });

    test("accepts true/TRUE/1, with surrounding whitespace", () {
      for (final raw in ["true", "TRUE", "True", "1", "  true  "]) {
        dotenv.clean();
        dotenv.loadFromString(envString: "NO_AUTH_MODE=$raw");
        expect(AppConfig.noAuthMode, isTrue, reason: "for '$raw'");
      }
    });

    test("rejects anything else", () {
      for (final raw in ["false", "no", "0", "yes", "on"]) {
        dotenv.clean();
        dotenv.loadFromString(envString: "NO_AUTH_MODE=$raw");
        expect(AppConfig.noAuthMode, isFalse, reason: "for '$raw'");
      }
    });

    test("debugOverrideNoAuthMode wins over the environment", () {
      dotenv.loadFromString(envString: "NO_AUTH_MODE=false");

      AppConfig.debugOverrideNoAuthMode = true;
      expect(AppConfig.noAuthMode, isTrue);

      AppConfig.debugOverrideNoAuthMode = false;
      expect(AppConfig.noAuthMode, isFalse);
    });

    test("the flag is readable with nothing else in the environment", () {
      // The whole point of the mode: a one-line `.env` is a complete config.
      dotenv.loadFromString(envString: "NO_AUTH_MODE=true");

      expect(AppConfig.noAuthMode, isTrue);
      expect(() => AppConfig.host, returnsNormally);
      expect(AppConfig.host, "");
    });
  });
}
