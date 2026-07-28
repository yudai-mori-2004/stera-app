import "dart:io";

import "package:ffigen/ffigen.dart";

void main() {
  final packageRoot = Platform.script.resolve("../");
  final iosInteropHeader = packageRoot.resolve("ffi/ARRecorderInterop.h");

  FfiGenerator(
    headers: Headers(
      entryPoints: [iosInteropHeader],
      compilerOptions: ["-isysroot", iosSdkPath, "-fobjc-arc"],
      ignoreSourceErrors: false,
    ),
    objectiveC: ObjectiveC(
      interfaces: Interfaces(
        include: Declarations.includeSet({
          "ARFRecordingConfig",
          "ARFRecorderResult",
          "ARRecorderInterop",
        }),
        // No module prefix: the Swift classes carry explicit `@objc(...)` names
        // (ios/stera_recorder/Sources/stera_recorder/ArRecorderInterop.swift), so
        // their Objective-C runtime names don't depend on the module they're
        // compiled into.
        module: (declaration) => null,
      ),
    ),
    output: Output(
      dartFile: packageRoot.resolve(
        "lib/src/ffi/generated/ios_ar_recorder_objc_bindings.dart",
      ),
    ),
  ).generate();
}
