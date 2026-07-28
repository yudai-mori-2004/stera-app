import "dart:convert";
import "dart:typed_data";

/// Deserializer for the little-endian XCDR1 payloads produced by
/// `ios/Runner/ar_recorder/data/CDRSerializer.swift`.
///
/// Alignment is computed relative to byte 4 (i.e. after the 4-byte CDR
/// encapsulation header), matching the writer and Foxglove's reader.
class CdrDeserializer {
  CdrDeserializer(this._data) : _view = ByteData.sublistView(_data) {
    if (_data.length < 4) {
      throw const FormatException("CDR payload shorter than encapsulation header");
    }
    _offset = 4; // skip encapsulation header (00 01 00 00 = CDR_LE)
  }

  final Uint8List _data;
  final ByteData _view;
  int _offset = 0;

  int get remaining => _data.length - _offset;

  void align(int alignment) {
    final remainder = (_offset - 4) % alignment;
    if (remainder != 0) _offset += alignment - remainder;
  }

  int uint8() => _view.getUint8(_offset++);

  int int8() => _view.getInt8(_offset++);

  int uint16() {
    align(2);
    final v = _view.getUint16(_offset, Endian.little);
    _offset += 2;
    return v;
  }

  int int32() {
    align(4);
    final v = _view.getInt32(_offset, Endian.little);
    _offset += 4;
    return v;
  }

  int uint32() {
    align(4);
    final v = _view.getUint32(_offset, Endian.little);
    _offset += 4;
    return v;
  }

  int int64() {
    align(8);
    final v = _view.getInt64(_offset, Endian.little);
    _offset += 8;
    return v;
  }

  int uint64() {
    align(8);
    final v = _view.getUint64(_offset, Endian.little);
    _offset += 8;
    return v;
  }

  double float32() {
    align(4);
    final v = _view.getFloat32(_offset, Endian.little);
    _offset += 4;
    return v;
  }

  double float64() {
    align(8);
    final v = _view.getFloat64(_offset, Endian.little);
    _offset += 8;
    return v;
  }

  /// CDR string: uint32 length (including null terminator) + bytes + null.
  String string() {
    final length = uint32();
    if (length == 0) return "";
    final stringBytes = Uint8List.sublistView(_data, _offset, _offset + length - 1);
    _offset += length;
    return utf8.decode(stringBytes, allowMalformed: true);
  }

  /// builtin_interfaces/Time (int32 sec + uint32 nanosec) as nanoseconds.
  int timeNs() {
    final sec = int32();
    final nanosec = uint32();
    return sec * 1000000000 + nanosec;
  }

  /// Sequence of uint8 (uint32 length prefix + raw bytes).
  Uint8List byteSequence() {
    final length = uint32();
    final v = Uint8List.sublistView(_data, _offset, _offset + length);
    _offset += length;
    return v;
  }

  List<double> float64List(int count) {
    return List<double>.generate(count, (_) => float64());
  }

  void skip(int count) {
    _offset += count;
  }
}
