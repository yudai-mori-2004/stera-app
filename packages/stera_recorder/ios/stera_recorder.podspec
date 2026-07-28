#
# The AR recorder's iOS implementation. `pod lib lint stera_recorder.podspec`
# validates changes to this file.
#
Pod::Spec.new do |s|
  s.name             = 'stera_recorder'
  s.version          = '0.0.1'
  s.summary          = 'ARKit capture + MCAP dataset writing for Flutter.'
  s.description      = <<-DESC
Owns the ARKit session, frame pipeline, video encoding and MCAP dataset writers
behind the `ar_recorder` method channel and the ARRecorderInterop FFI surface.
                       DESC
  s.homepage         = 'https://github.com/fpv-labs/stera-app'
  s.license          = { :type => 'Apache-2.0', :file => '../LICENSE' }
  s.author           = { 'FPV Labs' => 'subs@fpvlabs.ai' }
  s.source           = { :path => '.' }
  # Sources live in the Swift Package Manager layout (ios/stera_recorder); this
  # pod compiles the same files so the plugin keeps working under CocoaPods.
  # ARRecorderInterop.h lives in ../../ffi and is deliberately outside both: it
  # is an ffigen input describing the @objc surface of ArRecorderInterop.swift,
  # so compiling it here would redeclare what stera_recorder-Swift.h already
  # generates.
  s.source_files = 'stera_recorder/Sources/stera_recorder/**/*.swift',
                   'stera_recorder/Sources/stera_recorder_objc/**/*.{h,m}'
  # ObjCTryBlock is the @try/@catch shim MCAPWriter uses around FileHandle
  # writes; it has to be public so it lands in the pod's umbrella header and
  # stays visible to the pod's Swift sources. (Under SwiftPM it is a separate
  # module instead — see the `#if SWIFT_PACKAGE` import in MCAPWriter.)
  s.public_header_files = 'stera_recorder/Sources/stera_recorder_objc/include/**/*.h'
  s.dependency 'Flutter'
  s.platform = :ios, '14.0'
  s.frameworks = 'ARKit', 'AVFoundation', 'Accelerate', 'CoreImage', 'CoreMotion', 'CoreVideo', 'ImageIO'
  # MCAP CRCs go through zlib (`import zlib` in DatasetWriterImpl).
  s.libraries = 'z'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
