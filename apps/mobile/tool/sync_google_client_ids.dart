import "dart:io";

/// Writes the Google Sign-In web client ID from `.env` into Android's
/// `strings.xml`. The iOS half lives in `sync_ios_config.dart`.
///
/// Run via `dart run tool/sync_google_client_ids.dart` (also invoked by
/// `bun run pub-get:mobile` / `npm run pub-get --workspace @stera/mobile`).
Future<void> main(List<String> args) async {
  final repoRoot = Directory.current.path;
  final envPath = File("$repoRoot/.env");
  final envExamplePath = File("$repoRoot/.env.example");

  final envFile = envPath.existsSync() ? envPath : envExamplePath;
  if (!envFile.existsSync()) {
    stderr.writeln(
      "No .env or .env.example found in $repoRoot — skipping Google client sync.",
    );
    exit(0);
  }

  final values = _parseEnv(await envFile.readAsString());

  // An auth-free build has no Google Sign-In, and its `.env` may hold nothing
  // but the flag. Bailing here is what lets `bun run pub-get:mobile` succeed
  // against a one-line `.env`.
  final noAuth = (values["NO_AUTH_MODE"] ?? "").trim().toLowerCase();
  if (noAuth == "true" || noAuth == "1") {
    stdout.writeln("NO_AUTH_MODE — skipping Google client sync.");
    exit(0);
  }

  final webClientId = values["GOOGLE_WEB_CLIENT_ID"];
  final iosClientId = values["GOOGLE_IOS_CLIENT_ID"];

  if (webClientId == null || webClientId.isEmpty) {
    stderr.writeln("GOOGLE_WEB_CLIENT_ID missing in ${envFile.path}");
    exit(1);
  }

  if (iosClientId == null || iosClientId.isEmpty) {
    stderr.writeln("GOOGLE_IOS_CLIENT_ID missing in ${envFile.path}");
    exit(1);
  }

  // iOS is handled by `sync_ios_config.dart`, which writes the reversed client
  // id into a git-ignored xcconfig that `Info.plist` reads as
  // `$(GOOGLE_REVERSED_CLIENT_ID)` — so no real id ever lands in a tracked file.
  // Android's `strings.xml` has no equivalent indirection and is rewritten in
  // place; keep it out of your commits.
  await _writeAndroidStrings(repoRoot, webClientId);

  stdout.writeln("Synced Google web client ID from ${envFile.path}");
}

Map<String, String> _parseEnv(String contents) {
  final values = <String, String>{};

  for (final rawLine in contents.split("\n")) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith("#")) {
      continue;
    }

    final separator = line.indexOf("=");
    if (separator <= 0) {
      continue;
    }

    final key = line.substring(0, separator).trim();
    var value = line.substring(separator + 1).trim();

    if ((value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'"))) {
      value = value.substring(1, value.length - 1);
    }

    values[key] = value;
  }

  return values;
}

Future<void> _writeAndroidStrings(String repoRoot, String webClientId) async {
  final stringsPath = File(
    "$repoRoot/android/app/src/main/res/values/strings.xml",
  );

  if (!stringsPath.existsSync()) {
    stderr.writeln("Android strings.xml not found at ${stringsPath.path}");
    exit(1);
  }

  var xml = await stringsPath.readAsString();
  xml = xml.replaceFirst(
    RegExp(
      r'<string name="default_web_client_id">[^<]*</string>',
    ),
    '<string name="default_web_client_id">$webClientId</string>',
  );

  await stringsPath.writeAsString(xml);
  stdout.writeln("Updated ${stringsPath.path}");
}

