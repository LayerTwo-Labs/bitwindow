import 'package:flutter/widgets.dart';
import 'package:sail_ui/sail_ui.dart';

/// A label in small grey type over its value.
class SailStat extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const SailStat({super.key, required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SailText.primary12(label, bold: true, color: theme.colors.textSecondary),
        const SizedBox(height: 2),
        SailText.primary14(value, bold: true, color: valueColor),
      ],
    );
  }
}
