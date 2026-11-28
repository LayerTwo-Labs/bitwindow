import 'package:flutter/widgets.dart';
import 'package:sail_ui/sail_ui.dart';

/// The segmented control at the top left of the explorer.
class ExplorerSegments extends StatelessWidget {
  final List<String> labels;
  final int activeIndex;
  final ValueChanged<int> onSelect;

  const ExplorerSegments({super.key, required this.labels, required this.activeIndex, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(color: theme.colors.formField, borderRadius: theme.chrome.radius),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (index, label) in labels.indexed)
              SailTappable(
                onTap: () async => onSelect(index),
                borderRadius: theme.chrome.radiusSmall,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: SailStyleValues.padding12, vertical: 6),
                  decoration: BoxDecoration(
                    color: index == activeIndex ? theme.colors.backgroundSecondary : null,
                    borderRadius: theme.chrome.radiusSmall,
                  ),
                  child: SailText.primary13(
                    label,
                    bold: index == activeIndex,
                    color: index == activeIndex ? theme.colors.text : theme.colors.textSecondary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A status dot and its label, for a table cell.
class ExplorerStatus extends StatelessWidget {
  final String label;
  final SailStatusTone tone;

  const ExplorerStatus({super.key, required this.label, required this.tone});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SailStatusDot(tone: tone),
        const SizedBox(width: 6),
        Flexible(child: SailText.primary13(label)),
      ],
    );
  }
}
