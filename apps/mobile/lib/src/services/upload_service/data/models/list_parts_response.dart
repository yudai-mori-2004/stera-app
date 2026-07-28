import "dart:convert";

/// Response from POST /api/v1/upload/multipart/list-parts — the storage-anchored
/// truth the client reconciles its local part rows against on resume.
///
/// When [uploadExists] is false the multipart upload id is gone (already
/// completed, aborted, or lifecycle-expired); [objectExists] then says whether
/// the final object actually landed — the two signals the reconciler's
/// `NoSuchUpload` branch needs (see 06 §6).
class ListPartsResponse {
  final List<RemotePart> parts;
  final bool uploadExists;
  final bool objectExists;

  ListPartsResponse({
    required this.parts,
    this.uploadExists = true,
    this.objectExists = false,
  });

  factory ListPartsResponse.fromMap(Map<String, dynamic> map) {
    final partsRaw = (map["parts"] as List<dynamic>?) ?? const [];
    return ListPartsResponse(
      parts: partsRaw
          .map((e) => RemotePart.fromMap(e as Map<String, dynamic>))
          .toList(),
      uploadExists: (map["uploadExists"] as bool?) ?? true,
      objectExists: (map["objectExists"] as bool?) ?? false,
    );
  }

  String toJson() => jsonEncode({
    "parts": parts.map((e) => e.toMap()).toList(),
    "uploadExists": uploadExists,
    "objectExists": objectExists,
  });

  factory ListPartsResponse.fromJson(String source) =>
      ListPartsResponse.fromMap(jsonDecode(source));
}

/// One part R2 reports as already received: its number, ETag (quotes stripped
/// server-side), and byte size.
class RemotePart {
  final int partNumber;
  final String etag;
  final int size;

  RemotePart({
    required this.partNumber,
    required this.etag,
    required this.size,
  });

  Map<String, dynamic> toMap() => {
    "partNumber": partNumber,
    "etag": etag,
    "size": size,
  };

  factory RemotePart.fromMap(Map<String, dynamic> map) {
    return RemotePart(
      partNumber: map["partNumber"] as int,
      etag: (map["etag"] as String?) ?? "",
      size: (map["size"] as num?)?.toInt() ?? 0,
    );
  }
}
