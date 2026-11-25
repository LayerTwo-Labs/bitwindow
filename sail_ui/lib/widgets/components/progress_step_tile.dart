import 'package:flutter/material.dart';
import 'package:sail_ui/sail_ui.dart';

class ProgressStepTile extends StatelessWidget {
  final String name;
  final bool isCompleted;
  final bool isFailed;
  final Duration? duration;
  final bool isActive;

  const ProgressStepTile({
    super.key,
    required this.name,
    required this.isCompleted,
    required this.isActive,
    this.isFailed = false,
    this.duration,
  });

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);

    Widget iconWidget;
    String timeText = '';

    final resultColor = isFailed ? theme.colors.error : SailColorScheme.green;
    if (isCompleted || isFailed) {
      iconWidget = SailSVG.fromAsset(
        isFailed ? SailSVGAsset.circleX : SailSVGAsset.circleCheck,
        color: resultColor,
        width: 16,
        height: 16,
      );
      if (duration != null) {
        final d = duration!;
        if (d.inSeconds > 0) {
          timeText = '${d.inSeconds}.${(d.inMilliseconds % 1000).toString().padLeft(3, '0')}s';
        } else {
          timeText = '${d.inMilliseconds}ms';
        }
      }
    } else if (isActive) {
      iconWidget = SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
          strokeWidth: 1,
          valueColor: AlwaysStoppedAnimation<Color>(theme.colors.primary),
        ),
      );
    } else {
      iconWidget = SailSVG.fromAsset(
        SailSVGAsset.circle,
        color: theme.colors.textSecondary,
        width: 16,
        height: 16,
      );
    }

    return SailRow(
      spacing: SailStyleValues.padding04,
      children: [
        SizedBox(width: 16, child: iconWidget),
        Expanded(
          child: SailText.primary13(
            name,
            color: isFailed
                ? resultColor
                : isActive
                ? theme.colors.primary
                : isCompleted
                ? resultColor
                : theme.colors.textSecondary,
          ),
        ),
        if (timeText.isNotEmpty) SailText.secondary12(timeText, color: resultColor),
      ],
    );
  }
}
