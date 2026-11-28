import 'package:flutter/widgets.dart';
import 'package:sail_ui/sail_ui.dart';

/// One segmented control: the active segment is a raised box.
class Segments<T> extends StatelessWidget {
  final List<(T, String)> items;
  final T? value;
  final ValueChanged<T> onChanged;

  /// Splits the full width between the segments.
  final bool expand;

  const Segments({super.key, required this.items, required this.value, required this.onChanged, this.expand = false});

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    final box = DecoratedBox(
      decoration: BoxDecoration(color: theme.colors.formField, borderRadius: theme.chrome.radius),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          children: [
            for (final (item, label) in items)
              if (expand) Expanded(child: _segment(theme, item, label)) else _segment(theme, item, label),
          ],
        ),
      ),
    );
    return expand ? box : SingleChildScrollView(scrollDirection: Axis.horizontal, child: box);
  }
}

extension<T> on Segments<T> {
  Widget _segment(SailThemeData theme, T item, String label) {
    return SailTappable(
      onTap: () async => onChanged(item),
      borderRadius: theme.chrome.radiusSmall,
      child: Container(
        alignment: expand ? Alignment.center : null,
        padding: const EdgeInsets.symmetric(horizontal: SailStyleValues.padding12, vertical: 6),
        decoration: BoxDecoration(
          color: item == value ? theme.colors.backgroundSecondary : null,
          borderRadius: theme.chrome.radiusSmall,
        ),
        child: SailText.primary13(
          label,
          bold: item == value,
          color: item == value ? theme.colors.text : theme.colors.textSecondary,
        ),
      ),
    );
  }
}

/// "‹ Markets": the link back to the market list.
class BackLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const BackLink({super.key, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    return SailTappable(
      onTap: () async => onTap(),
      borderRadius: theme.chrome.radius,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SailSVG.fromAsset(SailSVGAsset.chevronLeft, width: 14, height: 14, color: theme.colors.text),
            const SizedBox(width: 6),
            SailText.primary13(label),
          ],
        ),
      ),
    );
  }
}

/// A status dot and its label, with an optional grey line under it.
class StatusDotCell extends StatelessWidget {
  final String label;
  final SailStatusTone tone;
  final String? secondary;

  const StatusDotCell({super.key, required this.label, required this.tone, this.secondary});

  @override
  Widget build(BuildContext context) {
    final line = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SailStatusDot(tone: tone),
        const SizedBox(width: 6),
        Flexible(child: SailText.primary13(label)),
      ],
    );
    if (secondary == null) {
      return line;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [line, SailText.secondary12(secondary!)],
    );
  }
}

/// The head card of a page: title and a grey line at the left, key numbers, and a "…" menu.
class PageHeadCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> extra;
  final List<Widget> stats;
  final List<SailMenuEntity> Function() menuItems;

  const PageHeadCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.extra = const [],
    required this.stats,
    required this.menuItems,
  });

  @override
  Widget build(BuildContext context) {
    final head = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SailText.primary16(title, bold: true),
        const SizedBox(height: 2),
        SailText.secondary12(subtitle),
        for (final widget in extra) ...[const SizedBox(height: 6), widget],
      ],
    );
    final menu = SailRowMenuButton(items: menuItems);

    return SailCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 760) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: head),
                    menu,
                  ],
                ),
                const SizedBox(height: SailStyleValues.padding12),
                Wrap(spacing: 40, runSpacing: 12, children: stats),
              ],
            );
          }
          return Row(
            children: [
              ConstrainedBox(constraints: const BoxConstraints(maxWidth: 360), child: head),
              const SizedBox(width: 40),
              Expanded(child: Wrap(spacing: 40, runSpacing: 12, children: stats)),
              const SizedBox(width: 12),
              menu,
            ],
          );
        },
      ),
    );
  }
}

/// A big number in a [PageHeadCard]: label, value, and a grey line.
class HeadStat extends StatelessWidget {
  final String label;
  final String value;
  final String caption;
  final Color? valueColor;

  const HeadStat({super.key, required this.label, required this.value, required this.caption, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SailText.secondary12(label),
        SailText.primary22(value, bold: true, color: valueColor),
        SailText.secondary12(caption),
      ],
    );
  }
}

/// A menu item with a plain label.
SailMenuItem menuItem(String label, VoidCallback onSelected) =>
    SailMenuItem(onSelected: onSelected, child: SailText.primary12(label));
