import 'package:flutter/widgets.dart';
import 'package:sail_ui/sail_ui.dart';

/// The thin card at the top of a page: a lead such as a big amount, the key numbers, a status and the main actions.
class SailStrip extends StatelessWidget {
  final Widget? lead;

  /// Usually [SailStat]s.
  final List<Widget> stats;
  final Widget? status;
  final List<Widget> actions;

  const SailStrip({
    super.key,
    this.lead,
    this.stats = const [],
    this.status,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    return DecoratedBox(
      decoration: theme.chrome.panel(theme.colors),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            if (lead != null) ...[lead!, const SizedBox(width: 40)],
            Expanded(
              child: Wrap(
                spacing: 40,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: stats,
              ),
            ),
            if (status != null) ...[const SizedBox(width: 12), status!],
            for (final action in actions) ...[const SizedBox(width: 8), action],
          ],
        ),
      ),
    );
  }
}
