/// Truncate filename with ellipsis in the middle
///
/// Preserves file extension and shows beginning and end of filename.
/// Example: "very_long_filename_here.mp4" → "very_l...here.mp4"
String truncateFileName(String fileName, int maxLength) {
  if (fileName.length <= maxLength) return fileName;

  final lastDot = fileName.lastIndexOf(".");
  String name;
  String ext = "";

  if (lastDot != -1) {
    name = fileName.substring(0, lastDot);
    ext = fileName.substring(lastDot);
  } else {
    name = fileName;
  }

  final spaceForName = maxLength - ext.length - 3; // 3 for "..."
  if (spaceForName <= 0) return fileName;

  final halfSpace = spaceForName ~/ 2;
  final start = name.substring(0, halfSpace);
  final endPart = name.substring(name.length - halfSpace);

  return "$start...$endPart$ext";
}
