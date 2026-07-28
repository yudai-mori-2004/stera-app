import "dart:io";

/// MCAP files open AND close with the same 8-byte magic
/// (`0x89 M C A P 0x30 \r \n`). The native recorder writes the trailing magic
/// as the very last step of `MCAPWriter.finish()` (after the summary/footer),
/// so its presence at the end of the file is the definitive "finalization
/// complete" signal.
///
/// `metadata.json` is NOT that signal: native finalization writes it BEFORE
/// `mcapWriter.finish()` (ArRecorderImpl.finalizationQueue), and for long
/// recordings the footer write is the slow step. Snapshotting a file size
/// while the footer is still being written froze a truncated chunk plan —
/// the upload then "completed" but held a truncated (or empty) object.
abstract final class McapFinalization {
  /// `0x89 M C A P 0x30 \r \n` — mirrors `MCAPWriter.magic` on iOS.
  static const List<int> magic = [
    0x89, 0x4D, 0x43, 0x41, 0x50, 0x30, 0x0D, 0x0A, //
  ];

  /// True when [file] ends with the trailing MCAP magic — the writer's
  /// `finish()` ran to completion and the file is safe to size-snapshot and
  /// upload. False for a still-growing or crash-truncated mcap.
  static Future<bool> isFinalized(File file) async {
    try {
      final length = await file.length();
      // A valid mcap holds at least the leading + trailing magic.
      if (length < magic.length * 2) return false;
      final raf = await file.open();
      try {
        await raf.setPosition(length - magic.length);
        final tail = await raf.read(magic.length);
        if (tail.length != magic.length) return false;
        for (var i = 0; i < magic.length; i++) {
          if (tail[i] != magic[i]) return false;
        }
        return true;
      } finally {
        await raf.close();
      }
    } catch (_) {
      // Unreadable/unstattable == not safely uploadable; callers treat false
      // as "skip/retry later", never as data loss.
      return false;
    }
  }
}
