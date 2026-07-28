import "package:stera/src/core/theme/brand_space.dart";
import "package:flutter/widgets.dart";

/// The spacing scale, as the app consumes it.
///
/// Every gap and every pad comes from here. Nothing in `lib/` should spell a
/// gap as a number: `brand:verify` fails the build if it does, and a literal is
/// a widget whose density quietly stops following `theme.space` in
/// `packages/brand/brand.json` while everything around it moves.
///
/// The values live in the generated [BrandSpace]; this class is the ergonomic
/// face of it, same arrangement as [AppRadii] and [AppType]. Everything is
/// `static const`, which keeps `const EdgeInsets.all(...)` const at the call
/// site.
class AppSpacing {
  const AppSpacing._();

  /// No gap.
  static const double none = BrandSpace.none;

  /// Hairline separation: an icon from its label.
  static const double xxs = BrandSpace.xxs;

  /// Tight pairs inside a control.
  static const double xs = BrandSpace.xs;

  /// Chip and badge padding.
  static const double xsPlus = BrandSpace.xsPlus;

  /// The small gap: between a title and its subtitle.
  static const double sm = BrandSpace.sm;

  /// Compact list rows.
  static const double smPlus = BrandSpace.smPlus;

  /// Between related elements in a card.
  static const double md = BrandSpace.md;

  /// Card padding on dense screens.
  static const double mdPlus = BrandSpace.mdPlus;

  /// The workhorse: screen margins and card padding.
  static const double lg = BrandSpace.lg;

  /// Between sections of a form.
  static const double lgPlus = BrandSpace.lgPlus;

  /// Between major sections.
  static const double xl = BrandSpace.xl;

  /// Above a primary action.
  static const double xlPlus = BrandSpace.xlPlus;

  /// Screen-level breathing room.
  static const double xxl = BrandSpace.xxl;

  /// Empty-state and hero spacing.
  static const double huge = BrandSpace.huge;

  /// Ready-made all-round insets, for the common case.
  static const EdgeInsets allSm = EdgeInsets.all(sm);
  static const EdgeInsets allMd = EdgeInsets.all(md);
  static const EdgeInsets allLg = EdgeInsets.all(lg);
  static const EdgeInsets allXl = EdgeInsets.all(xl);

  /// The screen gutter: what a page's content is inset by.
  static const EdgeInsets screen = EdgeInsets.symmetric(horizontal: lg);

  /// Vertical gaps, for the `SizedBox` between two stacked things.
  static const SizedBox gapXs = SizedBox(height: xs);
  static const SizedBox gapSm = SizedBox(height: sm);
  static const SizedBox gapMd = SizedBox(height: md);
  static const SizedBox gapLg = SizedBox(height: lg);
  static const SizedBox gapXl = SizedBox(height: xl);

  /// Horizontal gaps, for the `SizedBox` between two side-by-side things.
  static const SizedBox gapWideXs = SizedBox(width: xs);
  static const SizedBox gapWideSm = SizedBox(width: sm);
  static const SizedBox gapWideMd = SizedBox(width: md);
  static const SizedBox gapWideLg = SizedBox(width: lg);
}
