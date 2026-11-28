import 'package:flutter/widgets.dart';
import 'package:sail_ui/sail_ui.dart';

/// The big value at the top of a side panel, with an optional grey line under it.
class PanelHeadline extends StatelessWidget {
  final String value;
  final String? caption;

  const PanelHeadline({super.key, required this.value, this.caption});

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SailText.primary24(value, bold: true),
        if (caption != null) SailText.primary15(caption!, color: theme.colors.textSecondary),
      ],
    );
  }
}

/// A status dot and its label, for a table cell.
class StatusDotLabel extends StatelessWidget {
  final String label;
  final SailStatusTone tone;
  final Color? textColor;

  const StatusDotLabel({
    super.key,
    required this.label,
    required this.tone,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SailStatusDot(tone: tone),
        const SizedBox(width: 6),
        Flexible(child: SailText.primary13(label, color: textColor)),
      ],
    );
  }
}

/// Splits a formatted amount such as "0.25000000 BTC" into the number and its unit.
(String, String?) splitAmountUnit(String formatted) {
  final space = formatted.lastIndexOf(' ');
  if (space < 0) {
    return (formatted, null);
  }
  return (formatted.substring(0, space), formatted.substring(space + 1));
}

/// The first and last 10 characters of [value].
String shortHash(String value) {
  if (value.length <= 20) {
    return value;
  }
  return '${value.substring(0, 10)}...${value.substring(value.length - 10)}';
}
