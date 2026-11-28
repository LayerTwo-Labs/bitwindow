import 'package:flutter/widgets.dart';
import 'package:sail_ui/sail_ui.dart';

/// The color of the dot in a [SailStatusPill].
enum SailStatusTone { success, warning, error, info, neutral }

extension SailStatusToneColor on SailStatusTone {
  Color color(SailColor colors) => switch (this) {
    SailStatusTone.success => colors.success,
    SailStatusTone.warning => colors.warning,
    SailStatusTone.error => colors.error,
    SailStatusTone.info => colors.info,
    SailStatusTone.neutral => colors.textHint,
  };
}

/// A status dot and a label on the form field fill.
class SailStatusPill extends StatelessWidget {
  final String label;
  final SailStatusTone tone;

  const SailStatusPill({super.key, required this.label, this.tone = SailStatusTone.success});

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(color: theme.colors.formField, borderRadius: theme.chrome.radius),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SailStatusDot(tone: tone),
            const SizedBox(width: 8),
            Flexible(child: SailText.primary13(label, color: theme.colors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

/// The 7 px status dot of a [SailStatusPill] or a table row.
class SailStatusDot extends StatelessWidget {
  final SailStatusTone tone;

  const SailStatusDot({super.key, required this.tone});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(shape: BoxShape.circle, color: tone.color(SailTheme.of(context).colors)),
    );
  }
}
