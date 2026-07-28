import "dart:convert";

import "package:stera/src/services/upload_service/data/models/multipart_parts_response.dart";
import "package:drift/drift.dart";

class PartUrlListTypeConverter extends TypeConverter<List<PartUrl>, String> {
  const PartUrlListTypeConverter();

  @override
  List<PartUrl> fromSql(String fromDb) {
    final List<dynamic> decoded = json.decode(fromDb);
    return decoded
        .map((e) => PartUrl.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  @override
  String toSql(List<PartUrl> value) {
    final List<Map<String, dynamic>> encoded = value
        .map((e) => e.toMap())
        .toList();
    return json.encode(encoded);
  }
}
