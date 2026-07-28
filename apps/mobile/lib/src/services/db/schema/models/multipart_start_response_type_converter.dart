import "dart:convert";

import "package:stera/src/services/upload_service/data/models/multipart_start_response.dart";
import "package:drift/drift.dart";

/// Type converter for storing MultipartStartResponse in the database as JSON string
class MultipartStartResponseTypeConverter
    extends TypeConverter<MultipartStartResponse, String> {
  const MultipartStartResponseTypeConverter();

  @override
  MultipartStartResponse fromSql(String fromDb) {
    final Map<String, dynamic> decoded = json.decode(fromDb);
    return MultipartStartResponse.fromMap(decoded);
  }

  @override
  String toSql(MultipartStartResponse value) {
    return json.encode(value.toMap());
  }
}
