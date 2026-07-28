import "dart:convert";

/// Response from POST /api/v1/upload/multipart/complete
/// Backend returns: { "data": { "message": "Upload complete" } }
/// Step 3 of multipart upload process
class MultipartCompleteResponse {
  final String message;

  MultipartCompleteResponse({required this.message});

  Map<String, dynamic> toMap() {
    return {"message": message};
  }

  factory MultipartCompleteResponse.fromMap(Map<String, dynamic> map) {
    return MultipartCompleteResponse(
      message: map["message"] as String,
    );
  }

  String toJson() => jsonEncode(toMap());

  factory MultipartCompleteResponse.fromJson(String source) =>
      MultipartCompleteResponse.fromMap(jsonDecode(source));
}
