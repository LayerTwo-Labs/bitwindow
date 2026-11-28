import 'package:flutter/widgets.dart';
import 'package:sail_ui/sail_ui.dart';

/// The detail card at the right of a page: a head with a title, a "…" menu and a ×, over a body that scrolls.
class SailSidePanel extends StatelessWidget {
  static const double width = 380;

  final String title;
  final Widget? lead;

  /// The actions of the "…" menu. Null hides the menu.
  final List<SailMenuEntity> Function()? menuItems;

  /// Null hides the ×.
  final Future<void> Function()? onClose;

  /// Defaults to [width].
  final double panelWidth;
  final Widget child;

  const SailSidePanel({
    super.key,
    required this.title,
    required this.child,
    this.lead,
    this.menuItems,
    this.onClose,
    this.panelWidth = width,
  });

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    final head = Row(
      children: [
        if (lead != null) ...[lead!, const SizedBox(width: 8)],
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 2),
            style: SailStyleValues.sixteen.copyWith(
              color: theme.colors.text,
              fontWeight: FontWeight.w600,
              fontFamily: theme.chrome.textFamily(),
            ),
          ),
        ),
        if (menuItems != null) ...[const SizedBox(width: 8), SailRowMenuButton(items: menuItems!)],
        if (onClose != null) ...[
          const SizedBox(width: 8),
          SailIconBoxButton(icon: SailSVGAsset.x, tooltip: 'Close', onPressed: onClose),
        ],
      ],
    );

    return SizedBox(
      width: panelWidth,
      child: DecoratedBox(
        decoration: theme.chrome.panel(theme.colors),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (!constraints.hasBoundedHeight) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [head, const SizedBox(height: 14), child],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  head,
                  const SizedBox(height: 14),
                  Expanded(child: SingleChildScrollView(child: child)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
