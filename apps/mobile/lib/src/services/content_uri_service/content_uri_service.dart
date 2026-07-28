import "dart:developer";
import "dart:typed_data";

import "package:stera/src/core/enums/platform_channel_methods.dart";
import "package:stera/src/core/enums/platform_channels.dart";

class ContentUriService {
  static const _channel = PlatformChannels.contentUriHelper;

  static Future<bool> takePersistentPermission(Uri contentUri) async {
    try {
      final result = await _channel.channel.invokeMethod<bool>(
        ContentUriHelperMethod.takePersistentPermission.methodName,
        {"uri": contentUri.toString()},
      );
      return result ?? false;
    } catch (e) {
      log("Error taking persistent permission: $e");
      return false;
    }
  }

  static Future<bool> releasePersistentPermission(Uri contentUri) async {
    try {
      final result = await _channel.channel.invokeMethod<bool>(
        ContentUriHelperMethod.releasePersistentPermission.methodName,
        {"uri": contentUri.toString()},
      );
      return result ?? false;
    } catch (e) {
      log("Error releasing persistent permission: $e");
      return false;
    }
  }

  /// Check if we still have permission for a URI.
  static Future<bool> hasPermission(Uri contentUri) async {
    try {
      final result = await _channel.channel.invokeMethod<bool>(
        ContentUriHelperMethod.hasPermission.methodName,
        {"uri": contentUri.toString()},
      );
      return result ?? false;
    } catch (e) {
      log("Error checking permission: $e");
      return false;
    }
  }

  static Future<int> getFileSize(Uri contentUri) async {
    try {
      log("🔍 ContentUriService: Requesting file size for $contentUri");
      final result = await _channel.channel.invokeMethod<int>(
        ContentUriHelperMethod.getFileSize.methodName,
        {"uri": contentUri.toString()},
      );
      if (result == null) {
        log("❌ ContentUriService: Received nil for file size of $contentUri");
        throw ContentUriException("Failed to get file size", uri: contentUri);
      }
      log("✅ ContentUriService: Received file size $result for $contentUri");
      return result;
    } catch (e) {
      log("❌ ContentUriService: Error getting file size for $contentUri: $e");
      if (e is ContentUriException) rethrow;
      throw ContentUriException("Failed to get file size: $e", uri: contentUri);
    }
  }

  static Future<Map<String, dynamic>?> getFileMetadata(Uri contentUri) async {
    try {
      log("🔍 ContentUriService: Requesting metadata for $contentUri");
      final result = await _channel.channel.invokeMethod<Map>(
        ContentUriHelperMethod.getFileMetadata.methodName,
        {"uri": contentUri.toString()},
      );
      if (result == null) {
        log("❌ ContentUriService: Received nil metadata for $contentUri");
        return null;
      }
      log("✅ ContentUriService: Received metadata for $contentUri: $result");
      return Map<String, dynamic>.from(result);
    } catch (e) {
      log("❌ ContentUriService: Error getting metadata for $contentUri: $e");
      log("Error getting file metadata: $e");
      return null;
    }
  }

  static Future<Uint8List> readChunk(
    Uri contentUri,
    int offset,
    int length,
  ) async {
    try {
      final result = await _channel.channel.invokeMethod<Uint8List>(
        ContentUriHelperMethod.readChunk.methodName,
        {"uri": contentUri.toString(), "offset": offset, "length": length},
      );
      if (result == null) {
        throw ContentUriException(
          "Failed to read chunk at offset $offset",
          uri: contentUri,
        );
      }
      return result;
    } catch (e) {
      if (e is ContentUriException) rethrow;
      throw ContentUriException(
        "Failed to read chunk at offset $offset: $e",
        uri: contentUri,
      );
    }
  }
}

class ContentUriException implements Exception {
  final String message;
  final Uri? uri;

  ContentUriException(this.message, {this.uri});

  @override
  String toString() => uri != null
      ? "ContentUriException: $message (uri: $uri)"
      : "ContentUriException: $message";
}
