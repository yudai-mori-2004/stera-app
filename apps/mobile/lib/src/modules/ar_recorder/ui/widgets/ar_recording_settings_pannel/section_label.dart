import "package:stera/src/core/common/utils/extensions.dart";
import "package:flutter/material.dart";

class SectionLabel extends StatelessWidget {
  const SectionLabel({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: context.textTheme.bodyXsMedium.copyWith(
        color: context.colors.textTertiary,
        letterSpacing: 0.6,
      ),
    );
  }
}
