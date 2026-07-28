import "package:flutter_test/flutter_test.dart";
import "package:stera/src/core/common/formatters/format_bytes.dart";

void main() {
  group("formatBytes", () {
    // Guards the output of the three duplicated `_formatBytes` copies this
    // replaced — the strings are user-visible, so drift here is a regression.
    test("steps through binary units", () {
      expect(formatBytes(512), "512 B");
      expect(formatBytes(1023), "1023 B");
      expect(formatBytes(1536), "1.5 KB");
      expect(formatBytes(1024 * 1024 * 5), "5.0 MB");
      expect(formatBytes(1024 * 1024 * 1024 * 2), "2.00 GB");
    });

    test("renders a placeholder rather than 'null'", () {
      expect(formatBytes(null), "--");
      expect(formatBytes(null, nullPlaceholder: "n/a"), "n/a");
    });

    test("handles the boundaries", () {
      expect(formatBytes(0), "0 B");
      expect(formatBytes(1024), "1.0 KB");
    });
  });
}
