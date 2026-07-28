import "package:stera/src/core/theme/brand_type.dart";
import "package:stera/src/core/theme/colors.dart";
import "package:flutter/widgets.dart";

class AppTextTheme {
  // Headings - 4xl
  final TextStyle head4XlGaramond;
  final TextStyle head4XlHandjet;
  final TextStyle head4Xl;

  // Headings - 3xl
  final TextStyle head3XlGaramond;
  final TextStyle head3XlHandjet;
  final TextStyle head3Xl;

  // Headings - 2xl, xl, lg, md, sm
  final TextStyle head2Xl;
  final TextStyle headXl;
  final TextStyle headLg;
  final TextStyle headMd;
  final TextStyle headSm;

  // Body - lg
  final TextStyle bodyLgMedium;
  final TextStyle bodyLg;

  // Body - md
  final TextStyle bodyMdMedium;
  final TextStyle bodyMd;

  // Body - sm
  final TextStyle bodySmMedium;
  final TextStyle bodySm;
  final TextStyle bodySmMono;

  // Body - xs
  final TextStyle bodyXsMedium;
  final TextStyle bodyXs;
  final TextStyle bodyXsMono;

  AppTextTheme({
    required this.head4XlGaramond,
    required this.head4XlHandjet,
    required this.head4Xl,
    required this.head3XlGaramond,
    required this.head3XlHandjet,
    required this.head3Xl,
    required this.head2Xl,
    required this.headXl,
    required this.headLg,
    required this.headMd,
    required this.headSm,
    required this.bodyLgMedium,
    required this.bodyLg,
    required this.bodyMdMedium,
    required this.bodyMd,
    required this.bodySmMedium,
    required this.bodySm,
    required this.bodySmMono,
    required this.bodyXsMedium,
    required this.bodyXs,
    required this.bodyXsMono,
  });

  factory AppTextTheme.fromColors(C colors) {
    return AppTextTheme(
      // Headings - 4xl
      head4XlGaramond: TextStyle(
        fontFamily: "EBGaramond",
        fontSize: BrandType.sizeXl4,
        fontWeight: BrandType.weightMedium,
        height: BrandType.heightXl4,
        color: colors.textPrimary,
      ),
      head4XlHandjet: TextStyle(
        fontFamily: "Handjet",
        fontSize: BrandType.sizeXl4,
        fontWeight: BrandType.weightMedium,
        height: BrandType.heightXl4,
        color: colors.textPrimary,
      ),
      head4Xl: TextStyle(
        fontFamily: "Geist",
        fontSize: BrandType.sizeXl4,
        fontWeight: BrandType.weightBold,
        height: BrandType.heightXl4,
        color: colors.textPrimary,
      ),

      // Headings - 3xl
      head3XlGaramond: TextStyle(
        fontFamily: "EBGaramond",
        fontSize: BrandType.sizeXl3,
        fontWeight: BrandType.weightMedium,
        height: BrandType.heightXl3,
        color: colors.textPrimary,
      ),
      head3XlHandjet: TextStyle(
        fontFamily: "Handjet",
        fontSize: BrandType.sizeXl3,
        fontWeight: BrandType.weightMedium,
        height: BrandType.heightXl3,
        color: colors.textPrimary,
      ),
      head3Xl: TextStyle(
        fontFamily: "Geist",
        fontSize: BrandType.sizeXl3,
        fontWeight: BrandType.weightBold,
        height: BrandType.heightXl3,
        color: colors.textPrimary,
      ),

      // Headings - 2xl
      head2Xl: TextStyle(
        fontFamily: "Geist",
        fontSize: BrandType.sizeXl2,
        fontWeight: BrandType.weightSemibold,
        height: BrandType.heightXl2,
        color: colors.textPrimary,
      ),

      // Headings - xl
      headXl: TextStyle(
        fontFamily: "Geist",
        fontSize: BrandType.sizeXl,
        fontWeight: BrandType.weightSemibold,
        height: BrandType.heightXl,
        color: colors.textPrimary,
      ),

      // Headings - lg
      headLg: TextStyle(
        fontFamily: "Geist",
        fontSize: BrandType.sizeLg,
        fontWeight: BrandType.weightSemibold,
        height: BrandType.heightLg,
        color: colors.textPrimary,
      ),

      // Headings - md
      headMd: TextStyle(
        fontFamily: "Geist",
        fontSize: BrandType.sizeMd,
        fontWeight: BrandType.weightSemibold,
        height: BrandType.heightMd,
        color: colors.textPrimary,
      ),

      // Headings - sm
      headSm: TextStyle(
        fontFamily: "Geist",
        fontSize: BrandType.sizeSm,
        fontWeight: BrandType.weightSemibold,
        height: BrandType.heightSm,
        color: colors.textPrimary,
      ),

      // Body - lg
      bodyLgMedium: TextStyle(
        fontFamily: "Geist",
        fontSize: BrandType.sizeLg,
        fontWeight: BrandType.weightMedium,
        height: BrandType.heightLg,
        color: colors.textPrimary,
      ),
      bodyLg: TextStyle(
        fontFamily: "Geist",
        fontSize: BrandType.sizeLg,
        fontWeight: BrandType.weightRegular,
        height: BrandType.heightLg,
        color: colors.textPrimary,
      ),

      // Body - md
      bodyMdMedium: TextStyle(
        fontFamily: "Geist",
        fontSize: BrandType.sizeMd,
        fontWeight: BrandType.weightMedium,
        height: BrandType.heightMd,
        color: colors.textPrimary,
      ),
      bodyMd: TextStyle(
        fontFamily: "Geist",
        fontSize: BrandType.sizeMd,
        fontWeight: BrandType.weightRegular,
        height: BrandType.heightMd,
        color: colors.textPrimary,
      ),

      // Body - sm
      bodySmMedium: TextStyle(
        fontFamily: "Geist",
        fontSize: BrandType.sizeSm,
        fontWeight: BrandType.weightMedium,
        height: BrandType.heightSm,
        color: colors.textPrimary,
      ),
      bodySm: TextStyle(
        fontFamily: "Geist",
        fontSize: BrandType.sizeSm,
        fontWeight: BrandType.weightRegular,
        height: BrandType.heightSm,
        color: colors.textPrimary,
      ),
      bodySmMono: TextStyle(
        fontFamily: "GeistMono",
        fontSize: BrandType.sizeSm,
        fontWeight: BrandType.weightRegular,
        height: BrandType.heightSm,
        color: colors.textPrimary,
      ),

      // Body - xs
      bodyXsMedium: TextStyle(
        fontFamily: "Geist",
        fontSize: BrandType.sizeXs,
        fontWeight: BrandType.weightMedium,
        height: BrandType.heightXs,
        color: colors.textPrimary,
      ),
      bodyXs: TextStyle(
        fontFamily: "Geist",
        fontSize: BrandType.sizeXs,
        fontWeight: BrandType.weightRegular,
        height: BrandType.heightXs,
        color: colors.textPrimary,
      ),
      bodyXsMono: TextStyle(
        fontFamily: "GeistMono",
        fontSize: BrandType.sizeXs,
        fontWeight: BrandType.weightRegular,
        height: BrandType.heightXs,
        color: colors.textPrimary,
      ),
    );
  }
}
