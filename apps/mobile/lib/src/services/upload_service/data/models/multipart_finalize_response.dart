import "dart:convert";

/// Response from POST /api/v1/upload/multipart/finalize — server-side
/// auto-complete. `completed` is true once storage had every part and the
/// backend completed the multipart upload itself; otherwise `uploadedParts`
/// says how many storage currently has so the client keeps uploading.
class MultipartFinalizeResponse {
  final bool completed;
  final int uploadedParts;

  MultipartFinalizeResponse({required this.completed, required this.uploadedParts});

  factory MultipartFinalizeResponse.fromMap(Map<String, dynamic> map) {
    return MultipartFinalizeResponse(
      completed: (map["completed"] as bool?) ?? false,
      uploadedParts: (map["uploadedParts"] as num?)?.toInt() ?? 0,
    );
  }

  String toJson() =>
      jsonEncode({"completed": completed, "uploadedParts": uploadedParts});

  factory MultipartFinalizeResponse.fromJson(String source) =>
      MultipartFinalizeResponse.fromMap(jsonDecode(source));
}
