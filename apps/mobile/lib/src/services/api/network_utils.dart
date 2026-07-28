import "dart:io";

import "package:better_auth_flutter/better_auth_flutter.dart" as ba;

/// Returns true if the given error is a network-related exception
/// (DNS failure, TLS handshake failure, connection reset, etc.).
bool isNetworkError(Object e) {
  if (e is SocketException || e is HandshakeException || e is HttpException) {
    return true;
  }
  if (e is ba.BetterError && e.isNetworkError) return true;
  final msg = e.toString();
  return msg.contains("SocketException") ||
      msg.contains("HandshakeException") ||
      msg.contains("Connection terminated") ||
      msg.contains("Failed host lookup") ||
      msg.contains("NETWORK_ERROR") ||
      msg.contains("TIMEOUT");
}

/// Status codes that mean the request never reached a healthy origin: standard
/// 5xx plus Cloudflare's 52x family (522 = origin connection timed out).
const _upstreamOutageCodes = {500, 502, 503, 504, 520, 521, 522, 523, 524};

final _upstreamOutageMessage = RegExp(r"error code: 5\d\d");

/// True when the failure is an upstream/origin outage, not the user's
/// connectivity. Distinguished from [isNetworkError] so callers can tell the
/// user the service is down instead of blaming their connection.
bool isUpstreamOutage(Object e) {
  if (e is ba.BetterError) {
    final code = e.statusCode;
    if (code != null && _upstreamOutageCodes.contains(code)) return true;
  }
  return _upstreamOutageMessage.hasMatch(e.toString());
}

/// Retries [fn] up to [maxRetries] times when a network error occurs.
/// Waits [delay] between attempts (doubles each retry).
Future<T> retryOnNetworkError<T>(
  Future<T> Function() fn, {
  int maxRetries = 2,
  Duration delay = const Duration(milliseconds: 500),
}) async {
  var attempts = 0;
  while (true) {
    try {
      return await fn();
    } catch (e) {
      attempts++;
      final retryable = isNetworkError(e) || isUpstreamOutage(e);
      if (!retryable || attempts > maxRetries) rethrow;
      await Future.delayed(delay * attempts);
    }
  }
}
