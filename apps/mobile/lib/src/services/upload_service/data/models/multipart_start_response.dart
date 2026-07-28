import "dart:convert";

/// Response from POST /api/v1/upload/multipart/start
/// Backend returns: { "data": { "uploadId": "...", "key": "...", "assetId": "..." } }
/// Step 1 of multipart upload process
class MultipartStartResponse {
  final String uploadId;
  final String key;
  final String? message;
  final String? videoId;

  /// Capabilities the backend advertises (e.g. `list-parts`, `presign-batch`,
  /// `presign-expiry`, `complete-idempotent`, `start-idempotent`). Lets the
  /// client feature-detect before relying on the new endpoints. Empty/absent
  /// on older backends. See [hasCapability].
  final List<String> capabilities;

  /// True when the backend **deduped** this `/start` on `clientUploadId` and
  /// returned a pre-existing multipart upload instead of creating a new one
  /// (`upload.ts` idempotency replay). The caller MUST then reconcile against
  /// storage (`list-parts`) before re-uploading — R2 may already hold parts the
  /// local journal doesn't know about (e.g. after a logout wiped the journal).
  /// Absent/false on a genuinely fresh start or an older backend.
  final bool idempotentReplay;

  MultipartStartResponse({
    required this.uploadId,
    required this.key,
    this.message,
    this.videoId,
    this.capabilities = const [],
    this.idempotentReplay = false,
  });

  bool hasCapability(String capability) => capabilities.contains(capability);

  MultipartStartResponse copyWith({
    String? uploadId,
    String? key,
    String? message,
    String? videoId,
    List<String>? capabilities,
    bool? idempotentReplay,
  }) {
    return MultipartStartResponse(
      uploadId: uploadId ?? this.uploadId,
      key: key ?? this.key,
      message: message ?? this.message,
      videoId: videoId ?? this.videoId,
      capabilities: capabilities ?? this.capabilities,
      idempotentReplay: idempotentReplay ?? this.idempotentReplay,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      "uploadId": uploadId,
      "key": key,
      "message": message,
      "videoId": videoId,
      "capabilities": capabilities,
      "idempotentReplay": idempotentReplay,
    };
  }

  factory MultipartStartResponse.fromMap(Map<String, dynamic> map) {
    return MultipartStartResponse(
      uploadId: map["uploadId"] as String,
      key: map["key"] as String,
      message: map["message"] as String?,
      videoId: map["videoId"] as String?,
      capabilities:
          (map["capabilities"] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      idempotentReplay: map["idempotentReplay"] as bool? ?? false,
    );
  }

  String toJson() => jsonEncode(toMap());

  factory MultipartStartResponse.fromJson(String source) =>
      MultipartStartResponse.fromMap(jsonDecode(source));
}
