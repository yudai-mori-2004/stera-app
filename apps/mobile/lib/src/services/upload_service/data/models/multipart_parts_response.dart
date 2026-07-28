import "dart:convert";

/// Response from POST /api/v1/upload/multipart/parts
///
/// Backend (post Phase-3) returns either form:
///   legacy:  { "urls": ["https://...", ...] }
///   current: { "urls": [...], "parts": [{partNumber,url,expiresAt}],
///              "expiresInSeconds": 86400, "expiresAt": "..." }
/// We prefer `parts` (explicit partNumber + expiry, needed for just-in-time
/// batches whose part numbers aren't 1..N) and fall back to `urls`.
class MultipartPartsResponse {
  final List<PartUrl> urls;

  /// TTL the backend applied to this batch's URLs, if advertised.
  final int? expiresInSeconds;

  MultipartPartsResponse({required this.urls, this.expiresInSeconds});

  Map<String, dynamic> toMap() {
    return {
      "urls": urls.map((e) => e.toMap()).toList(),
      if (expiresInSeconds != null) "expiresInSeconds": expiresInSeconds,
    };
  }

  factory MultipartPartsResponse.fromMap(Map<String, dynamic> map) {
    final partsRaw = map["parts"];
    final List<PartUrl> urls;

    if (partsRaw is List) {
      urls = partsRaw
          .map((e) => PartUrl.fromMap(e as Map<String, dynamic>))
          .toList();
    } else {
      // Legacy `urls` string[] — infer 1-based part numbers, share the
      // batch-level expiry if present.
      final urlsList = (map["urls"] as List<dynamic>?) ?? const [];
      final batchExpiry = _parseDate(map["expiresAt"]);
      urls = urlsList
          .asMap()
          .entries
          .map(
            (e) => PartUrl(
              partNumber: e.key + 1,
              url: e.value as String,
              expiresAt: batchExpiry,
            ),
          )
          .toList();
    }

    return MultipartPartsResponse(
      urls: urls,
      expiresInSeconds: (map["expiresInSeconds"] as num?)?.toInt(),
    );
  }

  String toJson() => jsonEncode(toMap());

  factory MultipartPartsResponse.fromJson(String source) =>
      MultipartPartsResponse.fromMap(jsonDecode(source));
}

/// Individual part URL for multipart upload.
/// [partNumber] is 1-based (matches S3 multipart part numbering).
/// [url] is the presigned S3 PUT URL for this part.
/// [expiresAt] is when that URL stops being valid, so the client can refresh
/// proactively (null for legacy responses that didn't advertise it).
class PartUrl {
  final int partNumber;
  final String url;
  final DateTime? expiresAt;

  PartUrl({required this.partNumber, required this.url, this.expiresAt});

  Map<String, dynamic> toMap() {
    return {
      "partNumber": partNumber,
      "url": url,
      if (expiresAt != null) "expiresAt": expiresAt!.toIso8601String(),
    };
  }

  factory PartUrl.fromMap(Map<String, dynamic> map) {
    return PartUrl(
      partNumber: map["partNumber"] as int,
      url: map["url"] as String,
      expiresAt: _parseDate(map["expiresAt"]),
    );
  }

  String toJson() => jsonEncode(toMap());

  factory PartUrl.fromJson(String source) =>
      PartUrl.fromMap(jsonDecode(source));
}

DateTime? _parseDate(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;
