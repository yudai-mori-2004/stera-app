/// Landscape RGB / JPEG / preview target: 1280×720, 1920×1080, or 3840×2160.
enum RgbVideoResolution {
  /// 1280×720.
  hd720(720, 1280, 720),

  /// 1920×1080.
  hd1080(1080, 1920, 1080),

  /// 3840×2160. ARKit locks 4K capture to 30 fps.
  uhd4k(2160, 3840, 2160);

  /// Nominal short side (720p / 1080p / 2160p).
  final int nominalHeight;

  /// Width in landscape orientation.
  final int landscapeWidth;

  /// Height in landscape orientation.
  final int landscapeHeight;

  const RgbVideoResolution(
    this.nominalHeight,
    this.landscapeWidth,
    this.landscapeHeight,
  );

  /// The resolutions the recorder offers, ascending.
  static const supported = <RgbVideoResolution>[hd720, hd1080, uhd4k];

  /// Looks a resolution up by its [nominalHeight], falling back to [hd720] for
  /// an unrecognised value.
  static RgbVideoResolution fromNominalHeight(int height) {
    for (final r in supported) {
      if (r.nominalHeight == height) return r;
    }
    return hd720;
  }
}

const _rgbVideoResolutionBaseSubtitle =
    "RGB preview, JPEG frames, and encoded video (landscape). ";

const _rgbVideoResolutionOpenCameraHint =
    "Open this screen before starting the camera so the capture mode matches.";

/// Display and capability helpers for [RgbVideoResolution].
extension RgbVideoResolutionX on RgbVideoResolution {
  /// Short user-facing name: "720p", "1080p", "4K".
  String get label => switch (this) {
    RgbVideoResolution.uhd4k => "4K",
    RgbVideoResolution.hd1080 => "1080p",
    RgbVideoResolution.hd720 => "720p",
  };

  /// Highest ARKit session frame rate this resolution can deliver.
  int get maxArkitFps => this == RgbVideoResolution.uhd4k ? 30 : 60;

  /// The spatial rates selectable at this resolution, ascending. Always a
  /// contiguous sub-range of `RecordingConfig.supportedSpatialHz`.
  List<int> get spatialHzOptions => this == RgbVideoResolution.uhd4k
      ? const [5, 10, 15, 30]
      : const [15, 30, 60];

  /// One-line explanation for a settings row.
  String get subtitle =>
      "$_rgbVideoResolutionBaseSubtitle$_rgbVideoResolutionOpenCameraHint";
}
