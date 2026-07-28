import "dart:convert";
import "dart:developer";
import "dart:io";
import "package:stera/src/core/config/constants/app_endpoints.dart";
import "package:stera/src/services/api/api.dart";
import "package:stera/src/services/api/enums/error_type.dart";
import "package:stera/src/services/api/enums/method_type.dart";
import "package:stera/src/services/api/models/api_failure.dart";
import "package:stera/src/services/api/network_utils.dart";
import "package:stera/src/services/db/schema/models/upload_part.dart";
import "package:stera/src/services/upload_service/data/models/list_parts_response.dart";
import "package:stera/src/services/upload_service/data/models/multipart_abort_response.dart";
import "package:stera/src/services/upload_service/data/models/multipart_finalize_response.dart";
import "package:stera/src/services/upload_service/data/models/multipart_complete_response.dart";
import "package:stera/src/services/upload_service/data/models/multipart_parts_response.dart";
import "package:stera/src/services/upload_service/data/models/multipart_start_response.dart";
import "package:stera/src/services/upload_service/data/models/s3_presign_response.dart";
import "package:stera/src/services/upload_service/utils/resolve_file_path.dart";

class UploadRepo {
  /// Start a multipart upload.
  /// Returns { uploadId, key, assetId } from the backend.
  /// The assetId is stored as videoId in MultipartStartResponse for backwards compat.
  static Future<(MultipartStartResponse?, Failure?)> startMultipartUpload({
    required String fileName,
    required String contentType,
    String? clientUploadId,
  }) async {
    try {
      log("Starting multipart upload: fileName=$fileName");

      final (res, err) = await Api.sendRequest(
        AppEndpoints.uploadMultipartStart,
        method: MethodType.post,
        body: {
          "filename": fileName,
          "contentType": contentType,
          // Enables backend /start idempotency: a replayed start (crash before
          // we persisted the response) returns the original upload.
          "clientUploadId": ?clientUploadId,
        },
        // Unattended upload call: a background 401 must not log the user out.
        suppressSessionExpiry: true,
      );

      if (err != null) {
        log("Multipart start failed for $fileName: ${err.message}");
        return (null, err);
      }

      final data =
          (res as Map<String, dynamic>)["data"] as Map<String, dynamic>;
      // Map backend assetId → videoId field for backwards compatibility within the upload service
      final response = MultipartStartResponse.fromMap(
        data,
      ).copyWith(videoId: data["assetId"] as String?);

      return (response, null);
    } catch (e) {
      if (isNetworkError(e)) return (null, Failure.networkError());
      return (null, Failure.fromException(e));
    }
  }

  /// Get presigned URLs for multipart parts.
  ///
  /// Pass [partNumbers] to presign just-in-time batches (a subset, for a long
  /// upload refreshing expired URLs), or [partCount] to presign 1..partCount
  /// up front (legacy). Exactly one must be supplied. The response carries
  /// `expiresAt` per URL so the caller can refresh before expiry.
  static Future<(MultipartPartsResponse?, Failure?)> getMultipartPartUrls({
    required String key,
    required String uploadId,
    int? partCount,
    List<int>? partNumbers,
  }) async {
    final hasPartNumbers = partNumbers != null && partNumbers.isNotEmpty;
    if (!hasPartNumbers && (partCount == null || partCount <= 0)) {
      return (
        null,
        Failure(
          message: "Provide partCount > 0 or a non-empty partNumbers list",
          code: ErrorType.badRequest,
        ),
      );
    }
    try {
      final (res, err) = await Api.sendRequest(
        AppEndpoints.uploadMultipartParts,
        method: MethodType.post,
        body: {
          "key": key,
          "uploadId": uploadId,
          if (hasPartNumbers)
            "partNumbers": partNumbers
          else
            "partCount": partCount,
        },
        // Unattended upload call: a background 401 must not log the user out.
        suppressSessionExpiry: true,
      );

      if (err != null) {
        final scope = hasPartNumbers
            ? "partNumbers=${partNumbers.length}"
            : "partCount=$partCount";
        log("Multipart parts failed key=$key, $scope: ${err.message}");
        return (null, err);
      }

      final data =
          (res as Map<String, dynamic>)["data"] as Map<String, dynamic>;

      return (MultipartPartsResponse.fromMap(data), null);
    } catch (e) {
      if (isNetworkError(e)) return (null, Failure.networkError());
      return (null, Failure.fromException(e));
    }
  }

  /// List the parts storage has actually received for an open multipart upload
  /// — the storage-anchored truth the reconciler diffs local part rows against
  /// on resume. Requires the backend `list-parts` capability (feature-detect via
  /// [MultipartStartResponse.hasCapability]).
  static Future<(ListPartsResponse?, Failure?)> listMultipartParts({
    required String key,
    required String uploadId,
  }) async {
    try {
      final (res, err) = await Api.sendRequest(
        AppEndpoints.uploadMultipartListParts,
        method: MethodType.post,
        body: {"key": key, "uploadId": uploadId},
        // Unattended upload call: a background 401 must not log the user out.
        suppressSessionExpiry: true,
      );

      if (err != null) {
        log("List parts failed key=$key: ${err.message}");
        return (null, err);
      }

      final data =
          (res as Map<String, dynamic>)["data"] as Map<String, dynamic>;
      return (ListPartsResponse.fromMap(data), null);
    } catch (e) {
      if (isNetworkError(e)) return (null, Failure.networkError());
      return (null, Failure.fromException(e));
    }
  }

  /// Ask the backend to finalize server-side: it completes the multipart upload
  /// itself iff storage already has all [partCount] parts (no client-assembled
  /// parts list, no app wake to call complete). Requires the `server-finalize`
  /// capability.
  static Future<(MultipartFinalizeResponse?, Failure?)> finalizeMultipartUpload({
    required String key,
    required String uploadId,
    required int partCount,
  }) async {
    try {
      final (res, err) = await Api.sendRequest(
        AppEndpoints.uploadMultipartFinalize,
        method: MethodType.post,
        body: {"key": key, "uploadId": uploadId, "partCount": partCount},
        // Unattended upload call: a background 401 must not log the user out.
        suppressSessionExpiry: true,
      );

      if (err != null) {
        log("Multipart finalize failed key=$key: ${err.message}");
        return (null, err);
      }

      final data =
          (res as Map<String, dynamic>)["data"] as Map<String, dynamic>;
      return (MultipartFinalizeResponse.fromMap(data), null);
    } catch (e) {
      if (isNetworkError(e)) return (null, Failure.networkError());
      return (null, Failure.fromException(e));
    }
  }

  /// Complete a multipart upload after all parts are uploaded.
  static Future<(MultipartCompleteResponse?, Failure?)>
  completeMultipartUpload({
    required String key,
    required String uploadId,
    required List<UploadedPart> parts,
  }) async {
    try {
      final (res, err) = await Api.sendRequest(
        AppEndpoints.uploadMultipartComplete,
        method: MethodType.post,
        body: {
          "key": key,
          "uploadId": uploadId,
          "parts": parts.map((e) => e.toApiMap()).toList(),
        },
        // Unattended upload call: a background 401 must not log the user out.
        suppressSessionExpiry: true,
      );

      if (err != null) {
        log(
          "Multipart complete failed key=$key, parts=${parts.length}: ${err.message}",
        );
        return (null, err);
      }

      final data =
          (res as Map<String, dynamic>)["data"] as Map<String, dynamic>;
      return (MultipartCompleteResponse.fromMap(data), null);
    } catch (e) {
      if (isNetworkError(e)) return (null, Failure.networkError());
      return (null, Failure.fromException(e));
    }
  }

  /// Register an uploaded asset in the backend after the file is in R2.
  /// Calls POST /api/v1/assets — user identity derived from JWT, no user_id needed.
  static Future<Failure?> registerAsset({
    required String storagePath,
    required String filename,
    required int durationSeconds,
    String? thumbnailFilePath,
    String? mimeType,
    int? fileSizeBytes,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      String? thumbnailBase64;

      if (thumbnailFilePath != null) {
        final resolvedPath = await ResolveFilePath.resolve(thumbnailFilePath);
        final thumbnailFile = File(resolvedPath);
        if (await thumbnailFile.exists()) {
          final thumbnailBytes = await thumbnailFile.readAsBytes();
          thumbnailBase64 = base64Encode(thumbnailBytes);
        } else {
          log("registerAsset: thumbnail not found at $resolvedPath (stored: $thumbnailFilePath)");
        }
      }

      final (_, err) = await Api.sendRequest(
        AppEndpoints.assets,
        method: MethodType.post,
        body: {
          "storagePath": storagePath,
          "originalFilename": filename,
          "mimeType": ?mimeType,
          "durationSeconds": durationSeconds,
          "fileSizeBytes": ?fileSizeBytes,
          "metadata": _sanitizeMetadataForAssetsApi(metadata),
          "thumbnail": ?thumbnailBase64,
        },
        // Unattended upload call: a background 401 must not log the user out.
        suppressSessionExpiry: true,
      );

      return err;
    } catch (e) {
      if (isNetworkError(e)) return Failure.networkError();
      return Failure.fromException(e);
    }
  }

  /// Abort a multipart upload (cleanup on cancel).
  static Future<(MultipartAbortResponse?, Failure?)> abortMultipartUpload({
    required String key,
    required String uploadId,
  }) async {
    try {
      final (res, err) = await Api.sendRequest(
        AppEndpoints.uploadMultipartAbort,
        method: MethodType.post,
        body: {"key": key, "uploadId": uploadId},
        // Unattended upload call: a background 401 must not log the user out.
        suppressSessionExpiry: true,
      );

      if (err != null) {
        log("Multipart abort failed key=$key: ${err.message}");
        return (null, err);
      }

      final data =
          (res as Map<String, dynamic>)["data"] as Map<String, dynamic>;
      return (MultipartAbortResponse.fromMap(data), null);
    } catch (e) {
      if (isNetworkError(e)) return (null, Failure.networkError());
      return (null, Failure.fromException(e));
    }
  }

  /// [Deprecated] Simple presigned upload — use multipart methods instead.
  @Deprecated("Use startMultipartUpload instead.")
  static Future<(S3PresignResponse?, Failure?)> getPresignedUrl({
    required String fileName,
    required String contentType,
  }) async {
    try {
      final (res, err) = await Api.sendRequest(
        AppEndpoints.uploadPresign,
        method: MethodType.post,
        body: {"filename": fileName, "contentType": contentType},
      );

      if (err != null) return (null, err);

      final data =
          (res as Map<String, dynamic>)["data"] as Map<String, dynamic>;
      return (S3PresignResponse.fromMap(data), null);
    } catch (e) {
      if (isNetworkError(e)) return (null, Failure.networkError());
      return (null, Failure.fromException(e));
    }
  }

  /// POST /api/v1/assets expects several [metadata.json] fields as **strings**
  /// (e.g. `metadata/dataset_quality_summary`, `metadata/compression`), not
  /// nested JSON objects. Session files store objects like:
  /// ```json
  /// "dataset_quality_summary": {
  ///   "cumulative_frame_drift": 1,
  ///   "depth_fps_effective": 14.69,
  ///   "drift_warning": false,
  ///   ...
  /// }
  /// ```
  /// We send that whole value as one JSON **string** via [jsonEncode].
  ///
  /// Rule: any **top-level** value that is a [Map] or [List] becomes a string;
  /// `null`, `bool`, `num`, and `String` are unchanged.
  static Map<String, dynamic> _sanitizeMetadataForAssetsApi(
    Map<String, dynamic>? metadata,
  ) {
    if (metadata == null || metadata.isEmpty) {
      return <String, dynamic>{};
    }
    final out = <String, dynamic>{};
    for (final e in Map<String, dynamic>.from(metadata).entries) {
      out[e.key] = _metadataTopLevelValueForAssetsApi(e.value);
    }
    return out;
  }

  static dynamic _metadataTopLevelValueForAssetsApi(dynamic v) {
    if (v == null || v is bool || v is num || v is String) {
      return v;
    }
    if (v is Map) {
      return _metadataStructuredValueToApiString(Map<String, dynamic>.from(v));
    }
    if (v is List) {
      return _metadataStructuredValueToApiString(v);
    }
    return v.toString();
  }

  static String _metadataStructuredValueToApiString(Object v) {
    try {
      return jsonEncode(v);
    } catch (_) {
      return v.toString();
    }
  }
}
