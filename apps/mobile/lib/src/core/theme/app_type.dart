import "package:stera/src/core/theme/brand_type.dart";
import "package:flutter/widgets.dart";

/// The typographic scale, as the app consumes it.
///
/// Nothing in `lib/` should spell a font size or a weight as a number:
/// `brand:verify` fails the build if it does, and a literal is a piece of text
/// that quietly stops following `theme.type` in `packages/brand/brand.json`
/// while every label around it moves.
///
/// Most text should not come through here at all — reach for a named style on
/// `context.textTheme`, which pairs a size with a weight, a line height and a
/// colour. [AppType] is for the two cases a named style cannot serve: a
/// `copyWith` that changes only the weight, and chrome drawn over video where
/// the size is doing layout work.
///
/// The values live in the generated [BrandType]; this class is the ergonomic
/// face of it, which is why call sites do not import a file with a DO NOT EDIT
/// header at the top. Same arrangement as [AppRadii] and for the same reason.
class AppType {
  const AppType._();

  /// Captions, dense metadata.
  static const double xs = BrandType.sizeXs;

  /// Secondary labels, timestamps.
  static const double sm = BrandType.sizeSm;

  /// The workhorse body size.
  static const double md = BrandType.sizeMd;

  /// Emphasised body, list titles.
  static const double lg = BrandType.sizeLg;

  /// Section headings.
  static const double xl = BrandType.sizeXl;

  /// Sheet titles.
  static const double xl2 = BrandType.sizeXl2;

  /// Screen headings.
  static const double xl3 = BrandType.sizeXl3;

  /// Page titles.
  static const double xl3Plus = BrandType.sizeXl3Plus;

  /// The display size: splash wordmark, hero numerals.
  static const double xl4 = BrandType.sizeXl4;

  /// Body copy.
  static const FontWeight regular = BrandType.weightRegular;

  /// Emphasised body, secondary labels.
  static const FontWeight medium = BrandType.weightMedium;

  /// Headings and interactive labels.
  static const FontWeight semibold = BrandType.weightSemibold;

  /// Page titles and the display sizes.
  static const FontWeight bold = BrandType.weightBold;
}
