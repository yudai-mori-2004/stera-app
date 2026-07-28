// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'db.dart';

// ignore_for_file: type=lint
class $UploadsTable extends Uploads with TableInfo<$UploadsTable, Upload> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UploadsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _filepathMeta = const VerificationMeta(
    'filepath',
  );
  @override
  late final GeneratedColumn<String> filepath = GeneratedColumn<String>(
    'filepath',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _filesizeMeta = const VerificationMeta(
    'filesize',
  );
  @override
  late final GeneratedColumn<int> filesize = GeneratedColumn<int>(
    'filesize',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _thumnbnailMeta = const VerificationMeta(
    'thumnbnail',
  );
  @override
  late final GeneratedColumn<String> thumnbnail = GeneratedColumn<String>(
    'thumnbnail',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _metadataFilepathMeta = const VerificationMeta(
    'metadataFilepath',
  );
  @override
  late final GeneratedColumn<String> metadataFilepath = GeneratedColumn<String>(
    'metadata_filepath',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<UploadStatus, String> status =
      GeneratedColumn<String>(
        'status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: Constant(UploadStatus.pending.name),
      ).withConverter<UploadStatus>($UploadsTable.$converterstatus);
  static const VerificationMeta _fileNameMeta = const VerificationMeta(
    'fileName',
  );
  @override
  late final GeneratedColumn<String> fileName = GeneratedColumn<String>(
    'file_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _mimeTypeMeta = const VerificationMeta(
    'mimeType',
  );
  @override
  late final GeneratedColumn<String> mimeType = GeneratedColumn<String>(
    'mime_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _progressMeta = const VerificationMeta(
    'progress',
  );
  @override
  late final GeneratedColumn<double> progress = GeneratedColumn<double>(
    'progress',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _retryCountMeta = const VerificationMeta(
    'retryCount',
  );
  @override
  late final GeneratedColumn<int> retryCount = GeneratedColumn<int>(
    'retry_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  late final GeneratedColumnWithTypeConverter<S3PresignResponse?, String>
  s3PresignResponse =
      GeneratedColumn<String>(
        's3_presign_response',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<S3PresignResponse?>(
        $UploadsTable.$converters3PresignResponsen,
      );
  @override
  late final GeneratedColumnWithTypeConverter<MultipartStartResponse?, String>
  multipartStartResponse =
      GeneratedColumn<String>(
        'multipart_start_response',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<MultipartStartResponse?>(
        $UploadsTable.$convertermultipartStartResponsen,
      );
  @override
  late final GeneratedColumnWithTypeConverter<List<PartUrl>?, String> partUrls =
      GeneratedColumn<String>(
        'part_urls',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<List<PartUrl>?>($UploadsTable.$converterpartUrlsn);
  @override
  late final GeneratedColumnWithTypeConverter<List<UploadedPart>?, String>
  uploadedParts = GeneratedColumn<String>(
    'uploaded_parts',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  ).withConverter<List<UploadedPart>?>($UploadsTable.$converteruploadedPartsn);
  static const VerificationMeta _partsCountMeta = const VerificationMeta(
    'partsCount',
  );
  @override
  late final GeneratedColumn<int> partsCount = GeneratedColumn<int>(
    'parts_count',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _isHiddenMeta = const VerificationMeta(
    'isHidden',
  );
  @override
  late final GeneratedColumn<bool> isHidden = GeneratedColumn<bool>(
    'is_hidden',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_hidden" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _taskIdMeta = const VerificationMeta('taskId');
  @override
  late final GeneratedColumn<String> taskId = GeneratedColumn<String>(
    'task_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _taskNameMeta = const VerificationMeta(
    'taskName',
  );
  @override
  late final GeneratedColumn<String> taskName = GeneratedColumn<String>(
    'task_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _subtaskIdMeta = const VerificationMeta(
    'subtaskId',
  );
  @override
  late final GeneratedColumn<String> subtaskId = GeneratedColumn<String>(
    'subtask_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _subtaskNameMeta = const VerificationMeta(
    'subtaskName',
  );
  @override
  late final GeneratedColumn<String> subtaskName = GeneratedColumn<String>(
    'subtask_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    filepath,
    filesize,
    durationMs,
    thumnbnail,
    metadataFilepath,
    status,
    fileName,
    mimeType,
    progress,
    retryCount,
    s3PresignResponse,
    multipartStartResponse,
    partUrls,
    uploadedParts,
    partsCount,
    createdAt,
    updatedAt,
    isHidden,
    taskId,
    taskName,
    subtaskId,
    subtaskName,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'uploads';
  @override
  VerificationContext validateIntegrity(
    Insertable<Upload> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('filepath')) {
      context.handle(
        _filepathMeta,
        filepath.isAcceptableOrUnknown(data['filepath']!, _filepathMeta),
      );
    } else if (isInserting) {
      context.missing(_filepathMeta);
    }
    if (data.containsKey('filesize')) {
      context.handle(
        _filesizeMeta,
        filesize.isAcceptableOrUnknown(data['filesize']!, _filesizeMeta),
      );
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    }
    if (data.containsKey('thumnbnail')) {
      context.handle(
        _thumnbnailMeta,
        thumnbnail.isAcceptableOrUnknown(data['thumnbnail']!, _thumnbnailMeta),
      );
    }
    if (data.containsKey('metadata_filepath')) {
      context.handle(
        _metadataFilepathMeta,
        metadataFilepath.isAcceptableOrUnknown(
          data['metadata_filepath']!,
          _metadataFilepathMeta,
        ),
      );
    }
    if (data.containsKey('file_name')) {
      context.handle(
        _fileNameMeta,
        fileName.isAcceptableOrUnknown(data['file_name']!, _fileNameMeta),
      );
    }
    if (data.containsKey('mime_type')) {
      context.handle(
        _mimeTypeMeta,
        mimeType.isAcceptableOrUnknown(data['mime_type']!, _mimeTypeMeta),
      );
    }
    if (data.containsKey('progress')) {
      context.handle(
        _progressMeta,
        progress.isAcceptableOrUnknown(data['progress']!, _progressMeta),
      );
    }
    if (data.containsKey('retry_count')) {
      context.handle(
        _retryCountMeta,
        retryCount.isAcceptableOrUnknown(data['retry_count']!, _retryCountMeta),
      );
    }
    if (data.containsKey('parts_count')) {
      context.handle(
        _partsCountMeta,
        partsCount.isAcceptableOrUnknown(data['parts_count']!, _partsCountMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('is_hidden')) {
      context.handle(
        _isHiddenMeta,
        isHidden.isAcceptableOrUnknown(data['is_hidden']!, _isHiddenMeta),
      );
    }
    if (data.containsKey('task_id')) {
      context.handle(
        _taskIdMeta,
        taskId.isAcceptableOrUnknown(data['task_id']!, _taskIdMeta),
      );
    }
    if (data.containsKey('task_name')) {
      context.handle(
        _taskNameMeta,
        taskName.isAcceptableOrUnknown(data['task_name']!, _taskNameMeta),
      );
    }
    if (data.containsKey('subtask_id')) {
      context.handle(
        _subtaskIdMeta,
        subtaskId.isAcceptableOrUnknown(data['subtask_id']!, _subtaskIdMeta),
      );
    }
    if (data.containsKey('subtask_name')) {
      context.handle(
        _subtaskNameMeta,
        subtaskName.isAcceptableOrUnknown(
          data['subtask_name']!,
          _subtaskNameMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Upload map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Upload(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      filepath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}filepath'],
      )!,
      filesize: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}filesize'],
      ),
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      ),
      thumnbnail: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}thumnbnail'],
      ),
      metadataFilepath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}metadata_filepath'],
      ),
      status: $UploadsTable.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}status'],
        )!,
      ),
      fileName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_name'],
      ),
      mimeType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mime_type'],
      ),
      progress: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}progress'],
      ),
      retryCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}retry_count'],
      )!,
      s3PresignResponse: $UploadsTable.$converters3PresignResponsen.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}s3_presign_response'],
        ),
      ),
      multipartStartResponse: $UploadsTable.$convertermultipartStartResponsen
          .fromSql(
            attachedDatabase.typeMapping.read(
              DriftSqlType.string,
              data['${effectivePrefix}multipart_start_response'],
            ),
          ),
      partUrls: $UploadsTable.$converterpartUrlsn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}part_urls'],
        ),
      ),
      uploadedParts: $UploadsTable.$converteruploadedPartsn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}uploaded_parts'],
        ),
      ),
      partsCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}parts_count'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      isHidden: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_hidden'],
      )!,
      taskId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}task_id'],
      ),
      taskName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}task_name'],
      ),
      subtaskId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}subtask_id'],
      ),
      subtaskName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}subtask_name'],
      ),
    );
  }

  @override
  $UploadsTable createAlias(String alias) {
    return $UploadsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<UploadStatus, String, String> $converterstatus =
      const EnumNameConverter<UploadStatus>(UploadStatus.values);
  static TypeConverter<S3PresignResponse, String> $converters3PresignResponse =
      const S3PresignResponseTypeConverter();
  static TypeConverter<S3PresignResponse?, String?>
  $converters3PresignResponsen = NullAwareTypeConverter.wrap(
    $converters3PresignResponse,
  );
  static TypeConverter<MultipartStartResponse, String>
  $convertermultipartStartResponse =
      const MultipartStartResponseTypeConverter();
  static TypeConverter<MultipartStartResponse?, String?>
  $convertermultipartStartResponsen = NullAwareTypeConverter.wrap(
    $convertermultipartStartResponse,
  );
  static TypeConverter<List<PartUrl>, String> $converterpartUrls =
      const PartUrlListTypeConverter();
  static TypeConverter<List<PartUrl>?, String?> $converterpartUrlsn =
      NullAwareTypeConverter.wrap($converterpartUrls);
  static TypeConverter<List<UploadedPart>, String> $converteruploadedParts =
      const UploadedPartsConverter();
  static TypeConverter<List<UploadedPart>?, String?> $converteruploadedPartsn =
      NullAwareTypeConverter.wrap($converteruploadedParts);
}

class Upload extends DataClass implements Insertable<Upload> {
  final int id;
  final String filepath;
  final int? filesize;
  final int? durationMs;
  final String? thumnbnail;
  final String? metadataFilepath;
  final UploadStatus status;
  final String? fileName;
  final String? mimeType;
  final double? progress;
  final int retryCount;
  final S3PresignResponse? s3PresignResponse;
  final MultipartStartResponse? multipartStartResponse;
  final List<PartUrl>? partUrls;
  final List<UploadedPart>? uploadedParts;
  final int? partsCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isHidden;
  final String? taskId;
  final String? taskName;
  final String? subtaskId;
  final String? subtaskName;
  const Upload({
    required this.id,
    required this.filepath,
    this.filesize,
    this.durationMs,
    this.thumnbnail,
    this.metadataFilepath,
    required this.status,
    this.fileName,
    this.mimeType,
    this.progress,
    required this.retryCount,
    this.s3PresignResponse,
    this.multipartStartResponse,
    this.partUrls,
    this.uploadedParts,
    this.partsCount,
    required this.createdAt,
    required this.updatedAt,
    required this.isHidden,
    this.taskId,
    this.taskName,
    this.subtaskId,
    this.subtaskName,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['filepath'] = Variable<String>(filepath);
    if (!nullToAbsent || filesize != null) {
      map['filesize'] = Variable<int>(filesize);
    }
    if (!nullToAbsent || durationMs != null) {
      map['duration_ms'] = Variable<int>(durationMs);
    }
    if (!nullToAbsent || thumnbnail != null) {
      map['thumnbnail'] = Variable<String>(thumnbnail);
    }
    if (!nullToAbsent || metadataFilepath != null) {
      map['metadata_filepath'] = Variable<String>(metadataFilepath);
    }
    {
      map['status'] = Variable<String>(
        $UploadsTable.$converterstatus.toSql(status),
      );
    }
    if (!nullToAbsent || fileName != null) {
      map['file_name'] = Variable<String>(fileName);
    }
    if (!nullToAbsent || mimeType != null) {
      map['mime_type'] = Variable<String>(mimeType);
    }
    if (!nullToAbsent || progress != null) {
      map['progress'] = Variable<double>(progress);
    }
    map['retry_count'] = Variable<int>(retryCount);
    if (!nullToAbsent || s3PresignResponse != null) {
      map['s3_presign_response'] = Variable<String>(
        $UploadsTable.$converters3PresignResponsen.toSql(s3PresignResponse),
      );
    }
    if (!nullToAbsent || multipartStartResponse != null) {
      map['multipart_start_response'] = Variable<String>(
        $UploadsTable.$convertermultipartStartResponsen.toSql(
          multipartStartResponse,
        ),
      );
    }
    if (!nullToAbsent || partUrls != null) {
      map['part_urls'] = Variable<String>(
        $UploadsTable.$converterpartUrlsn.toSql(partUrls),
      );
    }
    if (!nullToAbsent || uploadedParts != null) {
      map['uploaded_parts'] = Variable<String>(
        $UploadsTable.$converteruploadedPartsn.toSql(uploadedParts),
      );
    }
    if (!nullToAbsent || partsCount != null) {
      map['parts_count'] = Variable<int>(partsCount);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['is_hidden'] = Variable<bool>(isHidden);
    if (!nullToAbsent || taskId != null) {
      map['task_id'] = Variable<String>(taskId);
    }
    if (!nullToAbsent || taskName != null) {
      map['task_name'] = Variable<String>(taskName);
    }
    if (!nullToAbsent || subtaskId != null) {
      map['subtask_id'] = Variable<String>(subtaskId);
    }
    if (!nullToAbsent || subtaskName != null) {
      map['subtask_name'] = Variable<String>(subtaskName);
    }
    return map;
  }

  UploadsCompanion toCompanion(bool nullToAbsent) {
    return UploadsCompanion(
      id: Value(id),
      filepath: Value(filepath),
      filesize: filesize == null && nullToAbsent
          ? const Value.absent()
          : Value(filesize),
      durationMs: durationMs == null && nullToAbsent
          ? const Value.absent()
          : Value(durationMs),
      thumnbnail: thumnbnail == null && nullToAbsent
          ? const Value.absent()
          : Value(thumnbnail),
      metadataFilepath: metadataFilepath == null && nullToAbsent
          ? const Value.absent()
          : Value(metadataFilepath),
      status: Value(status),
      fileName: fileName == null && nullToAbsent
          ? const Value.absent()
          : Value(fileName),
      mimeType: mimeType == null && nullToAbsent
          ? const Value.absent()
          : Value(mimeType),
      progress: progress == null && nullToAbsent
          ? const Value.absent()
          : Value(progress),
      retryCount: Value(retryCount),
      s3PresignResponse: s3PresignResponse == null && nullToAbsent
          ? const Value.absent()
          : Value(s3PresignResponse),
      multipartStartResponse: multipartStartResponse == null && nullToAbsent
          ? const Value.absent()
          : Value(multipartStartResponse),
      partUrls: partUrls == null && nullToAbsent
          ? const Value.absent()
          : Value(partUrls),
      uploadedParts: uploadedParts == null && nullToAbsent
          ? const Value.absent()
          : Value(uploadedParts),
      partsCount: partsCount == null && nullToAbsent
          ? const Value.absent()
          : Value(partsCount),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      isHidden: Value(isHidden),
      taskId: taskId == null && nullToAbsent
          ? const Value.absent()
          : Value(taskId),
      taskName: taskName == null && nullToAbsent
          ? const Value.absent()
          : Value(taskName),
      subtaskId: subtaskId == null && nullToAbsent
          ? const Value.absent()
          : Value(subtaskId),
      subtaskName: subtaskName == null && nullToAbsent
          ? const Value.absent()
          : Value(subtaskName),
    );
  }

  factory Upload.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Upload(
      id: serializer.fromJson<int>(json['id']),
      filepath: serializer.fromJson<String>(json['filepath']),
      filesize: serializer.fromJson<int?>(json['filesize']),
      durationMs: serializer.fromJson<int?>(json['durationMs']),
      thumnbnail: serializer.fromJson<String?>(json['thumnbnail']),
      metadataFilepath: serializer.fromJson<String?>(json['metadataFilepath']),
      status: $UploadsTable.$converterstatus.fromJson(
        serializer.fromJson<String>(json['status']),
      ),
      fileName: serializer.fromJson<String?>(json['fileName']),
      mimeType: serializer.fromJson<String?>(json['mimeType']),
      progress: serializer.fromJson<double?>(json['progress']),
      retryCount: serializer.fromJson<int>(json['retryCount']),
      s3PresignResponse: serializer.fromJson<S3PresignResponse?>(
        json['s3PresignResponse'],
      ),
      multipartStartResponse: serializer.fromJson<MultipartStartResponse?>(
        json['multipartStartResponse'],
      ),
      partUrls: serializer.fromJson<List<PartUrl>?>(json['partUrls']),
      uploadedParts: serializer.fromJson<List<UploadedPart>?>(
        json['uploadedParts'],
      ),
      partsCount: serializer.fromJson<int?>(json['partsCount']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      isHidden: serializer.fromJson<bool>(json['isHidden']),
      taskId: serializer.fromJson<String?>(json['taskId']),
      taskName: serializer.fromJson<String?>(json['taskName']),
      subtaskId: serializer.fromJson<String?>(json['subtaskId']),
      subtaskName: serializer.fromJson<String?>(json['subtaskName']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'filepath': serializer.toJson<String>(filepath),
      'filesize': serializer.toJson<int?>(filesize),
      'durationMs': serializer.toJson<int?>(durationMs),
      'thumnbnail': serializer.toJson<String?>(thumnbnail),
      'metadataFilepath': serializer.toJson<String?>(metadataFilepath),
      'status': serializer.toJson<String>(
        $UploadsTable.$converterstatus.toJson(status),
      ),
      'fileName': serializer.toJson<String?>(fileName),
      'mimeType': serializer.toJson<String?>(mimeType),
      'progress': serializer.toJson<double?>(progress),
      'retryCount': serializer.toJson<int>(retryCount),
      's3PresignResponse': serializer.toJson<S3PresignResponse?>(
        s3PresignResponse,
      ),
      'multipartStartResponse': serializer.toJson<MultipartStartResponse?>(
        multipartStartResponse,
      ),
      'partUrls': serializer.toJson<List<PartUrl>?>(partUrls),
      'uploadedParts': serializer.toJson<List<UploadedPart>?>(uploadedParts),
      'partsCount': serializer.toJson<int?>(partsCount),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'isHidden': serializer.toJson<bool>(isHidden),
      'taskId': serializer.toJson<String?>(taskId),
      'taskName': serializer.toJson<String?>(taskName),
      'subtaskId': serializer.toJson<String?>(subtaskId),
      'subtaskName': serializer.toJson<String?>(subtaskName),
    };
  }

  Upload copyWith({
    int? id,
    String? filepath,
    Value<int?> filesize = const Value.absent(),
    Value<int?> durationMs = const Value.absent(),
    Value<String?> thumnbnail = const Value.absent(),
    Value<String?> metadataFilepath = const Value.absent(),
    UploadStatus? status,
    Value<String?> fileName = const Value.absent(),
    Value<String?> mimeType = const Value.absent(),
    Value<double?> progress = const Value.absent(),
    int? retryCount,
    Value<S3PresignResponse?> s3PresignResponse = const Value.absent(),
    Value<MultipartStartResponse?> multipartStartResponse =
        const Value.absent(),
    Value<List<PartUrl>?> partUrls = const Value.absent(),
    Value<List<UploadedPart>?> uploadedParts = const Value.absent(),
    Value<int?> partsCount = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isHidden,
    Value<String?> taskId = const Value.absent(),
    Value<String?> taskName = const Value.absent(),
    Value<String?> subtaskId = const Value.absent(),
    Value<String?> subtaskName = const Value.absent(),
  }) => Upload(
    id: id ?? this.id,
    filepath: filepath ?? this.filepath,
    filesize: filesize.present ? filesize.value : this.filesize,
    durationMs: durationMs.present ? durationMs.value : this.durationMs,
    thumnbnail: thumnbnail.present ? thumnbnail.value : this.thumnbnail,
    metadataFilepath: metadataFilepath.present
        ? metadataFilepath.value
        : this.metadataFilepath,
    status: status ?? this.status,
    fileName: fileName.present ? fileName.value : this.fileName,
    mimeType: mimeType.present ? mimeType.value : this.mimeType,
    progress: progress.present ? progress.value : this.progress,
    retryCount: retryCount ?? this.retryCount,
    s3PresignResponse: s3PresignResponse.present
        ? s3PresignResponse.value
        : this.s3PresignResponse,
    multipartStartResponse: multipartStartResponse.present
        ? multipartStartResponse.value
        : this.multipartStartResponse,
    partUrls: partUrls.present ? partUrls.value : this.partUrls,
    uploadedParts: uploadedParts.present
        ? uploadedParts.value
        : this.uploadedParts,
    partsCount: partsCount.present ? partsCount.value : this.partsCount,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    isHidden: isHidden ?? this.isHidden,
    taskId: taskId.present ? taskId.value : this.taskId,
    taskName: taskName.present ? taskName.value : this.taskName,
    subtaskId: subtaskId.present ? subtaskId.value : this.subtaskId,
    subtaskName: subtaskName.present ? subtaskName.value : this.subtaskName,
  );
  Upload copyWithCompanion(UploadsCompanion data) {
    return Upload(
      id: data.id.present ? data.id.value : this.id,
      filepath: data.filepath.present ? data.filepath.value : this.filepath,
      filesize: data.filesize.present ? data.filesize.value : this.filesize,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      thumnbnail: data.thumnbnail.present
          ? data.thumnbnail.value
          : this.thumnbnail,
      metadataFilepath: data.metadataFilepath.present
          ? data.metadataFilepath.value
          : this.metadataFilepath,
      status: data.status.present ? data.status.value : this.status,
      fileName: data.fileName.present ? data.fileName.value : this.fileName,
      mimeType: data.mimeType.present ? data.mimeType.value : this.mimeType,
      progress: data.progress.present ? data.progress.value : this.progress,
      retryCount: data.retryCount.present
          ? data.retryCount.value
          : this.retryCount,
      s3PresignResponse: data.s3PresignResponse.present
          ? data.s3PresignResponse.value
          : this.s3PresignResponse,
      multipartStartResponse: data.multipartStartResponse.present
          ? data.multipartStartResponse.value
          : this.multipartStartResponse,
      partUrls: data.partUrls.present ? data.partUrls.value : this.partUrls,
      uploadedParts: data.uploadedParts.present
          ? data.uploadedParts.value
          : this.uploadedParts,
      partsCount: data.partsCount.present
          ? data.partsCount.value
          : this.partsCount,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      isHidden: data.isHidden.present ? data.isHidden.value : this.isHidden,
      taskId: data.taskId.present ? data.taskId.value : this.taskId,
      taskName: data.taskName.present ? data.taskName.value : this.taskName,
      subtaskId: data.subtaskId.present ? data.subtaskId.value : this.subtaskId,
      subtaskName: data.subtaskName.present
          ? data.subtaskName.value
          : this.subtaskName,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Upload(')
          ..write('id: $id, ')
          ..write('filepath: $filepath, ')
          ..write('filesize: $filesize, ')
          ..write('durationMs: $durationMs, ')
          ..write('thumnbnail: $thumnbnail, ')
          ..write('metadataFilepath: $metadataFilepath, ')
          ..write('status: $status, ')
          ..write('fileName: $fileName, ')
          ..write('mimeType: $mimeType, ')
          ..write('progress: $progress, ')
          ..write('retryCount: $retryCount, ')
          ..write('s3PresignResponse: $s3PresignResponse, ')
          ..write('multipartStartResponse: $multipartStartResponse, ')
          ..write('partUrls: $partUrls, ')
          ..write('uploadedParts: $uploadedParts, ')
          ..write('partsCount: $partsCount, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('isHidden: $isHidden, ')
          ..write('taskId: $taskId, ')
          ..write('taskName: $taskName, ')
          ..write('subtaskId: $subtaskId, ')
          ..write('subtaskName: $subtaskName')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    filepath,
    filesize,
    durationMs,
    thumnbnail,
    metadataFilepath,
    status,
    fileName,
    mimeType,
    progress,
    retryCount,
    s3PresignResponse,
    multipartStartResponse,
    partUrls,
    uploadedParts,
    partsCount,
    createdAt,
    updatedAt,
    isHidden,
    taskId,
    taskName,
    subtaskId,
    subtaskName,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Upload &&
          other.id == this.id &&
          other.filepath == this.filepath &&
          other.filesize == this.filesize &&
          other.durationMs == this.durationMs &&
          other.thumnbnail == this.thumnbnail &&
          other.metadataFilepath == this.metadataFilepath &&
          other.status == this.status &&
          other.fileName == this.fileName &&
          other.mimeType == this.mimeType &&
          other.progress == this.progress &&
          other.retryCount == this.retryCount &&
          other.s3PresignResponse == this.s3PresignResponse &&
          other.multipartStartResponse == this.multipartStartResponse &&
          other.partUrls == this.partUrls &&
          other.uploadedParts == this.uploadedParts &&
          other.partsCount == this.partsCount &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.isHidden == this.isHidden &&
          other.taskId == this.taskId &&
          other.taskName == this.taskName &&
          other.subtaskId == this.subtaskId &&
          other.subtaskName == this.subtaskName);
}

class UploadsCompanion extends UpdateCompanion<Upload> {
  final Value<int> id;
  final Value<String> filepath;
  final Value<int?> filesize;
  final Value<int?> durationMs;
  final Value<String?> thumnbnail;
  final Value<String?> metadataFilepath;
  final Value<UploadStatus> status;
  final Value<String?> fileName;
  final Value<String?> mimeType;
  final Value<double?> progress;
  final Value<int> retryCount;
  final Value<S3PresignResponse?> s3PresignResponse;
  final Value<MultipartStartResponse?> multipartStartResponse;
  final Value<List<PartUrl>?> partUrls;
  final Value<List<UploadedPart>?> uploadedParts;
  final Value<int?> partsCount;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<bool> isHidden;
  final Value<String?> taskId;
  final Value<String?> taskName;
  final Value<String?> subtaskId;
  final Value<String?> subtaskName;
  const UploadsCompanion({
    this.id = const Value.absent(),
    this.filepath = const Value.absent(),
    this.filesize = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.thumnbnail = const Value.absent(),
    this.metadataFilepath = const Value.absent(),
    this.status = const Value.absent(),
    this.fileName = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.progress = const Value.absent(),
    this.retryCount = const Value.absent(),
    this.s3PresignResponse = const Value.absent(),
    this.multipartStartResponse = const Value.absent(),
    this.partUrls = const Value.absent(),
    this.uploadedParts = const Value.absent(),
    this.partsCount = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.isHidden = const Value.absent(),
    this.taskId = const Value.absent(),
    this.taskName = const Value.absent(),
    this.subtaskId = const Value.absent(),
    this.subtaskName = const Value.absent(),
  });
  UploadsCompanion.insert({
    this.id = const Value.absent(),
    required String filepath,
    this.filesize = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.thumnbnail = const Value.absent(),
    this.metadataFilepath = const Value.absent(),
    this.status = const Value.absent(),
    this.fileName = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.progress = const Value.absent(),
    this.retryCount = const Value.absent(),
    this.s3PresignResponse = const Value.absent(),
    this.multipartStartResponse = const Value.absent(),
    this.partUrls = const Value.absent(),
    this.uploadedParts = const Value.absent(),
    this.partsCount = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.isHidden = const Value.absent(),
    this.taskId = const Value.absent(),
    this.taskName = const Value.absent(),
    this.subtaskId = const Value.absent(),
    this.subtaskName = const Value.absent(),
  }) : filepath = Value(filepath);
  static Insertable<Upload> custom({
    Expression<int>? id,
    Expression<String>? filepath,
    Expression<int>? filesize,
    Expression<int>? durationMs,
    Expression<String>? thumnbnail,
    Expression<String>? metadataFilepath,
    Expression<String>? status,
    Expression<String>? fileName,
    Expression<String>? mimeType,
    Expression<double>? progress,
    Expression<int>? retryCount,
    Expression<String>? s3PresignResponse,
    Expression<String>? multipartStartResponse,
    Expression<String>? partUrls,
    Expression<String>? uploadedParts,
    Expression<int>? partsCount,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<bool>? isHidden,
    Expression<String>? taskId,
    Expression<String>? taskName,
    Expression<String>? subtaskId,
    Expression<String>? subtaskName,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (filepath != null) 'filepath': filepath,
      if (filesize != null) 'filesize': filesize,
      if (durationMs != null) 'duration_ms': durationMs,
      if (thumnbnail != null) 'thumnbnail': thumnbnail,
      if (metadataFilepath != null) 'metadata_filepath': metadataFilepath,
      if (status != null) 'status': status,
      if (fileName != null) 'file_name': fileName,
      if (mimeType != null) 'mime_type': mimeType,
      if (progress != null) 'progress': progress,
      if (retryCount != null) 'retry_count': retryCount,
      if (s3PresignResponse != null) 's3_presign_response': s3PresignResponse,
      if (multipartStartResponse != null)
        'multipart_start_response': multipartStartResponse,
      if (partUrls != null) 'part_urls': partUrls,
      if (uploadedParts != null) 'uploaded_parts': uploadedParts,
      if (partsCount != null) 'parts_count': partsCount,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (isHidden != null) 'is_hidden': isHidden,
      if (taskId != null) 'task_id': taskId,
      if (taskName != null) 'task_name': taskName,
      if (subtaskId != null) 'subtask_id': subtaskId,
      if (subtaskName != null) 'subtask_name': subtaskName,
    });
  }

  UploadsCompanion copyWith({
    Value<int>? id,
    Value<String>? filepath,
    Value<int?>? filesize,
    Value<int?>? durationMs,
    Value<String?>? thumnbnail,
    Value<String?>? metadataFilepath,
    Value<UploadStatus>? status,
    Value<String?>? fileName,
    Value<String?>? mimeType,
    Value<double?>? progress,
    Value<int>? retryCount,
    Value<S3PresignResponse?>? s3PresignResponse,
    Value<MultipartStartResponse?>? multipartStartResponse,
    Value<List<PartUrl>?>? partUrls,
    Value<List<UploadedPart>?>? uploadedParts,
    Value<int?>? partsCount,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<bool>? isHidden,
    Value<String?>? taskId,
    Value<String?>? taskName,
    Value<String?>? subtaskId,
    Value<String?>? subtaskName,
  }) {
    return UploadsCompanion(
      id: id ?? this.id,
      filepath: filepath ?? this.filepath,
      filesize: filesize ?? this.filesize,
      durationMs: durationMs ?? this.durationMs,
      thumnbnail: thumnbnail ?? this.thumnbnail,
      metadataFilepath: metadataFilepath ?? this.metadataFilepath,
      status: status ?? this.status,
      fileName: fileName ?? this.fileName,
      mimeType: mimeType ?? this.mimeType,
      progress: progress ?? this.progress,
      retryCount: retryCount ?? this.retryCount,
      s3PresignResponse: s3PresignResponse ?? this.s3PresignResponse,
      multipartStartResponse:
          multipartStartResponse ?? this.multipartStartResponse,
      partUrls: partUrls ?? this.partUrls,
      uploadedParts: uploadedParts ?? this.uploadedParts,
      partsCount: partsCount ?? this.partsCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isHidden: isHidden ?? this.isHidden,
      taskId: taskId ?? this.taskId,
      taskName: taskName ?? this.taskName,
      subtaskId: subtaskId ?? this.subtaskId,
      subtaskName: subtaskName ?? this.subtaskName,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (filepath.present) {
      map['filepath'] = Variable<String>(filepath.value);
    }
    if (filesize.present) {
      map['filesize'] = Variable<int>(filesize.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (thumnbnail.present) {
      map['thumnbnail'] = Variable<String>(thumnbnail.value);
    }
    if (metadataFilepath.present) {
      map['metadata_filepath'] = Variable<String>(metadataFilepath.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(
        $UploadsTable.$converterstatus.toSql(status.value),
      );
    }
    if (fileName.present) {
      map['file_name'] = Variable<String>(fileName.value);
    }
    if (mimeType.present) {
      map['mime_type'] = Variable<String>(mimeType.value);
    }
    if (progress.present) {
      map['progress'] = Variable<double>(progress.value);
    }
    if (retryCount.present) {
      map['retry_count'] = Variable<int>(retryCount.value);
    }
    if (s3PresignResponse.present) {
      map['s3_presign_response'] = Variable<String>(
        $UploadsTable.$converters3PresignResponsen.toSql(
          s3PresignResponse.value,
        ),
      );
    }
    if (multipartStartResponse.present) {
      map['multipart_start_response'] = Variable<String>(
        $UploadsTable.$convertermultipartStartResponsen.toSql(
          multipartStartResponse.value,
        ),
      );
    }
    if (partUrls.present) {
      map['part_urls'] = Variable<String>(
        $UploadsTable.$converterpartUrlsn.toSql(partUrls.value),
      );
    }
    if (uploadedParts.present) {
      map['uploaded_parts'] = Variable<String>(
        $UploadsTable.$converteruploadedPartsn.toSql(uploadedParts.value),
      );
    }
    if (partsCount.present) {
      map['parts_count'] = Variable<int>(partsCount.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (isHidden.present) {
      map['is_hidden'] = Variable<bool>(isHidden.value);
    }
    if (taskId.present) {
      map['task_id'] = Variable<String>(taskId.value);
    }
    if (taskName.present) {
      map['task_name'] = Variable<String>(taskName.value);
    }
    if (subtaskId.present) {
      map['subtask_id'] = Variable<String>(subtaskId.value);
    }
    if (subtaskName.present) {
      map['subtask_name'] = Variable<String>(subtaskName.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UploadsCompanion(')
          ..write('id: $id, ')
          ..write('filepath: $filepath, ')
          ..write('filesize: $filesize, ')
          ..write('durationMs: $durationMs, ')
          ..write('thumnbnail: $thumnbnail, ')
          ..write('metadataFilepath: $metadataFilepath, ')
          ..write('status: $status, ')
          ..write('fileName: $fileName, ')
          ..write('mimeType: $mimeType, ')
          ..write('progress: $progress, ')
          ..write('retryCount: $retryCount, ')
          ..write('s3PresignResponse: $s3PresignResponse, ')
          ..write('multipartStartResponse: $multipartStartResponse, ')
          ..write('partUrls: $partUrls, ')
          ..write('uploadedParts: $uploadedParts, ')
          ..write('partsCount: $partsCount, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('isHidden: $isHidden, ')
          ..write('taskId: $taskId, ')
          ..write('taskName: $taskName, ')
          ..write('subtaskId: $subtaskId, ')
          ..write('subtaskName: $subtaskName')
          ..write(')'))
        .toString();
  }
}

class $UploadSessionsTable extends UploadSessions
    with TableInfo<$UploadSessionsTable, UploadSession> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UploadSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _filepathMeta = const VerificationMeta(
    'filepath',
  );
  @override
  late final GeneratedColumn<String> filepath = GeneratedColumn<String>(
    'filepath',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fileSizeMeta = const VerificationMeta(
    'fileSize',
  );
  @override
  late final GeneratedColumn<int> fileSize = GeneratedColumn<int>(
    'file_size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fileNameMeta = const VerificationMeta(
    'fileName',
  );
  @override
  late final GeneratedColumn<String> fileName = GeneratedColumn<String>(
    'file_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mimeTypeMeta = const VerificationMeta(
    'mimeType',
  );
  @override
  late final GeneratedColumn<String> mimeType = GeneratedColumn<String>(
    'mime_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _thumbnailPathMeta = const VerificationMeta(
    'thumbnailPath',
  );
  @override
  late final GeneratedColumn<String> thumbnailPath = GeneratedColumn<String>(
    'thumbnail_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _metadataFilepathMeta = const VerificationMeta(
    'metadataFilepath',
  );
  @override
  late final GeneratedColumn<String> metadataFilepath = GeneratedColumn<String>(
    'metadata_filepath',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _chunkSizeMeta = const VerificationMeta(
    'chunkSize',
  );
  @override
  late final GeneratedColumn<int> chunkSize = GeneratedColumn<int>(
    'chunk_size',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _partCountMeta = const VerificationMeta(
    'partCount',
  );
  @override
  late final GeneratedColumn<int> partCount = GeneratedColumn<int>(
    'part_count',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _s3KeyMeta = const VerificationMeta('s3Key');
  @override
  late final GeneratedColumn<String> s3Key = GeneratedColumn<String>(
    's3_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _s3UploadIdMeta = const VerificationMeta(
    's3UploadId',
  );
  @override
  late final GeneratedColumn<String> s3UploadId = GeneratedColumn<String>(
    's3_upload_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _assetIdMeta = const VerificationMeta(
    'assetId',
  );
  @override
  late final GeneratedColumn<String> assetId = GeneratedColumn<String>(
    'asset_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<SessionState, String> state =
      GeneratedColumn<String>(
        'state',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: Constant(SessionState.queued.name),
      ).withConverter<SessionState>($UploadSessionsTable.$converterstate);
  static const VerificationMeta _lastErrorCodeMeta = const VerificationMeta(
    'lastErrorCode',
  );
  @override
  late final GeneratedColumn<String> lastErrorCode = GeneratedColumn<String>(
    'last_error_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastErrorDetailMeta = const VerificationMeta(
    'lastErrorDetail',
  );
  @override
  late final GeneratedColumn<String> lastErrorDetail = GeneratedColumn<String>(
    'last_error_detail',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _attemptsWithoutProgressMeta =
      const VerificationMeta('attemptsWithoutProgress');
  @override
  late final GeneratedColumn<int> attemptsWithoutProgress =
      GeneratedColumn<int>(
        'attempts_without_progress',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
        defaultValue: const Constant(0),
      );
  static const VerificationMeta _nextAttemptAtMeta = const VerificationMeta(
    'nextAttemptAt',
  );
  @override
  late final GeneratedColumn<DateTime> nextAttemptAt =
      GeneratedColumn<DateTime>(
        'next_attempt_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _fingerprintMeta = const VerificationMeta(
    'fingerprint',
  );
  @override
  late final GeneratedColumn<String> fingerprint = GeneratedColumn<String>(
    'fingerprint',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourceMtimeMeta = const VerificationMeta(
    'sourceMtime',
  );
  @override
  late final GeneratedColumn<DateTime> sourceMtime = GeneratedColumn<DateTime>(
    'source_mtime',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _taskIdMeta = const VerificationMeta('taskId');
  @override
  late final GeneratedColumn<String> taskId = GeneratedColumn<String>(
    'task_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _subtaskIdMeta = const VerificationMeta(
    'subtaskId',
  );
  @override
  late final GeneratedColumn<String> subtaskId = GeneratedColumn<String>(
    'subtask_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    filepath,
    fileSize,
    fileName,
    mimeType,
    durationMs,
    thumbnailPath,
    metadataFilepath,
    chunkSize,
    partCount,
    s3Key,
    s3UploadId,
    assetId,
    state,
    lastErrorCode,
    lastErrorDetail,
    attemptsWithoutProgress,
    nextAttemptAt,
    fingerprint,
    sourceMtime,
    createdAt,
    updatedAt,
    taskId,
    subtaskId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'upload_sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<UploadSession> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('filepath')) {
      context.handle(
        _filepathMeta,
        filepath.isAcceptableOrUnknown(data['filepath']!, _filepathMeta),
      );
    } else if (isInserting) {
      context.missing(_filepathMeta);
    }
    if (data.containsKey('file_size')) {
      context.handle(
        _fileSizeMeta,
        fileSize.isAcceptableOrUnknown(data['file_size']!, _fileSizeMeta),
      );
    } else if (isInserting) {
      context.missing(_fileSizeMeta);
    }
    if (data.containsKey('file_name')) {
      context.handle(
        _fileNameMeta,
        fileName.isAcceptableOrUnknown(data['file_name']!, _fileNameMeta),
      );
    } else if (isInserting) {
      context.missing(_fileNameMeta);
    }
    if (data.containsKey('mime_type')) {
      context.handle(
        _mimeTypeMeta,
        mimeType.isAcceptableOrUnknown(data['mime_type']!, _mimeTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_mimeTypeMeta);
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    }
    if (data.containsKey('thumbnail_path')) {
      context.handle(
        _thumbnailPathMeta,
        thumbnailPath.isAcceptableOrUnknown(
          data['thumbnail_path']!,
          _thumbnailPathMeta,
        ),
      );
    }
    if (data.containsKey('metadata_filepath')) {
      context.handle(
        _metadataFilepathMeta,
        metadataFilepath.isAcceptableOrUnknown(
          data['metadata_filepath']!,
          _metadataFilepathMeta,
        ),
      );
    }
    if (data.containsKey('chunk_size')) {
      context.handle(
        _chunkSizeMeta,
        chunkSize.isAcceptableOrUnknown(data['chunk_size']!, _chunkSizeMeta),
      );
    }
    if (data.containsKey('part_count')) {
      context.handle(
        _partCountMeta,
        partCount.isAcceptableOrUnknown(data['part_count']!, _partCountMeta),
      );
    }
    if (data.containsKey('s3_key')) {
      context.handle(
        _s3KeyMeta,
        s3Key.isAcceptableOrUnknown(data['s3_key']!, _s3KeyMeta),
      );
    }
    if (data.containsKey('s3_upload_id')) {
      context.handle(
        _s3UploadIdMeta,
        s3UploadId.isAcceptableOrUnknown(
          data['s3_upload_id']!,
          _s3UploadIdMeta,
        ),
      );
    }
    if (data.containsKey('asset_id')) {
      context.handle(
        _assetIdMeta,
        assetId.isAcceptableOrUnknown(data['asset_id']!, _assetIdMeta),
      );
    }
    if (data.containsKey('last_error_code')) {
      context.handle(
        _lastErrorCodeMeta,
        lastErrorCode.isAcceptableOrUnknown(
          data['last_error_code']!,
          _lastErrorCodeMeta,
        ),
      );
    }
    if (data.containsKey('last_error_detail')) {
      context.handle(
        _lastErrorDetailMeta,
        lastErrorDetail.isAcceptableOrUnknown(
          data['last_error_detail']!,
          _lastErrorDetailMeta,
        ),
      );
    }
    if (data.containsKey('attempts_without_progress')) {
      context.handle(
        _attemptsWithoutProgressMeta,
        attemptsWithoutProgress.isAcceptableOrUnknown(
          data['attempts_without_progress']!,
          _attemptsWithoutProgressMeta,
        ),
      );
    }
    if (data.containsKey('next_attempt_at')) {
      context.handle(
        _nextAttemptAtMeta,
        nextAttemptAt.isAcceptableOrUnknown(
          data['next_attempt_at']!,
          _nextAttemptAtMeta,
        ),
      );
    }
    if (data.containsKey('fingerprint')) {
      context.handle(
        _fingerprintMeta,
        fingerprint.isAcceptableOrUnknown(
          data['fingerprint']!,
          _fingerprintMeta,
        ),
      );
    }
    if (data.containsKey('source_mtime')) {
      context.handle(
        _sourceMtimeMeta,
        sourceMtime.isAcceptableOrUnknown(
          data['source_mtime']!,
          _sourceMtimeMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('task_id')) {
      context.handle(
        _taskIdMeta,
        taskId.isAcceptableOrUnknown(data['task_id']!, _taskIdMeta),
      );
    }
    if (data.containsKey('subtask_id')) {
      context.handle(
        _subtaskIdMeta,
        subtaskId.isAcceptableOrUnknown(data['subtask_id']!, _subtaskIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  UploadSession map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return UploadSession(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      filepath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}filepath'],
      )!,
      fileSize: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}file_size'],
      )!,
      fileName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_name'],
      )!,
      mimeType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mime_type'],
      )!,
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      ),
      thumbnailPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}thumbnail_path'],
      ),
      metadataFilepath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}metadata_filepath'],
      ),
      chunkSize: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}chunk_size'],
      ),
      partCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}part_count'],
      ),
      s3Key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}s3_key'],
      ),
      s3UploadId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}s3_upload_id'],
      ),
      assetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}asset_id'],
      ),
      state: $UploadSessionsTable.$converterstate.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}state'],
        )!,
      ),
      lastErrorCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error_code'],
      ),
      lastErrorDetail: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error_detail'],
      ),
      attemptsWithoutProgress: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts_without_progress'],
      )!,
      nextAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}next_attempt_at'],
      ),
      fingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fingerprint'],
      ),
      sourceMtime: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}source_mtime'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      taskId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}task_id'],
      ),
      subtaskId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}subtask_id'],
      ),
    );
  }

  @override
  $UploadSessionsTable createAlias(String alias) {
    return $UploadSessionsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<SessionState, String, String> $converterstate =
      const EnumNameConverter<SessionState>(SessionState.values);
}

class UploadSession extends DataClass implements Insertable<UploadSession> {
  /// uuid; doubles as the `clientUploadId` sent to the backend for /start
  /// idempotency.
  final String id;
  final String filepath;
  final int fileSize;
  final String fileName;
  final String mimeType;
  final int? durationMs;
  final String? thumbnailPath;
  final String? metadataFilepath;
  final int? chunkSize;
  final int? partCount;
  final String? s3Key;
  final String? s3UploadId;
  final String? assetId;
  final SessionState state;
  final String? lastErrorCode;
  final String? lastErrorDetail;
  final int attemptsWithoutProgress;
  final DateTime? nextAttemptAt;
  final String? fingerprint;
  final DateTime? sourceMtime;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? taskId;
  final String? subtaskId;
  const UploadSession({
    required this.id,
    required this.filepath,
    required this.fileSize,
    required this.fileName,
    required this.mimeType,
    this.durationMs,
    this.thumbnailPath,
    this.metadataFilepath,
    this.chunkSize,
    this.partCount,
    this.s3Key,
    this.s3UploadId,
    this.assetId,
    required this.state,
    this.lastErrorCode,
    this.lastErrorDetail,
    required this.attemptsWithoutProgress,
    this.nextAttemptAt,
    this.fingerprint,
    this.sourceMtime,
    required this.createdAt,
    required this.updatedAt,
    this.taskId,
    this.subtaskId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['filepath'] = Variable<String>(filepath);
    map['file_size'] = Variable<int>(fileSize);
    map['file_name'] = Variable<String>(fileName);
    map['mime_type'] = Variable<String>(mimeType);
    if (!nullToAbsent || durationMs != null) {
      map['duration_ms'] = Variable<int>(durationMs);
    }
    if (!nullToAbsent || thumbnailPath != null) {
      map['thumbnail_path'] = Variable<String>(thumbnailPath);
    }
    if (!nullToAbsent || metadataFilepath != null) {
      map['metadata_filepath'] = Variable<String>(metadataFilepath);
    }
    if (!nullToAbsent || chunkSize != null) {
      map['chunk_size'] = Variable<int>(chunkSize);
    }
    if (!nullToAbsent || partCount != null) {
      map['part_count'] = Variable<int>(partCount);
    }
    if (!nullToAbsent || s3Key != null) {
      map['s3_key'] = Variable<String>(s3Key);
    }
    if (!nullToAbsent || s3UploadId != null) {
      map['s3_upload_id'] = Variable<String>(s3UploadId);
    }
    if (!nullToAbsent || assetId != null) {
      map['asset_id'] = Variable<String>(assetId);
    }
    {
      map['state'] = Variable<String>(
        $UploadSessionsTable.$converterstate.toSql(state),
      );
    }
    if (!nullToAbsent || lastErrorCode != null) {
      map['last_error_code'] = Variable<String>(lastErrorCode);
    }
    if (!nullToAbsent || lastErrorDetail != null) {
      map['last_error_detail'] = Variable<String>(lastErrorDetail);
    }
    map['attempts_without_progress'] = Variable<int>(attemptsWithoutProgress);
    if (!nullToAbsent || nextAttemptAt != null) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt);
    }
    if (!nullToAbsent || fingerprint != null) {
      map['fingerprint'] = Variable<String>(fingerprint);
    }
    if (!nullToAbsent || sourceMtime != null) {
      map['source_mtime'] = Variable<DateTime>(sourceMtime);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || taskId != null) {
      map['task_id'] = Variable<String>(taskId);
    }
    if (!nullToAbsent || subtaskId != null) {
      map['subtask_id'] = Variable<String>(subtaskId);
    }
    return map;
  }

  UploadSessionsCompanion toCompanion(bool nullToAbsent) {
    return UploadSessionsCompanion(
      id: Value(id),
      filepath: Value(filepath),
      fileSize: Value(fileSize),
      fileName: Value(fileName),
      mimeType: Value(mimeType),
      durationMs: durationMs == null && nullToAbsent
          ? const Value.absent()
          : Value(durationMs),
      thumbnailPath: thumbnailPath == null && nullToAbsent
          ? const Value.absent()
          : Value(thumbnailPath),
      metadataFilepath: metadataFilepath == null && nullToAbsent
          ? const Value.absent()
          : Value(metadataFilepath),
      chunkSize: chunkSize == null && nullToAbsent
          ? const Value.absent()
          : Value(chunkSize),
      partCount: partCount == null && nullToAbsent
          ? const Value.absent()
          : Value(partCount),
      s3Key: s3Key == null && nullToAbsent
          ? const Value.absent()
          : Value(s3Key),
      s3UploadId: s3UploadId == null && nullToAbsent
          ? const Value.absent()
          : Value(s3UploadId),
      assetId: assetId == null && nullToAbsent
          ? const Value.absent()
          : Value(assetId),
      state: Value(state),
      lastErrorCode: lastErrorCode == null && nullToAbsent
          ? const Value.absent()
          : Value(lastErrorCode),
      lastErrorDetail: lastErrorDetail == null && nullToAbsent
          ? const Value.absent()
          : Value(lastErrorDetail),
      attemptsWithoutProgress: Value(attemptsWithoutProgress),
      nextAttemptAt: nextAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(nextAttemptAt),
      fingerprint: fingerprint == null && nullToAbsent
          ? const Value.absent()
          : Value(fingerprint),
      sourceMtime: sourceMtime == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceMtime),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      taskId: taskId == null && nullToAbsent
          ? const Value.absent()
          : Value(taskId),
      subtaskId: subtaskId == null && nullToAbsent
          ? const Value.absent()
          : Value(subtaskId),
    );
  }

  factory UploadSession.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return UploadSession(
      id: serializer.fromJson<String>(json['id']),
      filepath: serializer.fromJson<String>(json['filepath']),
      fileSize: serializer.fromJson<int>(json['fileSize']),
      fileName: serializer.fromJson<String>(json['fileName']),
      mimeType: serializer.fromJson<String>(json['mimeType']),
      durationMs: serializer.fromJson<int?>(json['durationMs']),
      thumbnailPath: serializer.fromJson<String?>(json['thumbnailPath']),
      metadataFilepath: serializer.fromJson<String?>(json['metadataFilepath']),
      chunkSize: serializer.fromJson<int?>(json['chunkSize']),
      partCount: serializer.fromJson<int?>(json['partCount']),
      s3Key: serializer.fromJson<String?>(json['s3Key']),
      s3UploadId: serializer.fromJson<String?>(json['s3UploadId']),
      assetId: serializer.fromJson<String?>(json['assetId']),
      state: $UploadSessionsTable.$converterstate.fromJson(
        serializer.fromJson<String>(json['state']),
      ),
      lastErrorCode: serializer.fromJson<String?>(json['lastErrorCode']),
      lastErrorDetail: serializer.fromJson<String?>(json['lastErrorDetail']),
      attemptsWithoutProgress: serializer.fromJson<int>(
        json['attemptsWithoutProgress'],
      ),
      nextAttemptAt: serializer.fromJson<DateTime?>(json['nextAttemptAt']),
      fingerprint: serializer.fromJson<String?>(json['fingerprint']),
      sourceMtime: serializer.fromJson<DateTime?>(json['sourceMtime']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      taskId: serializer.fromJson<String?>(json['taskId']),
      subtaskId: serializer.fromJson<String?>(json['subtaskId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'filepath': serializer.toJson<String>(filepath),
      'fileSize': serializer.toJson<int>(fileSize),
      'fileName': serializer.toJson<String>(fileName),
      'mimeType': serializer.toJson<String>(mimeType),
      'durationMs': serializer.toJson<int?>(durationMs),
      'thumbnailPath': serializer.toJson<String?>(thumbnailPath),
      'metadataFilepath': serializer.toJson<String?>(metadataFilepath),
      'chunkSize': serializer.toJson<int?>(chunkSize),
      'partCount': serializer.toJson<int?>(partCount),
      's3Key': serializer.toJson<String?>(s3Key),
      's3UploadId': serializer.toJson<String?>(s3UploadId),
      'assetId': serializer.toJson<String?>(assetId),
      'state': serializer.toJson<String>(
        $UploadSessionsTable.$converterstate.toJson(state),
      ),
      'lastErrorCode': serializer.toJson<String?>(lastErrorCode),
      'lastErrorDetail': serializer.toJson<String?>(lastErrorDetail),
      'attemptsWithoutProgress': serializer.toJson<int>(
        attemptsWithoutProgress,
      ),
      'nextAttemptAt': serializer.toJson<DateTime?>(nextAttemptAt),
      'fingerprint': serializer.toJson<String?>(fingerprint),
      'sourceMtime': serializer.toJson<DateTime?>(sourceMtime),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'taskId': serializer.toJson<String?>(taskId),
      'subtaskId': serializer.toJson<String?>(subtaskId),
    };
  }

  UploadSession copyWith({
    String? id,
    String? filepath,
    int? fileSize,
    String? fileName,
    String? mimeType,
    Value<int?> durationMs = const Value.absent(),
    Value<String?> thumbnailPath = const Value.absent(),
    Value<String?> metadataFilepath = const Value.absent(),
    Value<int?> chunkSize = const Value.absent(),
    Value<int?> partCount = const Value.absent(),
    Value<String?> s3Key = const Value.absent(),
    Value<String?> s3UploadId = const Value.absent(),
    Value<String?> assetId = const Value.absent(),
    SessionState? state,
    Value<String?> lastErrorCode = const Value.absent(),
    Value<String?> lastErrorDetail = const Value.absent(),
    int? attemptsWithoutProgress,
    Value<DateTime?> nextAttemptAt = const Value.absent(),
    Value<String?> fingerprint = const Value.absent(),
    Value<DateTime?> sourceMtime = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<String?> taskId = const Value.absent(),
    Value<String?> subtaskId = const Value.absent(),
  }) => UploadSession(
    id: id ?? this.id,
    filepath: filepath ?? this.filepath,
    fileSize: fileSize ?? this.fileSize,
    fileName: fileName ?? this.fileName,
    mimeType: mimeType ?? this.mimeType,
    durationMs: durationMs.present ? durationMs.value : this.durationMs,
    thumbnailPath: thumbnailPath.present
        ? thumbnailPath.value
        : this.thumbnailPath,
    metadataFilepath: metadataFilepath.present
        ? metadataFilepath.value
        : this.metadataFilepath,
    chunkSize: chunkSize.present ? chunkSize.value : this.chunkSize,
    partCount: partCount.present ? partCount.value : this.partCount,
    s3Key: s3Key.present ? s3Key.value : this.s3Key,
    s3UploadId: s3UploadId.present ? s3UploadId.value : this.s3UploadId,
    assetId: assetId.present ? assetId.value : this.assetId,
    state: state ?? this.state,
    lastErrorCode: lastErrorCode.present
        ? lastErrorCode.value
        : this.lastErrorCode,
    lastErrorDetail: lastErrorDetail.present
        ? lastErrorDetail.value
        : this.lastErrorDetail,
    attemptsWithoutProgress:
        attemptsWithoutProgress ?? this.attemptsWithoutProgress,
    nextAttemptAt: nextAttemptAt.present
        ? nextAttemptAt.value
        : this.nextAttemptAt,
    fingerprint: fingerprint.present ? fingerprint.value : this.fingerprint,
    sourceMtime: sourceMtime.present ? sourceMtime.value : this.sourceMtime,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    taskId: taskId.present ? taskId.value : this.taskId,
    subtaskId: subtaskId.present ? subtaskId.value : this.subtaskId,
  );
  UploadSession copyWithCompanion(UploadSessionsCompanion data) {
    return UploadSession(
      id: data.id.present ? data.id.value : this.id,
      filepath: data.filepath.present ? data.filepath.value : this.filepath,
      fileSize: data.fileSize.present ? data.fileSize.value : this.fileSize,
      fileName: data.fileName.present ? data.fileName.value : this.fileName,
      mimeType: data.mimeType.present ? data.mimeType.value : this.mimeType,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      thumbnailPath: data.thumbnailPath.present
          ? data.thumbnailPath.value
          : this.thumbnailPath,
      metadataFilepath: data.metadataFilepath.present
          ? data.metadataFilepath.value
          : this.metadataFilepath,
      chunkSize: data.chunkSize.present ? data.chunkSize.value : this.chunkSize,
      partCount: data.partCount.present ? data.partCount.value : this.partCount,
      s3Key: data.s3Key.present ? data.s3Key.value : this.s3Key,
      s3UploadId: data.s3UploadId.present
          ? data.s3UploadId.value
          : this.s3UploadId,
      assetId: data.assetId.present ? data.assetId.value : this.assetId,
      state: data.state.present ? data.state.value : this.state,
      lastErrorCode: data.lastErrorCode.present
          ? data.lastErrorCode.value
          : this.lastErrorCode,
      lastErrorDetail: data.lastErrorDetail.present
          ? data.lastErrorDetail.value
          : this.lastErrorDetail,
      attemptsWithoutProgress: data.attemptsWithoutProgress.present
          ? data.attemptsWithoutProgress.value
          : this.attemptsWithoutProgress,
      nextAttemptAt: data.nextAttemptAt.present
          ? data.nextAttemptAt.value
          : this.nextAttemptAt,
      fingerprint: data.fingerprint.present
          ? data.fingerprint.value
          : this.fingerprint,
      sourceMtime: data.sourceMtime.present
          ? data.sourceMtime.value
          : this.sourceMtime,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      taskId: data.taskId.present ? data.taskId.value : this.taskId,
      subtaskId: data.subtaskId.present ? data.subtaskId.value : this.subtaskId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('UploadSession(')
          ..write('id: $id, ')
          ..write('filepath: $filepath, ')
          ..write('fileSize: $fileSize, ')
          ..write('fileName: $fileName, ')
          ..write('mimeType: $mimeType, ')
          ..write('durationMs: $durationMs, ')
          ..write('thumbnailPath: $thumbnailPath, ')
          ..write('metadataFilepath: $metadataFilepath, ')
          ..write('chunkSize: $chunkSize, ')
          ..write('partCount: $partCount, ')
          ..write('s3Key: $s3Key, ')
          ..write('s3UploadId: $s3UploadId, ')
          ..write('assetId: $assetId, ')
          ..write('state: $state, ')
          ..write('lastErrorCode: $lastErrorCode, ')
          ..write('lastErrorDetail: $lastErrorDetail, ')
          ..write('attemptsWithoutProgress: $attemptsWithoutProgress, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('fingerprint: $fingerprint, ')
          ..write('sourceMtime: $sourceMtime, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('taskId: $taskId, ')
          ..write('subtaskId: $subtaskId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    filepath,
    fileSize,
    fileName,
    mimeType,
    durationMs,
    thumbnailPath,
    metadataFilepath,
    chunkSize,
    partCount,
    s3Key,
    s3UploadId,
    assetId,
    state,
    lastErrorCode,
    lastErrorDetail,
    attemptsWithoutProgress,
    nextAttemptAt,
    fingerprint,
    sourceMtime,
    createdAt,
    updatedAt,
    taskId,
    subtaskId,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UploadSession &&
          other.id == this.id &&
          other.filepath == this.filepath &&
          other.fileSize == this.fileSize &&
          other.fileName == this.fileName &&
          other.mimeType == this.mimeType &&
          other.durationMs == this.durationMs &&
          other.thumbnailPath == this.thumbnailPath &&
          other.metadataFilepath == this.metadataFilepath &&
          other.chunkSize == this.chunkSize &&
          other.partCount == this.partCount &&
          other.s3Key == this.s3Key &&
          other.s3UploadId == this.s3UploadId &&
          other.assetId == this.assetId &&
          other.state == this.state &&
          other.lastErrorCode == this.lastErrorCode &&
          other.lastErrorDetail == this.lastErrorDetail &&
          other.attemptsWithoutProgress == this.attemptsWithoutProgress &&
          other.nextAttemptAt == this.nextAttemptAt &&
          other.fingerprint == this.fingerprint &&
          other.sourceMtime == this.sourceMtime &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.taskId == this.taskId &&
          other.subtaskId == this.subtaskId);
}

class UploadSessionsCompanion extends UpdateCompanion<UploadSession> {
  final Value<String> id;
  final Value<String> filepath;
  final Value<int> fileSize;
  final Value<String> fileName;
  final Value<String> mimeType;
  final Value<int?> durationMs;
  final Value<String?> thumbnailPath;
  final Value<String?> metadataFilepath;
  final Value<int?> chunkSize;
  final Value<int?> partCount;
  final Value<String?> s3Key;
  final Value<String?> s3UploadId;
  final Value<String?> assetId;
  final Value<SessionState> state;
  final Value<String?> lastErrorCode;
  final Value<String?> lastErrorDetail;
  final Value<int> attemptsWithoutProgress;
  final Value<DateTime?> nextAttemptAt;
  final Value<String?> fingerprint;
  final Value<DateTime?> sourceMtime;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<String?> taskId;
  final Value<String?> subtaskId;
  final Value<int> rowid;
  const UploadSessionsCompanion({
    this.id = const Value.absent(),
    this.filepath = const Value.absent(),
    this.fileSize = const Value.absent(),
    this.fileName = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.thumbnailPath = const Value.absent(),
    this.metadataFilepath = const Value.absent(),
    this.chunkSize = const Value.absent(),
    this.partCount = const Value.absent(),
    this.s3Key = const Value.absent(),
    this.s3UploadId = const Value.absent(),
    this.assetId = const Value.absent(),
    this.state = const Value.absent(),
    this.lastErrorCode = const Value.absent(),
    this.lastErrorDetail = const Value.absent(),
    this.attemptsWithoutProgress = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.fingerprint = const Value.absent(),
    this.sourceMtime = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.taskId = const Value.absent(),
    this.subtaskId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  UploadSessionsCompanion.insert({
    required String id,
    required String filepath,
    required int fileSize,
    required String fileName,
    required String mimeType,
    this.durationMs = const Value.absent(),
    this.thumbnailPath = const Value.absent(),
    this.metadataFilepath = const Value.absent(),
    this.chunkSize = const Value.absent(),
    this.partCount = const Value.absent(),
    this.s3Key = const Value.absent(),
    this.s3UploadId = const Value.absent(),
    this.assetId = const Value.absent(),
    this.state = const Value.absent(),
    this.lastErrorCode = const Value.absent(),
    this.lastErrorDetail = const Value.absent(),
    this.attemptsWithoutProgress = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.fingerprint = const Value.absent(),
    this.sourceMtime = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.taskId = const Value.absent(),
    this.subtaskId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       filepath = Value(filepath),
       fileSize = Value(fileSize),
       fileName = Value(fileName),
       mimeType = Value(mimeType);
  static Insertable<UploadSession> custom({
    Expression<String>? id,
    Expression<String>? filepath,
    Expression<int>? fileSize,
    Expression<String>? fileName,
    Expression<String>? mimeType,
    Expression<int>? durationMs,
    Expression<String>? thumbnailPath,
    Expression<String>? metadataFilepath,
    Expression<int>? chunkSize,
    Expression<int>? partCount,
    Expression<String>? s3Key,
    Expression<String>? s3UploadId,
    Expression<String>? assetId,
    Expression<String>? state,
    Expression<String>? lastErrorCode,
    Expression<String>? lastErrorDetail,
    Expression<int>? attemptsWithoutProgress,
    Expression<DateTime>? nextAttemptAt,
    Expression<String>? fingerprint,
    Expression<DateTime>? sourceMtime,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<String>? taskId,
    Expression<String>? subtaskId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (filepath != null) 'filepath': filepath,
      if (fileSize != null) 'file_size': fileSize,
      if (fileName != null) 'file_name': fileName,
      if (mimeType != null) 'mime_type': mimeType,
      if (durationMs != null) 'duration_ms': durationMs,
      if (thumbnailPath != null) 'thumbnail_path': thumbnailPath,
      if (metadataFilepath != null) 'metadata_filepath': metadataFilepath,
      if (chunkSize != null) 'chunk_size': chunkSize,
      if (partCount != null) 'part_count': partCount,
      if (s3Key != null) 's3_key': s3Key,
      if (s3UploadId != null) 's3_upload_id': s3UploadId,
      if (assetId != null) 'asset_id': assetId,
      if (state != null) 'state': state,
      if (lastErrorCode != null) 'last_error_code': lastErrorCode,
      if (lastErrorDetail != null) 'last_error_detail': lastErrorDetail,
      if (attemptsWithoutProgress != null)
        'attempts_without_progress': attemptsWithoutProgress,
      if (nextAttemptAt != null) 'next_attempt_at': nextAttemptAt,
      if (fingerprint != null) 'fingerprint': fingerprint,
      if (sourceMtime != null) 'source_mtime': sourceMtime,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (taskId != null) 'task_id': taskId,
      if (subtaskId != null) 'subtask_id': subtaskId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  UploadSessionsCompanion copyWith({
    Value<String>? id,
    Value<String>? filepath,
    Value<int>? fileSize,
    Value<String>? fileName,
    Value<String>? mimeType,
    Value<int?>? durationMs,
    Value<String?>? thumbnailPath,
    Value<String?>? metadataFilepath,
    Value<int?>? chunkSize,
    Value<int?>? partCount,
    Value<String?>? s3Key,
    Value<String?>? s3UploadId,
    Value<String?>? assetId,
    Value<SessionState>? state,
    Value<String?>? lastErrorCode,
    Value<String?>? lastErrorDetail,
    Value<int>? attemptsWithoutProgress,
    Value<DateTime?>? nextAttemptAt,
    Value<String?>? fingerprint,
    Value<DateTime?>? sourceMtime,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<String?>? taskId,
    Value<String?>? subtaskId,
    Value<int>? rowid,
  }) {
    return UploadSessionsCompanion(
      id: id ?? this.id,
      filepath: filepath ?? this.filepath,
      fileSize: fileSize ?? this.fileSize,
      fileName: fileName ?? this.fileName,
      mimeType: mimeType ?? this.mimeType,
      durationMs: durationMs ?? this.durationMs,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      metadataFilepath: metadataFilepath ?? this.metadataFilepath,
      chunkSize: chunkSize ?? this.chunkSize,
      partCount: partCount ?? this.partCount,
      s3Key: s3Key ?? this.s3Key,
      s3UploadId: s3UploadId ?? this.s3UploadId,
      assetId: assetId ?? this.assetId,
      state: state ?? this.state,
      lastErrorCode: lastErrorCode ?? this.lastErrorCode,
      lastErrorDetail: lastErrorDetail ?? this.lastErrorDetail,
      attemptsWithoutProgress:
          attemptsWithoutProgress ?? this.attemptsWithoutProgress,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      fingerprint: fingerprint ?? this.fingerprint,
      sourceMtime: sourceMtime ?? this.sourceMtime,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      taskId: taskId ?? this.taskId,
      subtaskId: subtaskId ?? this.subtaskId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (filepath.present) {
      map['filepath'] = Variable<String>(filepath.value);
    }
    if (fileSize.present) {
      map['file_size'] = Variable<int>(fileSize.value);
    }
    if (fileName.present) {
      map['file_name'] = Variable<String>(fileName.value);
    }
    if (mimeType.present) {
      map['mime_type'] = Variable<String>(mimeType.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (thumbnailPath.present) {
      map['thumbnail_path'] = Variable<String>(thumbnailPath.value);
    }
    if (metadataFilepath.present) {
      map['metadata_filepath'] = Variable<String>(metadataFilepath.value);
    }
    if (chunkSize.present) {
      map['chunk_size'] = Variable<int>(chunkSize.value);
    }
    if (partCount.present) {
      map['part_count'] = Variable<int>(partCount.value);
    }
    if (s3Key.present) {
      map['s3_key'] = Variable<String>(s3Key.value);
    }
    if (s3UploadId.present) {
      map['s3_upload_id'] = Variable<String>(s3UploadId.value);
    }
    if (assetId.present) {
      map['asset_id'] = Variable<String>(assetId.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(
        $UploadSessionsTable.$converterstate.toSql(state.value),
      );
    }
    if (lastErrorCode.present) {
      map['last_error_code'] = Variable<String>(lastErrorCode.value);
    }
    if (lastErrorDetail.present) {
      map['last_error_detail'] = Variable<String>(lastErrorDetail.value);
    }
    if (attemptsWithoutProgress.present) {
      map['attempts_without_progress'] = Variable<int>(
        attemptsWithoutProgress.value,
      );
    }
    if (nextAttemptAt.present) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt.value);
    }
    if (fingerprint.present) {
      map['fingerprint'] = Variable<String>(fingerprint.value);
    }
    if (sourceMtime.present) {
      map['source_mtime'] = Variable<DateTime>(sourceMtime.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (taskId.present) {
      map['task_id'] = Variable<String>(taskId.value);
    }
    if (subtaskId.present) {
      map['subtask_id'] = Variable<String>(subtaskId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UploadSessionsCompanion(')
          ..write('id: $id, ')
          ..write('filepath: $filepath, ')
          ..write('fileSize: $fileSize, ')
          ..write('fileName: $fileName, ')
          ..write('mimeType: $mimeType, ')
          ..write('durationMs: $durationMs, ')
          ..write('thumbnailPath: $thumbnailPath, ')
          ..write('metadataFilepath: $metadataFilepath, ')
          ..write('chunkSize: $chunkSize, ')
          ..write('partCount: $partCount, ')
          ..write('s3Key: $s3Key, ')
          ..write('s3UploadId: $s3UploadId, ')
          ..write('assetId: $assetId, ')
          ..write('state: $state, ')
          ..write('lastErrorCode: $lastErrorCode, ')
          ..write('lastErrorDetail: $lastErrorDetail, ')
          ..write('attemptsWithoutProgress: $attemptsWithoutProgress, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('fingerprint: $fingerprint, ')
          ..write('sourceMtime: $sourceMtime, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('taskId: $taskId, ')
          ..write('subtaskId: $subtaskId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $UploadPartsTable extends UploadParts
    with TableInfo<$UploadPartsTable, UploadPart> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UploadPartsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES upload_sessions (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _partNumberMeta = const VerificationMeta(
    'partNumber',
  );
  @override
  late final GeneratedColumn<int> partNumber = GeneratedColumn<int>(
    'part_number',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _offsetMeta = const VerificationMeta('offset');
  @override
  late final GeneratedColumn<int> offset = GeneratedColumn<int>(
    'offset',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lengthMeta = const VerificationMeta('length');
  @override
  late final GeneratedColumn<int> length = GeneratedColumn<int>(
    'length',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<PartState, String> state =
      GeneratedColumn<String>(
        'state',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: Constant(PartState.planned.name),
      ).withConverter<PartState>($UploadPartsTable.$converterstate);
  static const VerificationMeta _urlMeta = const VerificationMeta('url');
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
    'url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _urlExpiresAtMeta = const VerificationMeta(
    'urlExpiresAt',
  );
  @override
  late final GeneratedColumn<DateTime> urlExpiresAt = GeneratedColumn<DateTime>(
    'url_expires_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _etagMeta = const VerificationMeta('etag');
  @override
  late final GeneratedColumn<String> etag = GeneratedColumn<String>(
    'etag',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _md5Meta = const VerificationMeta('md5');
  @override
  late final GeneratedColumn<String> md5 = GeneratedColumn<String>(
    'md5',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _attemptsAtUrlMeta = const VerificationMeta(
    'attemptsAtUrl',
  );
  @override
  late final GeneratedColumn<int> attemptsAtUrl = GeneratedColumn<int>(
    'attempts_at_url',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastErrorCodeMeta = const VerificationMeta(
    'lastErrorCode',
  );
  @override
  late final GeneratedColumn<String> lastErrorCode = GeneratedColumn<String>(
    'last_error_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    sessionId,
    partNumber,
    offset,
    length,
    state,
    url,
    urlExpiresAt,
    etag,
    md5,
    attempts,
    attemptsAtUrl,
    lastErrorCode,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'upload_parts';
  @override
  VerificationContext validateIntegrity(
    Insertable<UploadPart> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('part_number')) {
      context.handle(
        _partNumberMeta,
        partNumber.isAcceptableOrUnknown(data['part_number']!, _partNumberMeta),
      );
    } else if (isInserting) {
      context.missing(_partNumberMeta);
    }
    if (data.containsKey('offset')) {
      context.handle(
        _offsetMeta,
        offset.isAcceptableOrUnknown(data['offset']!, _offsetMeta),
      );
    } else if (isInserting) {
      context.missing(_offsetMeta);
    }
    if (data.containsKey('length')) {
      context.handle(
        _lengthMeta,
        length.isAcceptableOrUnknown(data['length']!, _lengthMeta),
      );
    } else if (isInserting) {
      context.missing(_lengthMeta);
    }
    if (data.containsKey('url')) {
      context.handle(
        _urlMeta,
        url.isAcceptableOrUnknown(data['url']!, _urlMeta),
      );
    }
    if (data.containsKey('url_expires_at')) {
      context.handle(
        _urlExpiresAtMeta,
        urlExpiresAt.isAcceptableOrUnknown(
          data['url_expires_at']!,
          _urlExpiresAtMeta,
        ),
      );
    }
    if (data.containsKey('etag')) {
      context.handle(
        _etagMeta,
        etag.isAcceptableOrUnknown(data['etag']!, _etagMeta),
      );
    }
    if (data.containsKey('md5')) {
      context.handle(
        _md5Meta,
        md5.isAcceptableOrUnknown(data['md5']!, _md5Meta),
      );
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('attempts_at_url')) {
      context.handle(
        _attemptsAtUrlMeta,
        attemptsAtUrl.isAcceptableOrUnknown(
          data['attempts_at_url']!,
          _attemptsAtUrlMeta,
        ),
      );
    }
    if (data.containsKey('last_error_code')) {
      context.handle(
        _lastErrorCodeMeta,
        lastErrorCode.isAcceptableOrUnknown(
          data['last_error_code']!,
          _lastErrorCodeMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sessionId, partNumber};
  @override
  UploadPart map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return UploadPart(
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      partNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}part_number'],
      )!,
      offset: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}offset'],
      )!,
      length: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}length'],
      )!,
      state: $UploadPartsTable.$converterstate.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}state'],
        )!,
      ),
      url: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}url'],
      ),
      urlExpiresAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}url_expires_at'],
      ),
      etag: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}etag'],
      ),
      md5: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}md5'],
      ),
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      attemptsAtUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts_at_url'],
      )!,
      lastErrorCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error_code'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $UploadPartsTable createAlias(String alias) {
    return $UploadPartsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<PartState, String, String> $converterstate =
      const EnumNameConverter<PartState>(PartState.values);
}

class UploadPart extends DataClass implements Insertable<UploadPart> {
  final String sessionId;
  final int partNumber;
  final int offset;
  final int length;
  final PartState state;
  final String? url;
  final DateTime? urlExpiresAt;
  final String? etag;
  final String? md5;

  /// Total attempts across all URLs for this part (budget cap, doc 06 §2).
  final int attempts;

  /// Attempts against the *current* presigned URL; reset to 0 when a fresh URL
  /// is assigned. Lets the per-URL budget (5) stay distinct from the total (15).
  final int attemptsAtUrl;
  final String? lastErrorCode;
  final DateTime updatedAt;
  const UploadPart({
    required this.sessionId,
    required this.partNumber,
    required this.offset,
    required this.length,
    required this.state,
    this.url,
    this.urlExpiresAt,
    this.etag,
    this.md5,
    required this.attempts,
    required this.attemptsAtUrl,
    this.lastErrorCode,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['session_id'] = Variable<String>(sessionId);
    map['part_number'] = Variable<int>(partNumber);
    map['offset'] = Variable<int>(offset);
    map['length'] = Variable<int>(length);
    {
      map['state'] = Variable<String>(
        $UploadPartsTable.$converterstate.toSql(state),
      );
    }
    if (!nullToAbsent || url != null) {
      map['url'] = Variable<String>(url);
    }
    if (!nullToAbsent || urlExpiresAt != null) {
      map['url_expires_at'] = Variable<DateTime>(urlExpiresAt);
    }
    if (!nullToAbsent || etag != null) {
      map['etag'] = Variable<String>(etag);
    }
    if (!nullToAbsent || md5 != null) {
      map['md5'] = Variable<String>(md5);
    }
    map['attempts'] = Variable<int>(attempts);
    map['attempts_at_url'] = Variable<int>(attemptsAtUrl);
    if (!nullToAbsent || lastErrorCode != null) {
      map['last_error_code'] = Variable<String>(lastErrorCode);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  UploadPartsCompanion toCompanion(bool nullToAbsent) {
    return UploadPartsCompanion(
      sessionId: Value(sessionId),
      partNumber: Value(partNumber),
      offset: Value(offset),
      length: Value(length),
      state: Value(state),
      url: url == null && nullToAbsent ? const Value.absent() : Value(url),
      urlExpiresAt: urlExpiresAt == null && nullToAbsent
          ? const Value.absent()
          : Value(urlExpiresAt),
      etag: etag == null && nullToAbsent ? const Value.absent() : Value(etag),
      md5: md5 == null && nullToAbsent ? const Value.absent() : Value(md5),
      attempts: Value(attempts),
      attemptsAtUrl: Value(attemptsAtUrl),
      lastErrorCode: lastErrorCode == null && nullToAbsent
          ? const Value.absent()
          : Value(lastErrorCode),
      updatedAt: Value(updatedAt),
    );
  }

  factory UploadPart.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return UploadPart(
      sessionId: serializer.fromJson<String>(json['sessionId']),
      partNumber: serializer.fromJson<int>(json['partNumber']),
      offset: serializer.fromJson<int>(json['offset']),
      length: serializer.fromJson<int>(json['length']),
      state: $UploadPartsTable.$converterstate.fromJson(
        serializer.fromJson<String>(json['state']),
      ),
      url: serializer.fromJson<String?>(json['url']),
      urlExpiresAt: serializer.fromJson<DateTime?>(json['urlExpiresAt']),
      etag: serializer.fromJson<String?>(json['etag']),
      md5: serializer.fromJson<String?>(json['md5']),
      attempts: serializer.fromJson<int>(json['attempts']),
      attemptsAtUrl: serializer.fromJson<int>(json['attemptsAtUrl']),
      lastErrorCode: serializer.fromJson<String?>(json['lastErrorCode']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sessionId': serializer.toJson<String>(sessionId),
      'partNumber': serializer.toJson<int>(partNumber),
      'offset': serializer.toJson<int>(offset),
      'length': serializer.toJson<int>(length),
      'state': serializer.toJson<String>(
        $UploadPartsTable.$converterstate.toJson(state),
      ),
      'url': serializer.toJson<String?>(url),
      'urlExpiresAt': serializer.toJson<DateTime?>(urlExpiresAt),
      'etag': serializer.toJson<String?>(etag),
      'md5': serializer.toJson<String?>(md5),
      'attempts': serializer.toJson<int>(attempts),
      'attemptsAtUrl': serializer.toJson<int>(attemptsAtUrl),
      'lastErrorCode': serializer.toJson<String?>(lastErrorCode),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  UploadPart copyWith({
    String? sessionId,
    int? partNumber,
    int? offset,
    int? length,
    PartState? state,
    Value<String?> url = const Value.absent(),
    Value<DateTime?> urlExpiresAt = const Value.absent(),
    Value<String?> etag = const Value.absent(),
    Value<String?> md5 = const Value.absent(),
    int? attempts,
    int? attemptsAtUrl,
    Value<String?> lastErrorCode = const Value.absent(),
    DateTime? updatedAt,
  }) => UploadPart(
    sessionId: sessionId ?? this.sessionId,
    partNumber: partNumber ?? this.partNumber,
    offset: offset ?? this.offset,
    length: length ?? this.length,
    state: state ?? this.state,
    url: url.present ? url.value : this.url,
    urlExpiresAt: urlExpiresAt.present ? urlExpiresAt.value : this.urlExpiresAt,
    etag: etag.present ? etag.value : this.etag,
    md5: md5.present ? md5.value : this.md5,
    attempts: attempts ?? this.attempts,
    attemptsAtUrl: attemptsAtUrl ?? this.attemptsAtUrl,
    lastErrorCode: lastErrorCode.present
        ? lastErrorCode.value
        : this.lastErrorCode,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  UploadPart copyWithCompanion(UploadPartsCompanion data) {
    return UploadPart(
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      partNumber: data.partNumber.present
          ? data.partNumber.value
          : this.partNumber,
      offset: data.offset.present ? data.offset.value : this.offset,
      length: data.length.present ? data.length.value : this.length,
      state: data.state.present ? data.state.value : this.state,
      url: data.url.present ? data.url.value : this.url,
      urlExpiresAt: data.urlExpiresAt.present
          ? data.urlExpiresAt.value
          : this.urlExpiresAt,
      etag: data.etag.present ? data.etag.value : this.etag,
      md5: data.md5.present ? data.md5.value : this.md5,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      attemptsAtUrl: data.attemptsAtUrl.present
          ? data.attemptsAtUrl.value
          : this.attemptsAtUrl,
      lastErrorCode: data.lastErrorCode.present
          ? data.lastErrorCode.value
          : this.lastErrorCode,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('UploadPart(')
          ..write('sessionId: $sessionId, ')
          ..write('partNumber: $partNumber, ')
          ..write('offset: $offset, ')
          ..write('length: $length, ')
          ..write('state: $state, ')
          ..write('url: $url, ')
          ..write('urlExpiresAt: $urlExpiresAt, ')
          ..write('etag: $etag, ')
          ..write('md5: $md5, ')
          ..write('attempts: $attempts, ')
          ..write('attemptsAtUrl: $attemptsAtUrl, ')
          ..write('lastErrorCode: $lastErrorCode, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    sessionId,
    partNumber,
    offset,
    length,
    state,
    url,
    urlExpiresAt,
    etag,
    md5,
    attempts,
    attemptsAtUrl,
    lastErrorCode,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UploadPart &&
          other.sessionId == this.sessionId &&
          other.partNumber == this.partNumber &&
          other.offset == this.offset &&
          other.length == this.length &&
          other.state == this.state &&
          other.url == this.url &&
          other.urlExpiresAt == this.urlExpiresAt &&
          other.etag == this.etag &&
          other.md5 == this.md5 &&
          other.attempts == this.attempts &&
          other.attemptsAtUrl == this.attemptsAtUrl &&
          other.lastErrorCode == this.lastErrorCode &&
          other.updatedAt == this.updatedAt);
}

class UploadPartsCompanion extends UpdateCompanion<UploadPart> {
  final Value<String> sessionId;
  final Value<int> partNumber;
  final Value<int> offset;
  final Value<int> length;
  final Value<PartState> state;
  final Value<String?> url;
  final Value<DateTime?> urlExpiresAt;
  final Value<String?> etag;
  final Value<String?> md5;
  final Value<int> attempts;
  final Value<int> attemptsAtUrl;
  final Value<String?> lastErrorCode;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const UploadPartsCompanion({
    this.sessionId = const Value.absent(),
    this.partNumber = const Value.absent(),
    this.offset = const Value.absent(),
    this.length = const Value.absent(),
    this.state = const Value.absent(),
    this.url = const Value.absent(),
    this.urlExpiresAt = const Value.absent(),
    this.etag = const Value.absent(),
    this.md5 = const Value.absent(),
    this.attempts = const Value.absent(),
    this.attemptsAtUrl = const Value.absent(),
    this.lastErrorCode = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  UploadPartsCompanion.insert({
    required String sessionId,
    required int partNumber,
    required int offset,
    required int length,
    this.state = const Value.absent(),
    this.url = const Value.absent(),
    this.urlExpiresAt = const Value.absent(),
    this.etag = const Value.absent(),
    this.md5 = const Value.absent(),
    this.attempts = const Value.absent(),
    this.attemptsAtUrl = const Value.absent(),
    this.lastErrorCode = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : sessionId = Value(sessionId),
       partNumber = Value(partNumber),
       offset = Value(offset),
       length = Value(length);
  static Insertable<UploadPart> custom({
    Expression<String>? sessionId,
    Expression<int>? partNumber,
    Expression<int>? offset,
    Expression<int>? length,
    Expression<String>? state,
    Expression<String>? url,
    Expression<DateTime>? urlExpiresAt,
    Expression<String>? etag,
    Expression<String>? md5,
    Expression<int>? attempts,
    Expression<int>? attemptsAtUrl,
    Expression<String>? lastErrorCode,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sessionId != null) 'session_id': sessionId,
      if (partNumber != null) 'part_number': partNumber,
      if (offset != null) 'offset': offset,
      if (length != null) 'length': length,
      if (state != null) 'state': state,
      if (url != null) 'url': url,
      if (urlExpiresAt != null) 'url_expires_at': urlExpiresAt,
      if (etag != null) 'etag': etag,
      if (md5 != null) 'md5': md5,
      if (attempts != null) 'attempts': attempts,
      if (attemptsAtUrl != null) 'attempts_at_url': attemptsAtUrl,
      if (lastErrorCode != null) 'last_error_code': lastErrorCode,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  UploadPartsCompanion copyWith({
    Value<String>? sessionId,
    Value<int>? partNumber,
    Value<int>? offset,
    Value<int>? length,
    Value<PartState>? state,
    Value<String?>? url,
    Value<DateTime?>? urlExpiresAt,
    Value<String?>? etag,
    Value<String?>? md5,
    Value<int>? attempts,
    Value<int>? attemptsAtUrl,
    Value<String?>? lastErrorCode,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return UploadPartsCompanion(
      sessionId: sessionId ?? this.sessionId,
      partNumber: partNumber ?? this.partNumber,
      offset: offset ?? this.offset,
      length: length ?? this.length,
      state: state ?? this.state,
      url: url ?? this.url,
      urlExpiresAt: urlExpiresAt ?? this.urlExpiresAt,
      etag: etag ?? this.etag,
      md5: md5 ?? this.md5,
      attempts: attempts ?? this.attempts,
      attemptsAtUrl: attemptsAtUrl ?? this.attemptsAtUrl,
      lastErrorCode: lastErrorCode ?? this.lastErrorCode,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (partNumber.present) {
      map['part_number'] = Variable<int>(partNumber.value);
    }
    if (offset.present) {
      map['offset'] = Variable<int>(offset.value);
    }
    if (length.present) {
      map['length'] = Variable<int>(length.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(
        $UploadPartsTable.$converterstate.toSql(state.value),
      );
    }
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (urlExpiresAt.present) {
      map['url_expires_at'] = Variable<DateTime>(urlExpiresAt.value);
    }
    if (etag.present) {
      map['etag'] = Variable<String>(etag.value);
    }
    if (md5.present) {
      map['md5'] = Variable<String>(md5.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (attemptsAtUrl.present) {
      map['attempts_at_url'] = Variable<int>(attemptsAtUrl.value);
    }
    if (lastErrorCode.present) {
      map['last_error_code'] = Variable<String>(lastErrorCode.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UploadPartsCompanion(')
          ..write('sessionId: $sessionId, ')
          ..write('partNumber: $partNumber, ')
          ..write('offset: $offset, ')
          ..write('length: $length, ')
          ..write('state: $state, ')
          ..write('url: $url, ')
          ..write('urlExpiresAt: $urlExpiresAt, ')
          ..write('etag: $etag, ')
          ..write('md5: $md5, ')
          ..write('attempts: $attempts, ')
          ..write('attemptsAtUrl: $attemptsAtUrl, ')
          ..write('lastErrorCode: $lastErrorCode, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $UploadsTable uploads = $UploadsTable(this);
  late final $UploadSessionsTable uploadSessions = $UploadSessionsTable(this);
  late final $UploadPartsTable uploadParts = $UploadPartsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    uploads,
    uploadSessions,
    uploadParts,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'upload_sessions',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('upload_parts', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$UploadsTableCreateCompanionBuilder =
    UploadsCompanion Function({
      Value<int> id,
      required String filepath,
      Value<int?> filesize,
      Value<int?> durationMs,
      Value<String?> thumnbnail,
      Value<String?> metadataFilepath,
      Value<UploadStatus> status,
      Value<String?> fileName,
      Value<String?> mimeType,
      Value<double?> progress,
      Value<int> retryCount,
      Value<S3PresignResponse?> s3PresignResponse,
      Value<MultipartStartResponse?> multipartStartResponse,
      Value<List<PartUrl>?> partUrls,
      Value<List<UploadedPart>?> uploadedParts,
      Value<int?> partsCount,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<bool> isHidden,
      Value<String?> taskId,
      Value<String?> taskName,
      Value<String?> subtaskId,
      Value<String?> subtaskName,
    });
typedef $$UploadsTableUpdateCompanionBuilder =
    UploadsCompanion Function({
      Value<int> id,
      Value<String> filepath,
      Value<int?> filesize,
      Value<int?> durationMs,
      Value<String?> thumnbnail,
      Value<String?> metadataFilepath,
      Value<UploadStatus> status,
      Value<String?> fileName,
      Value<String?> mimeType,
      Value<double?> progress,
      Value<int> retryCount,
      Value<S3PresignResponse?> s3PresignResponse,
      Value<MultipartStartResponse?> multipartStartResponse,
      Value<List<PartUrl>?> partUrls,
      Value<List<UploadedPart>?> uploadedParts,
      Value<int?> partsCount,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<bool> isHidden,
      Value<String?> taskId,
      Value<String?> taskName,
      Value<String?> subtaskId,
      Value<String?> subtaskName,
    });

class $$UploadsTableFilterComposer
    extends Composer<_$AppDatabase, $UploadsTable> {
  $$UploadsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get filepath => $composableBuilder(
    column: $table.filepath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get filesize => $composableBuilder(
    column: $table.filesize,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get thumnbnail => $composableBuilder(
    column: $table.thumnbnail,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get metadataFilepath => $composableBuilder(
    column: $table.metadataFilepath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<UploadStatus, UploadStatus, String>
  get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get progress => $composableBuilder(
    column: $table.progress,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<S3PresignResponse?, S3PresignResponse, String>
  get s3PresignResponse => $composableBuilder(
    column: $table.s3PresignResponse,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<
    MultipartStartResponse?,
    MultipartStartResponse,
    String
  >
  get multipartStartResponse => $composableBuilder(
    column: $table.multipartStartResponse,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<List<PartUrl>?, List<PartUrl>, String>
  get partUrls => $composableBuilder(
    column: $table.partUrls,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<
    List<UploadedPart>?,
    List<UploadedPart>,
    String
  >
  get uploadedParts => $composableBuilder(
    column: $table.uploadedParts,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<int> get partsCount => $composableBuilder(
    column: $table.partsCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isHidden => $composableBuilder(
    column: $table.isHidden,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get taskId => $composableBuilder(
    column: $table.taskId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get taskName => $composableBuilder(
    column: $table.taskName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get subtaskId => $composableBuilder(
    column: $table.subtaskId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get subtaskName => $composableBuilder(
    column: $table.subtaskName,
    builder: (column) => ColumnFilters(column),
  );
}

class $$UploadsTableOrderingComposer
    extends Composer<_$AppDatabase, $UploadsTable> {
  $$UploadsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get filepath => $composableBuilder(
    column: $table.filepath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get filesize => $composableBuilder(
    column: $table.filesize,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get thumnbnail => $composableBuilder(
    column: $table.thumnbnail,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get metadataFilepath => $composableBuilder(
    column: $table.metadataFilepath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get progress => $composableBuilder(
    column: $table.progress,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get s3PresignResponse => $composableBuilder(
    column: $table.s3PresignResponse,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get multipartStartResponse => $composableBuilder(
    column: $table.multipartStartResponse,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get partUrls => $composableBuilder(
    column: $table.partUrls,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get uploadedParts => $composableBuilder(
    column: $table.uploadedParts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get partsCount => $composableBuilder(
    column: $table.partsCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isHidden => $composableBuilder(
    column: $table.isHidden,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get taskId => $composableBuilder(
    column: $table.taskId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get taskName => $composableBuilder(
    column: $table.taskName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get subtaskId => $composableBuilder(
    column: $table.subtaskId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get subtaskName => $composableBuilder(
    column: $table.subtaskName,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$UploadsTableAnnotationComposer
    extends Composer<_$AppDatabase, $UploadsTable> {
  $$UploadsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get filepath =>
      $composableBuilder(column: $table.filepath, builder: (column) => column);

  GeneratedColumn<int> get filesize =>
      $composableBuilder(column: $table.filesize, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get thumnbnail => $composableBuilder(
    column: $table.thumnbnail,
    builder: (column) => column,
  );

  GeneratedColumn<String> get metadataFilepath => $composableBuilder(
    column: $table.metadataFilepath,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<UploadStatus, String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get fileName =>
      $composableBuilder(column: $table.fileName, builder: (column) => column);

  GeneratedColumn<String> get mimeType =>
      $composableBuilder(column: $table.mimeType, builder: (column) => column);

  GeneratedColumn<double> get progress =>
      $composableBuilder(column: $table.progress, builder: (column) => column);

  GeneratedColumn<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<S3PresignResponse?, String>
  get s3PresignResponse => $composableBuilder(
    column: $table.s3PresignResponse,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<MultipartStartResponse?, String>
  get multipartStartResponse => $composableBuilder(
    column: $table.multipartStartResponse,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<List<PartUrl>?, String> get partUrls =>
      $composableBuilder(column: $table.partUrls, builder: (column) => column);

  GeneratedColumnWithTypeConverter<List<UploadedPart>?, String>
  get uploadedParts => $composableBuilder(
    column: $table.uploadedParts,
    builder: (column) => column,
  );

  GeneratedColumn<int> get partsCount => $composableBuilder(
    column: $table.partsCount,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get isHidden =>
      $composableBuilder(column: $table.isHidden, builder: (column) => column);

  GeneratedColumn<String> get taskId =>
      $composableBuilder(column: $table.taskId, builder: (column) => column);

  GeneratedColumn<String> get taskName =>
      $composableBuilder(column: $table.taskName, builder: (column) => column);

  GeneratedColumn<String> get subtaskId =>
      $composableBuilder(column: $table.subtaskId, builder: (column) => column);

  GeneratedColumn<String> get subtaskName => $composableBuilder(
    column: $table.subtaskName,
    builder: (column) => column,
  );
}

class $$UploadsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $UploadsTable,
          Upload,
          $$UploadsTableFilterComposer,
          $$UploadsTableOrderingComposer,
          $$UploadsTableAnnotationComposer,
          $$UploadsTableCreateCompanionBuilder,
          $$UploadsTableUpdateCompanionBuilder,
          (Upload, BaseReferences<_$AppDatabase, $UploadsTable, Upload>),
          Upload,
          PrefetchHooks Function()
        > {
  $$UploadsTableTableManager(_$AppDatabase db, $UploadsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UploadsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UploadsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UploadsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> filepath = const Value.absent(),
                Value<int?> filesize = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
                Value<String?> thumnbnail = const Value.absent(),
                Value<String?> metadataFilepath = const Value.absent(),
                Value<UploadStatus> status = const Value.absent(),
                Value<String?> fileName = const Value.absent(),
                Value<String?> mimeType = const Value.absent(),
                Value<double?> progress = const Value.absent(),
                Value<int> retryCount = const Value.absent(),
                Value<S3PresignResponse?> s3PresignResponse =
                    const Value.absent(),
                Value<MultipartStartResponse?> multipartStartResponse =
                    const Value.absent(),
                Value<List<PartUrl>?> partUrls = const Value.absent(),
                Value<List<UploadedPart>?> uploadedParts = const Value.absent(),
                Value<int?> partsCount = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<bool> isHidden = const Value.absent(),
                Value<String?> taskId = const Value.absent(),
                Value<String?> taskName = const Value.absent(),
                Value<String?> subtaskId = const Value.absent(),
                Value<String?> subtaskName = const Value.absent(),
              }) => UploadsCompanion(
                id: id,
                filepath: filepath,
                filesize: filesize,
                durationMs: durationMs,
                thumnbnail: thumnbnail,
                metadataFilepath: metadataFilepath,
                status: status,
                fileName: fileName,
                mimeType: mimeType,
                progress: progress,
                retryCount: retryCount,
                s3PresignResponse: s3PresignResponse,
                multipartStartResponse: multipartStartResponse,
                partUrls: partUrls,
                uploadedParts: uploadedParts,
                partsCount: partsCount,
                createdAt: createdAt,
                updatedAt: updatedAt,
                isHidden: isHidden,
                taskId: taskId,
                taskName: taskName,
                subtaskId: subtaskId,
                subtaskName: subtaskName,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String filepath,
                Value<int?> filesize = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
                Value<String?> thumnbnail = const Value.absent(),
                Value<String?> metadataFilepath = const Value.absent(),
                Value<UploadStatus> status = const Value.absent(),
                Value<String?> fileName = const Value.absent(),
                Value<String?> mimeType = const Value.absent(),
                Value<double?> progress = const Value.absent(),
                Value<int> retryCount = const Value.absent(),
                Value<S3PresignResponse?> s3PresignResponse =
                    const Value.absent(),
                Value<MultipartStartResponse?> multipartStartResponse =
                    const Value.absent(),
                Value<List<PartUrl>?> partUrls = const Value.absent(),
                Value<List<UploadedPart>?> uploadedParts = const Value.absent(),
                Value<int?> partsCount = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<bool> isHidden = const Value.absent(),
                Value<String?> taskId = const Value.absent(),
                Value<String?> taskName = const Value.absent(),
                Value<String?> subtaskId = const Value.absent(),
                Value<String?> subtaskName = const Value.absent(),
              }) => UploadsCompanion.insert(
                id: id,
                filepath: filepath,
                filesize: filesize,
                durationMs: durationMs,
                thumnbnail: thumnbnail,
                metadataFilepath: metadataFilepath,
                status: status,
                fileName: fileName,
                mimeType: mimeType,
                progress: progress,
                retryCount: retryCount,
                s3PresignResponse: s3PresignResponse,
                multipartStartResponse: multipartStartResponse,
                partUrls: partUrls,
                uploadedParts: uploadedParts,
                partsCount: partsCount,
                createdAt: createdAt,
                updatedAt: updatedAt,
                isHidden: isHidden,
                taskId: taskId,
                taskName: taskName,
                subtaskId: subtaskId,
                subtaskName: subtaskName,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$UploadsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $UploadsTable,
      Upload,
      $$UploadsTableFilterComposer,
      $$UploadsTableOrderingComposer,
      $$UploadsTableAnnotationComposer,
      $$UploadsTableCreateCompanionBuilder,
      $$UploadsTableUpdateCompanionBuilder,
      (Upload, BaseReferences<_$AppDatabase, $UploadsTable, Upload>),
      Upload,
      PrefetchHooks Function()
    >;
typedef $$UploadSessionsTableCreateCompanionBuilder =
    UploadSessionsCompanion Function({
      required String id,
      required String filepath,
      required int fileSize,
      required String fileName,
      required String mimeType,
      Value<int?> durationMs,
      Value<String?> thumbnailPath,
      Value<String?> metadataFilepath,
      Value<int?> chunkSize,
      Value<int?> partCount,
      Value<String?> s3Key,
      Value<String?> s3UploadId,
      Value<String?> assetId,
      Value<SessionState> state,
      Value<String?> lastErrorCode,
      Value<String?> lastErrorDetail,
      Value<int> attemptsWithoutProgress,
      Value<DateTime?> nextAttemptAt,
      Value<String?> fingerprint,
      Value<DateTime?> sourceMtime,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<String?> taskId,
      Value<String?> subtaskId,
      Value<int> rowid,
    });
typedef $$UploadSessionsTableUpdateCompanionBuilder =
    UploadSessionsCompanion Function({
      Value<String> id,
      Value<String> filepath,
      Value<int> fileSize,
      Value<String> fileName,
      Value<String> mimeType,
      Value<int?> durationMs,
      Value<String?> thumbnailPath,
      Value<String?> metadataFilepath,
      Value<int?> chunkSize,
      Value<int?> partCount,
      Value<String?> s3Key,
      Value<String?> s3UploadId,
      Value<String?> assetId,
      Value<SessionState> state,
      Value<String?> lastErrorCode,
      Value<String?> lastErrorDetail,
      Value<int> attemptsWithoutProgress,
      Value<DateTime?> nextAttemptAt,
      Value<String?> fingerprint,
      Value<DateTime?> sourceMtime,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<String?> taskId,
      Value<String?> subtaskId,
      Value<int> rowid,
    });

final class $$UploadSessionsTableReferences
    extends BaseReferences<_$AppDatabase, $UploadSessionsTable, UploadSession> {
  $$UploadSessionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<$UploadPartsTable, List<UploadPart>>
  _uploadPartsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.uploadParts,
    aliasName: 'upload_sessions__id__upload_parts__session_id',
  );

  $$UploadPartsTableProcessedTableManager get uploadPartsRefs {
    final manager = $$UploadPartsTableTableManager(
      $_db,
      $_db.uploadParts,
    ).filter((f) => f.sessionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_uploadPartsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$UploadSessionsTableFilterComposer
    extends Composer<_$AppDatabase, $UploadSessionsTable> {
  $$UploadSessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get filepath => $composableBuilder(
    column: $table.filepath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fileSize => $composableBuilder(
    column: $table.fileSize,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get thumbnailPath => $composableBuilder(
    column: $table.thumbnailPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get metadataFilepath => $composableBuilder(
    column: $table.metadataFilepath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get chunkSize => $composableBuilder(
    column: $table.chunkSize,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get partCount => $composableBuilder(
    column: $table.partCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get s3Key => $composableBuilder(
    column: $table.s3Key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get s3UploadId => $composableBuilder(
    column: $table.s3UploadId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get assetId => $composableBuilder(
    column: $table.assetId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<SessionState, SessionState, String>
  get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get lastErrorCode => $composableBuilder(
    column: $table.lastErrorCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastErrorDetail => $composableBuilder(
    column: $table.lastErrorDetail,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attemptsWithoutProgress => $composableBuilder(
    column: $table.attemptsWithoutProgress,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get sourceMtime => $composableBuilder(
    column: $table.sourceMtime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get taskId => $composableBuilder(
    column: $table.taskId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get subtaskId => $composableBuilder(
    column: $table.subtaskId,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> uploadPartsRefs(
    Expression<bool> Function($$UploadPartsTableFilterComposer f) f,
  ) {
    final $$UploadPartsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.uploadParts,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UploadPartsTableFilterComposer(
            $db: $db,
            $table: $db.uploadParts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$UploadSessionsTableOrderingComposer
    extends Composer<_$AppDatabase, $UploadSessionsTable> {
  $$UploadSessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get filepath => $composableBuilder(
    column: $table.filepath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fileSize => $composableBuilder(
    column: $table.fileSize,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get thumbnailPath => $composableBuilder(
    column: $table.thumbnailPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get metadataFilepath => $composableBuilder(
    column: $table.metadataFilepath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get chunkSize => $composableBuilder(
    column: $table.chunkSize,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get partCount => $composableBuilder(
    column: $table.partCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get s3Key => $composableBuilder(
    column: $table.s3Key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get s3UploadId => $composableBuilder(
    column: $table.s3UploadId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get assetId => $composableBuilder(
    column: $table.assetId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastErrorCode => $composableBuilder(
    column: $table.lastErrorCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastErrorDetail => $composableBuilder(
    column: $table.lastErrorDetail,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attemptsWithoutProgress => $composableBuilder(
    column: $table.attemptsWithoutProgress,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get sourceMtime => $composableBuilder(
    column: $table.sourceMtime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get taskId => $composableBuilder(
    column: $table.taskId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get subtaskId => $composableBuilder(
    column: $table.subtaskId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$UploadSessionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $UploadSessionsTable> {
  $$UploadSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get filepath =>
      $composableBuilder(column: $table.filepath, builder: (column) => column);

  GeneratedColumn<int> get fileSize =>
      $composableBuilder(column: $table.fileSize, builder: (column) => column);

  GeneratedColumn<String> get fileName =>
      $composableBuilder(column: $table.fileName, builder: (column) => column);

  GeneratedColumn<String> get mimeType =>
      $composableBuilder(column: $table.mimeType, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get thumbnailPath => $composableBuilder(
    column: $table.thumbnailPath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get metadataFilepath => $composableBuilder(
    column: $table.metadataFilepath,
    builder: (column) => column,
  );

  GeneratedColumn<int> get chunkSize =>
      $composableBuilder(column: $table.chunkSize, builder: (column) => column);

  GeneratedColumn<int> get partCount =>
      $composableBuilder(column: $table.partCount, builder: (column) => column);

  GeneratedColumn<String> get s3Key =>
      $composableBuilder(column: $table.s3Key, builder: (column) => column);

  GeneratedColumn<String> get s3UploadId => $composableBuilder(
    column: $table.s3UploadId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get assetId =>
      $composableBuilder(column: $table.assetId, builder: (column) => column);

  GeneratedColumnWithTypeConverter<SessionState, String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<String> get lastErrorCode => $composableBuilder(
    column: $table.lastErrorCode,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastErrorDetail => $composableBuilder(
    column: $table.lastErrorDetail,
    builder: (column) => column,
  );

  GeneratedColumn<int> get attemptsWithoutProgress => $composableBuilder(
    column: $table.attemptsWithoutProgress,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get sourceMtime => $composableBuilder(
    column: $table.sourceMtime,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get taskId =>
      $composableBuilder(column: $table.taskId, builder: (column) => column);

  GeneratedColumn<String> get subtaskId =>
      $composableBuilder(column: $table.subtaskId, builder: (column) => column);

  Expression<T> uploadPartsRefs<T extends Object>(
    Expression<T> Function($$UploadPartsTableAnnotationComposer a) f,
  ) {
    final $$UploadPartsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.uploadParts,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UploadPartsTableAnnotationComposer(
            $db: $db,
            $table: $db.uploadParts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$UploadSessionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $UploadSessionsTable,
          UploadSession,
          $$UploadSessionsTableFilterComposer,
          $$UploadSessionsTableOrderingComposer,
          $$UploadSessionsTableAnnotationComposer,
          $$UploadSessionsTableCreateCompanionBuilder,
          $$UploadSessionsTableUpdateCompanionBuilder,
          (UploadSession, $$UploadSessionsTableReferences),
          UploadSession,
          PrefetchHooks Function({bool uploadPartsRefs})
        > {
  $$UploadSessionsTableTableManager(
    _$AppDatabase db,
    $UploadSessionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UploadSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UploadSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UploadSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> filepath = const Value.absent(),
                Value<int> fileSize = const Value.absent(),
                Value<String> fileName = const Value.absent(),
                Value<String> mimeType = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
                Value<String?> thumbnailPath = const Value.absent(),
                Value<String?> metadataFilepath = const Value.absent(),
                Value<int?> chunkSize = const Value.absent(),
                Value<int?> partCount = const Value.absent(),
                Value<String?> s3Key = const Value.absent(),
                Value<String?> s3UploadId = const Value.absent(),
                Value<String?> assetId = const Value.absent(),
                Value<SessionState> state = const Value.absent(),
                Value<String?> lastErrorCode = const Value.absent(),
                Value<String?> lastErrorDetail = const Value.absent(),
                Value<int> attemptsWithoutProgress = const Value.absent(),
                Value<DateTime?> nextAttemptAt = const Value.absent(),
                Value<String?> fingerprint = const Value.absent(),
                Value<DateTime?> sourceMtime = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String?> taskId = const Value.absent(),
                Value<String?> subtaskId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UploadSessionsCompanion(
                id: id,
                filepath: filepath,
                fileSize: fileSize,
                fileName: fileName,
                mimeType: mimeType,
                durationMs: durationMs,
                thumbnailPath: thumbnailPath,
                metadataFilepath: metadataFilepath,
                chunkSize: chunkSize,
                partCount: partCount,
                s3Key: s3Key,
                s3UploadId: s3UploadId,
                assetId: assetId,
                state: state,
                lastErrorCode: lastErrorCode,
                lastErrorDetail: lastErrorDetail,
                attemptsWithoutProgress: attemptsWithoutProgress,
                nextAttemptAt: nextAttemptAt,
                fingerprint: fingerprint,
                sourceMtime: sourceMtime,
                createdAt: createdAt,
                updatedAt: updatedAt,
                taskId: taskId,
                subtaskId: subtaskId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String filepath,
                required int fileSize,
                required String fileName,
                required String mimeType,
                Value<int?> durationMs = const Value.absent(),
                Value<String?> thumbnailPath = const Value.absent(),
                Value<String?> metadataFilepath = const Value.absent(),
                Value<int?> chunkSize = const Value.absent(),
                Value<int?> partCount = const Value.absent(),
                Value<String?> s3Key = const Value.absent(),
                Value<String?> s3UploadId = const Value.absent(),
                Value<String?> assetId = const Value.absent(),
                Value<SessionState> state = const Value.absent(),
                Value<String?> lastErrorCode = const Value.absent(),
                Value<String?> lastErrorDetail = const Value.absent(),
                Value<int> attemptsWithoutProgress = const Value.absent(),
                Value<DateTime?> nextAttemptAt = const Value.absent(),
                Value<String?> fingerprint = const Value.absent(),
                Value<DateTime?> sourceMtime = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String?> taskId = const Value.absent(),
                Value<String?> subtaskId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UploadSessionsCompanion.insert(
                id: id,
                filepath: filepath,
                fileSize: fileSize,
                fileName: fileName,
                mimeType: mimeType,
                durationMs: durationMs,
                thumbnailPath: thumbnailPath,
                metadataFilepath: metadataFilepath,
                chunkSize: chunkSize,
                partCount: partCount,
                s3Key: s3Key,
                s3UploadId: s3UploadId,
                assetId: assetId,
                state: state,
                lastErrorCode: lastErrorCode,
                lastErrorDetail: lastErrorDetail,
                attemptsWithoutProgress: attemptsWithoutProgress,
                nextAttemptAt: nextAttemptAt,
                fingerprint: fingerprint,
                sourceMtime: sourceMtime,
                createdAt: createdAt,
                updatedAt: updatedAt,
                taskId: taskId,
                subtaskId: subtaskId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$UploadSessionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({uploadPartsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (uploadPartsRefs) db.uploadParts],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (uploadPartsRefs)
                    await $_getPrefetchedData<
                      UploadSession,
                      $UploadSessionsTable,
                      UploadPart
                    >(
                      currentTable: table,
                      referencedTable: $$UploadSessionsTableReferences
                          ._uploadPartsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$UploadSessionsTableReferences(
                            db,
                            table,
                            p0,
                          ).uploadPartsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.sessionId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$UploadSessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $UploadSessionsTable,
      UploadSession,
      $$UploadSessionsTableFilterComposer,
      $$UploadSessionsTableOrderingComposer,
      $$UploadSessionsTableAnnotationComposer,
      $$UploadSessionsTableCreateCompanionBuilder,
      $$UploadSessionsTableUpdateCompanionBuilder,
      (UploadSession, $$UploadSessionsTableReferences),
      UploadSession,
      PrefetchHooks Function({bool uploadPartsRefs})
    >;
typedef $$UploadPartsTableCreateCompanionBuilder =
    UploadPartsCompanion Function({
      required String sessionId,
      required int partNumber,
      required int offset,
      required int length,
      Value<PartState> state,
      Value<String?> url,
      Value<DateTime?> urlExpiresAt,
      Value<String?> etag,
      Value<String?> md5,
      Value<int> attempts,
      Value<int> attemptsAtUrl,
      Value<String?> lastErrorCode,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$UploadPartsTableUpdateCompanionBuilder =
    UploadPartsCompanion Function({
      Value<String> sessionId,
      Value<int> partNumber,
      Value<int> offset,
      Value<int> length,
      Value<PartState> state,
      Value<String?> url,
      Value<DateTime?> urlExpiresAt,
      Value<String?> etag,
      Value<String?> md5,
      Value<int> attempts,
      Value<int> attemptsAtUrl,
      Value<String?> lastErrorCode,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$UploadPartsTableReferences
    extends BaseReferences<_$AppDatabase, $UploadPartsTable, UploadPart> {
  $$UploadPartsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $UploadSessionsTable _sessionIdTable(_$AppDatabase db) => db
      .uploadSessions
      .createAlias('upload_parts__session_id__upload_sessions__id');

  $$UploadSessionsTableProcessedTableManager get sessionId {
    final $_column = $_itemColumn<String>('session_id')!;

    final manager = $$UploadSessionsTableTableManager(
      $_db,
      $_db.uploadSessions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sessionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$UploadPartsTableFilterComposer
    extends Composer<_$AppDatabase, $UploadPartsTable> {
  $$UploadPartsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get partNumber => $composableBuilder(
    column: $table.partNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get offset => $composableBuilder(
    column: $table.offset,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get length => $composableBuilder(
    column: $table.length,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<PartState, PartState, String> get state =>
      $composableBuilder(
        column: $table.state,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get urlExpiresAt => $composableBuilder(
    column: $table.urlExpiresAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get etag => $composableBuilder(
    column: $table.etag,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get md5 => $composableBuilder(
    column: $table.md5,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attemptsAtUrl => $composableBuilder(
    column: $table.attemptsAtUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastErrorCode => $composableBuilder(
    column: $table.lastErrorCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$UploadSessionsTableFilterComposer get sessionId {
    final $$UploadSessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.uploadSessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UploadSessionsTableFilterComposer(
            $db: $db,
            $table: $db.uploadSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$UploadPartsTableOrderingComposer
    extends Composer<_$AppDatabase, $UploadPartsTable> {
  $$UploadPartsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get partNumber => $composableBuilder(
    column: $table.partNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get offset => $composableBuilder(
    column: $table.offset,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get length => $composableBuilder(
    column: $table.length,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get urlExpiresAt => $composableBuilder(
    column: $table.urlExpiresAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get etag => $composableBuilder(
    column: $table.etag,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get md5 => $composableBuilder(
    column: $table.md5,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attemptsAtUrl => $composableBuilder(
    column: $table.attemptsAtUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastErrorCode => $composableBuilder(
    column: $table.lastErrorCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$UploadSessionsTableOrderingComposer get sessionId {
    final $$UploadSessionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.uploadSessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UploadSessionsTableOrderingComposer(
            $db: $db,
            $table: $db.uploadSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$UploadPartsTableAnnotationComposer
    extends Composer<_$AppDatabase, $UploadPartsTable> {
  $$UploadPartsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get partNumber => $composableBuilder(
    column: $table.partNumber,
    builder: (column) => column,
  );

  GeneratedColumn<int> get offset =>
      $composableBuilder(column: $table.offset, builder: (column) => column);

  GeneratedColumn<int> get length =>
      $composableBuilder(column: $table.length, builder: (column) => column);

  GeneratedColumnWithTypeConverter<PartState, String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<String> get url =>
      $composableBuilder(column: $table.url, builder: (column) => column);

  GeneratedColumn<DateTime> get urlExpiresAt => $composableBuilder(
    column: $table.urlExpiresAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get etag =>
      $composableBuilder(column: $table.etag, builder: (column) => column);

  GeneratedColumn<String> get md5 =>
      $composableBuilder(column: $table.md5, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<int> get attemptsAtUrl => $composableBuilder(
    column: $table.attemptsAtUrl,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastErrorCode => $composableBuilder(
    column: $table.lastErrorCode,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$UploadSessionsTableAnnotationComposer get sessionId {
    final $$UploadSessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.uploadSessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UploadSessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.uploadSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$UploadPartsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $UploadPartsTable,
          UploadPart,
          $$UploadPartsTableFilterComposer,
          $$UploadPartsTableOrderingComposer,
          $$UploadPartsTableAnnotationComposer,
          $$UploadPartsTableCreateCompanionBuilder,
          $$UploadPartsTableUpdateCompanionBuilder,
          (UploadPart, $$UploadPartsTableReferences),
          UploadPart,
          PrefetchHooks Function({bool sessionId})
        > {
  $$UploadPartsTableTableManager(_$AppDatabase db, $UploadPartsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UploadPartsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UploadPartsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UploadPartsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> sessionId = const Value.absent(),
                Value<int> partNumber = const Value.absent(),
                Value<int> offset = const Value.absent(),
                Value<int> length = const Value.absent(),
                Value<PartState> state = const Value.absent(),
                Value<String?> url = const Value.absent(),
                Value<DateTime?> urlExpiresAt = const Value.absent(),
                Value<String?> etag = const Value.absent(),
                Value<String?> md5 = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<int> attemptsAtUrl = const Value.absent(),
                Value<String?> lastErrorCode = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UploadPartsCompanion(
                sessionId: sessionId,
                partNumber: partNumber,
                offset: offset,
                length: length,
                state: state,
                url: url,
                urlExpiresAt: urlExpiresAt,
                etag: etag,
                md5: md5,
                attempts: attempts,
                attemptsAtUrl: attemptsAtUrl,
                lastErrorCode: lastErrorCode,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String sessionId,
                required int partNumber,
                required int offset,
                required int length,
                Value<PartState> state = const Value.absent(),
                Value<String?> url = const Value.absent(),
                Value<DateTime?> urlExpiresAt = const Value.absent(),
                Value<String?> etag = const Value.absent(),
                Value<String?> md5 = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<int> attemptsAtUrl = const Value.absent(),
                Value<String?> lastErrorCode = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UploadPartsCompanion.insert(
                sessionId: sessionId,
                partNumber: partNumber,
                offset: offset,
                length: length,
                state: state,
                url: url,
                urlExpiresAt: urlExpiresAt,
                etag: etag,
                md5: md5,
                attempts: attempts,
                attemptsAtUrl: attemptsAtUrl,
                lastErrorCode: lastErrorCode,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$UploadPartsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({sessionId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (sessionId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.sessionId,
                                referencedTable: $$UploadPartsTableReferences
                                    ._sessionIdTable(db),
                                referencedColumn: $$UploadPartsTableReferences
                                    ._sessionIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$UploadPartsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $UploadPartsTable,
      UploadPart,
      $$UploadPartsTableFilterComposer,
      $$UploadPartsTableOrderingComposer,
      $$UploadPartsTableAnnotationComposer,
      $$UploadPartsTableCreateCompanionBuilder,
      $$UploadPartsTableUpdateCompanionBuilder,
      (UploadPart, $$UploadPartsTableReferences),
      UploadPart,
      PrefetchHooks Function({bool sessionId})
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$UploadsTableTableManager get uploads =>
      $$UploadsTableTableManager(_db, _db.uploads);
  $$UploadSessionsTableTableManager get uploadSessions =>
      $$UploadSessionsTableTableManager(_db, _db.uploadSessions);
  $$UploadPartsTableTableManager get uploadParts =>
      $$UploadPartsTableTableManager(_db, _db.uploadParts);
}
