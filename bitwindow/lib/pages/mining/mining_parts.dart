import 'package:flutter/widgets.dart';
import 'package:sail_ui/sail_ui.dart';

/// A key number in a mining strip: a label with an optional info icon, the value and a grey line under it.
class MiningStat extends StatelessWidget {
  final String label;
  final String value;
  final String? subtitle;
  final String? info;
  final Color? valueColor;

  const MiningStat({super.key, required this.label, required this.value, this.subtitle, this.info, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return SailColumn(
      spacing: 2,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SailRow(
          spacing: SailStyleValues.padding04,
          children: [
            SailText.secondary12(label),
            if (info != null) SailInfoIcon(title: label, message: info!, size: 12),
          ],
        ),
        SailText.primary18(value, color: valueColor),
        if (subtitle != null) SailText.secondary12(subtitle!),
      ],
    );
  }
}

/// The title of a mining strip, with the subtitle or an error under it.
class MiningStripLead extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? error;

  const MiningStripLead({super.key, required this.title, this.subtitle, this.error});

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: SailColumn(
        spacing: SailStyleValues.padding04,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SailText.primary16(title, bold: true),
          if (error != null)
            SailText.primary12(error!, color: theme.colors.error)
          else if (subtitle != null)
            SailText.secondary12(subtitle!),
        ],
      ),
    );
  }
}
