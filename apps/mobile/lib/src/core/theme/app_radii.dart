import "package:stera/src/core/theme/brand_shape.dart";
import "package:flutter/widgets.dart";

/// The corner-radius scale, as the app consumes it.
///
/// Every rounded corner in the app comes from here. Nothing in `lib/` should
/// spell a radius as a number: `brand:verify` fails the build if it does, and a
/// literal is a corner that quietly stops following `theme.shape` in
/// `packages/brand/brand.json` while every corner around it moves.
///
/// The values themselves live in the generated [BrandShape] — this class is the
/// ergonomic face of it, and the reason call sites do not import a file with a
/// DO NOT EDIT header at the top.
///
/// Everything is `static const` rather than a [ThemeExtension] on purpose. The
/// scale does not vary by brightness, and a compile-time constant keeps
/// `const BorderRadius.all(...)` const at the call site, which is worth more
/// here than the symmetry with [AppColors]-style lookups would be.
class AppRadii {
  const AppRadii._();

  /// Grabbers, progress bars, hairline indicators.
  static const double hairline = BrandShape.radiusHairline;

  /// Chips, badges, small inputs.
  static const double xs = BrandShape.radiusXs;

  /// Small chips and inline pills.
  static const double xsPlus = BrandShape.radiusXsPlus;

  /// Buttons, list rows, thumbnails.
  static const double sm = BrandShape.radiusSm;

  /// Compact cards and banners.
  static const double smPlus = BrandShape.radiusSmPlus;

  /// The workhorse: cards, sheets, most containers.
  static const double md = BrandShape.radiusMd;

  /// Cards that sit above other cards.
  static const double mdPlus = BrandShape.radiusMdPlus;

  /// Large cards and modals.
  static const double lg = BrandShape.radiusLg;

  /// Bottom sheet tops and full-width panels.
  static const double lgPlus = BrandShape.radiusLgPlus;

  /// Hero panels.
  static const double xl = BrandShape.radiusXl;

  /// Stadium-ish buttons that are not quite pills.
  static const double xlPlus = BrandShape.radiusXlPlus;

  /// Avatars and pill buttons: "clamp to half the shorter side". Not scaled by
  /// the shape style, so `sharp` does not turn a circular avatar into a square.
  static const double full = BrandShape.radiusFull;

  /// Ready-made all-corner values, for the common case.
  static const BorderRadius allXs = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius allSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius allMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius allLg = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius allXl = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius allFull = BorderRadius.all(Radius.circular(full));
}
