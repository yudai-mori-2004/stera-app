import "dart:convert";

import "package:stera/src/services/upload_service/data/models/s3_presign_response.dart";
import "package:drift/drift.dart";

/// Type converter for storing S3PresignResponse in the database as JSON string
class S3PresignResponseTypeConverter
    extends TypeConverter<S3PresignResponse, String> {
  const S3PresignResponseTypeConverter();

  @override
  S3PresignResponse fromSql(String fromDb) {
    final Map<String, dynamic> decoded = json.decode(fromDb);
    return S3PresignResponse.fromMap(decoded);
  }

  @override
  String toSql(S3PresignResponse value) {
    return json.encode(value.toMap());
  }
}
