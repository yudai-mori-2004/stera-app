import "package:stera/src/services/db/schema/enums/upload_status.dart";
import "package:stera/src/services/db/schema/models/multipart_start_response_type_converter.dart";
import "package:stera/src/services/db/schema/models/part_url_type_converter.dart";
import "package:stera/src/services/db/schema/models/s3_presign_response_type_converter.dart";
import "package:stera/src/services/db/schema/models/upload_part.dart";
import "package:drift/drift.dart";

/// Uploads table - tracks video upload queue and progress
class Uploads extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get filepath => text()();
  IntColumn get filesize => integer().nullable()();
  IntColumn get durationMs => integer().nullable()();
  TextColumn get thumnbnail => text().nullable()();
  TextColumn get metadataFilepath => text().nullable()();
  TextColumn get status => textEnum<UploadStatus>().withDefault(
    Constant(UploadStatus.pending.name),
  )();
  TextColumn get fileName => text().nullable()();
  TextColumn get mimeType => text().nullable()();
  RealColumn get progress => real().nullable()();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  TextColumn get s3PresignResponse =>
      text().map(const S3PresignResponseTypeConverter()).nullable()();
  TextColumn get multipartStartResponse =>
      text().map(const MultipartStartResponseTypeConverter()).nullable()();
  TextColumn get partUrls =>
      text().map(const PartUrlListTypeConverter()).nullable()();
  TextColumn get uploadedParts =>
      text().map(const UploadedPartsConverter()).nullable()();
  IntColumn get partsCount => integer().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isHidden => boolean().withDefault(const Constant(false))();
  TextColumn get taskId => text().nullable()();
  TextColumn get taskName => text().nullable()();
  TextColumn get subtaskId => text().nullable()();
  TextColumn get subtaskName => text().nullable()();
}
