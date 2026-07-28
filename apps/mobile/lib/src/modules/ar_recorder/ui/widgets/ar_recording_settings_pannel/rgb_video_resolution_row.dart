import "package:stera/src/core/common/widgets/choice_chip_row.dart";
import "package:flutter/material.dart";
import "package:stera_recorder/stera_recorder.dart";

class RgbVideoResolutionRow extends StatelessWidget {
  const RgbVideoResolutionRow({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final RgbVideoResolution value;
  final ValueChanged<RgbVideoResolution> onChanged;

  static List<RgbVideoResolution> get _options => RgbVideoResolution.supported;

  @override
  Widget build(BuildContext context) {
    return ChoiceChipRow<RgbVideoResolution>(
      title: "Video resolution",
      subtitle: value.subtitle,
      options: _options,
      value: value,
      labelBuilder: (r) => r.label,
      onChanged: onChanged,
    );
  }
}
