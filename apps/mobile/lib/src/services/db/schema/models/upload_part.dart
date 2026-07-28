import "dart:convert";

import "package:drift/drift.dart";

/// Represents an uploaded part of a multipart upload
/// Used to track completed parts for resume capability
class UploadedPart {
  final String etag;
  final int partNumber;

  UploadedPart({required this.etag, required this.partNumber});

  /// Map for database storage
  Map<String, dynamic> toMap() => {"ETag": etag, "PartNumber": partNumber};

  /// Map for API calls (complete multipart upload)
  Map<String, dynamic> toApiMap() => {
    "ETag": _etagWithQuotes(etag),
    "PartNumber": partNumber,
  };

  factory UploadedPart.fromMap(Map<String, dynamic> map) {
    return UploadedPart(
      etag: map["ETag"] as String,
      partNumber: map["PartNumber"] as int,
    );
  }

  String toJson() => json.encode(toMap());

  factory UploadedPart.fromJson(String source) =>
      UploadedPart.fromMap(json.decode(source));

  static String _etagWithQuotes(String value) {
    if (value.startsWith('"') && value.endsWith('"')) return value;
    return '"$value"';
  }
}

/// Type converter for storing `List<UploadedPart>` in the database as JSON string
class UploadedPartsConverter extends TypeConverter<List<UploadedPart>, String> {
  const UploadedPartsConverter();

  @override
  List<UploadedPart> fromSql(String fromDb) {
    final list = jsonDecode(fromDb) as List<dynamic>;
    return list
        .map((e) => UploadedPart.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  @override
  String toSql(List<UploadedPart> value) {
    return jsonEncode(value.map((e) => e.toMap()).toList());
  }
}
