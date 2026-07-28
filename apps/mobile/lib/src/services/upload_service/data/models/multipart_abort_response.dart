import "dart:convert";

/// Response from POST /api/v1/s3/multipart/abort
/// Used to abort/cancel a multipart upload
class MultipartAbortResponse {
  final String message;

  MultipartAbortResponse({required this.message});

  Map<String, dynamic> toMap() {
    return {"message": message};
  }

  factory MultipartAbortResponse.fromMap(Map<String, dynamic> map) {
    return MultipartAbortResponse(message: map["message"] as String);
  }

  String toJson() => jsonEncode(toMap());

  factory MultipartAbortResponse.fromJson(String source) =>
      MultipartAbortResponse.fromMap(jsonDecode(source));
}
