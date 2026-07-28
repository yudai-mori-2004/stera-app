import "dart:convert";

/// Response from POST /api/v1/s3/presign
/// Used for simple uploads (files ≤ 5GB)
class S3PresignResponse {
  final String uploadUrl;
  final String key;
  final String folder;
  final String message;

  S3PresignResponse({
    required this.uploadUrl,
    required this.key,
    required this.folder,
    required this.message,
  });

  Map<String, dynamic> toMap() {
    return {
      "uploadUrl": uploadUrl,
      "key": key,
      "folder": folder,
      "message": message,
    };
  }

  factory S3PresignResponse.fromMap(Map<String, dynamic> map) {
    return S3PresignResponse(
      uploadUrl: map["uploadUrl"] as String,
      key: map["key"] as String,
      folder: map["folder"] as String,
      message: map["message"] as String,
    );
  }

  String toJson() => jsonEncode(toMap());

  factory S3PresignResponse.fromJson(String source) =>
      S3PresignResponse.fromMap(jsonDecode(source));
}
