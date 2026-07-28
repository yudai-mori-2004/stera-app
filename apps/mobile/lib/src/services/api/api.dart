import "dart:convert";
import "dart:developer";

import "package:stera/src/core/config/app_config.dart";
import "package:stera/src/core/config/constants/app_constants.dart";
import "package:stera/src/services/api/enums/error_type.dart";
import "package:stera/src/services/api/enums/method_type.dart";
import "package:stera/src/services/api/models/api_failure.dart";
import "package:stera/src/services/api/token_service.dart";
import "package:http/http.dart" as http;

class Api {
  static final hc = http.Client();

  static http.Request customRequest(MethodType method, String path) =>
      http.Request(method.id, Uri.parse(path));

  static Future<(dynamic, Failure?)> sendRequest(
    String path, {
    required MethodType method,
    String? host,
    String? apiVersion,
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? body,
    bool authenticated = true,
    int retryCount = 0,
    bool suppressSessionExpiry = false,
  }) async {
    // Every outbound call funnels through here, so one guard makes "an auth-free
    // build never touches the network" structurally true rather than true by
    // inspection of the call graph.
    if (AppConfig.noAuthMode) {
      return (
        null,
        Failure(
          code: ErrorType.serviceUnavailable,
          message: "Network features are disabled in this build.",
        ),
      );
    }

    headers ??= {};
    queryParameters ??= {};
    body ??= {};
    host ??= AppConfig.host;
    apiVersion ??= AppConfig.apiVersion;

    // Split host:port if port is included (e.g., for local dev)
    final hostParts = host.split(":");
    final hostName = hostParts[0];
    final port = hostParts.length > 1 ? int.tryParse(hostParts[1]) : null;

    final uri = Uri(
      scheme: AppConstants.scheme,
      host: hostName,
      port: port,
      path: apiVersion + path,
      queryParameters: queryParameters.isNotEmpty ? queryParameters : null,
    );

    if (authenticated) {
      final (cookieHeaders, tokenFailure) =
          await TokenService.getAuthHeaders(uri: uri);

      if (tokenFailure != null) return (null, tokenFailure);

      if (cookieHeaders != null) {
        cookieHeaders.forEach((k, v) => headers!.putIfAbsent(k, () => v));
      }
    }

    headers.addAll({"Content-Type": "application/json"});

    final http.Response response;

    try {
      switch (method) {
        case MethodType.get:
          response = await hc.get(uri, headers: headers);
          break;
        case MethodType.post:
          response = await hc.post(
            uri,
            headers: headers,
            body: jsonEncode(body),
          );
          break;
        case MethodType.patch:
          response = await hc.patch(
            uri,
            headers: headers,
            body: jsonEncode(body),
          );
          break;
        case MethodType.put:
          response = await hc.put(
            uri,
            headers: headers,
            body: jsonEncode(body),
          );
          break;
        case MethodType.delete:
          response = await hc.delete(
            uri,
            headers: headers,
            body: jsonEncode(body),
          );
          break;
      }
    } catch (e) {
      log("Api: Network error: $e");
      return (null, Failure.networkError());
    }

    await TokenService.saveCookiesFromResponse(
      uri,
      response.headersSplitValues["set-cookie"] ?? const [],
    );

    switch (response.statusCode) {
      case 200:
      case 201:
        final decoded = jsonDecode(response.body);
        return (decoded, null);
      case 204:
        return (null, null);
      case 400:
        try {
          final decoded = jsonDecode(response.body);
          final message = _extractErrorMessage(decoded) ?? "Bad request";
          return (
            null,
            Failure(message: message, code: ErrorType.badRequest),
          );
        } catch (e) {
          log("Api: Failed to parse 400 response: $e");
          return (
            null,
            Failure(message: "Bad request", code: ErrorType.badRequest),
          );
        }
      case 403:
        try {
          final decoded = jsonDecode(response.body);
          final message = _extractErrorMessage(decoded) ?? "Forbidden";
          return (null, Failure(code: ErrorType.forbidden, message: message));
        } catch (e) {
          return (
            null,
            Failure(code: ErrorType.forbidden, message: "Forbidden"),
          );
        }
      case 404:
        try {
          final decoded = jsonDecode(response.body);
          log("API Error 404: $decoded");
        } catch (e) {
          log("API Error 404: Failed to parse response");
        }
        return (null, Failure.notFound());
      case 409:
        try {
          final decoded = jsonDecode(response.body);
          final message = _extractErrorMessage(decoded) ?? "Conflict";
          return (null, Failure(code: ErrorType.conflict, message: message));
        } catch (e) {
          return (null, Failure(code: ErrorType.conflict, message: "Conflict"));
        }
      case 401:
        log("Api: Received 401, session expired");
        if (authenticated && !suppressSessionExpiry) {
          await TokenService.handleSessionExpired();
        }
        return (null, Failure.unAuthorized());
      case 429:
        return (null, Failure.tooManyRequests());
      case 500:
      case 502:
      case 503:
      case 504:
        final serverMessage = _extractErrorMessageFromBody(response.body);
        final requestId = _extractRequestIdFromBody(response.body);
        log(
          "Api: Server error ${response.statusCode} for $path"
          "${serverMessage != null ? ": $serverMessage" : ""}"
          "${requestId != null ? " (requestId: $requestId)" : ""}",
        );
        return (
          null,
          Failure(
            message: serverMessage ?? "Server error at $path",
            code: ErrorType.unknown,
          ),
        );
      default:
        log("Api: Unhandled status code: ${response.statusCode}");
        return (null, Failure.unknown());
    }
  }

  static String? _extractErrorMessage(dynamic decoded) {
    if (decoded == null) return null;

    if (decoded is Map<String, dynamic>) {
      if (decoded["error"] is Map) {
        return (decoded["error"] as Map<String, dynamic>)["message"] as String?;
      }
      if (decoded["error"] is String) {
        return decoded["error"] as String?;
      }
      if (decoded["message"] is String) {
        return decoded["message"] as String?;
      }
      if (decoded["detail"] is Map) {
        return (decoded["detail"] as Map<String, dynamic>)["message"] as String?;
      }
      if (decoded["detail"] is String) {
        return decoded["detail"] as String?;
      }
    }

    return null;
  }

  static String? _extractRequestIdFromBody(String body) {
    if (body.isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic> && decoded["error"] is Map) {
        return (decoded["error"] as Map<String, dynamic>)["requestId"]
            as String?;
      }
    } catch (_) {}
    return null;
  }

  static String? _extractErrorMessageFromBody(String body) {
    if (body.isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      return _extractErrorMessage(decoded);
    } catch (_) {
      return null;
    }
  }
}
