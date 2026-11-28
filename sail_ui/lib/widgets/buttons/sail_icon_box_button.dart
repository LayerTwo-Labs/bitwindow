import 'package:flutter/widgets.dart';
import 'package:sail_ui/sail_ui.dart';

/// A 28 px square icon button with the form field fill, for example the × of a panel.
class SailIconBoxButton extends StatelessWidget {
  final SailSVGAsset icon;
  final Future<void> Function()? onPressed;
  final String? tooltip;
  final double size;

  const SailIconBoxButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.size = 28,
  });

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    final button = DecoratedBox(
      decoration: BoxDecoration(color: theme.colors.formField, borderRadius: theme.chrome.radius),
      child: SailTappable(
        onTap: onPressed,
        borderRadius: theme.chrome.radius,
        hoverColor: theme.colors.text.withValues(alpha: 0.06),
        child: SizedBox(
          width: size,
          height: size,
          child: Center(
            child: SailSVG.fromAsset(icon, width: 14, height: 14, color: theme.colors.text),
          ),
        ),
      ),
    );
    return tooltip == null ? button : SailTooltip(message: tooltip!, child: button);
  }
}

/// The "…" button that opens a [SailMenu] of [items] under it. An empty list opens nothing.
class SailRowMenuButton extends StatelessWidget {
  final List<SailMenuEntity> Function() items;
  final String tooltip;

  /// False draws only the icon, as at the end of a table row.
  final bool filled;

  /// The side of the filled box, for example 36 next to a button.
  final double size;

  const SailRowMenuButton({
    super.key,
    required this.items,
    this.tooltip = 'More actions',
    this.filled = true,
    this.size = 28,
  });

  Future<void> _open(BuildContext context) async {
    final entries = items();
    if (entries.isEmpty) {
      return;
    }
    final box = context.findRenderObject()! as RenderBox;
    final overlay = Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final anchor = box.localToGlobal(box.size.bottomRight(const Offset(0, 4)), ancestor: overlay);
    await showSailMenu(
      context: context,
      preferredAnchorPoint: anchor,
      alignment: Alignment.topRight,
      menu: SailMenu(items: entries),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (filled) {
      return SailIconBoxButton(
        icon: SailSVGAsset.ellipsis,
        tooltip: tooltip,
        size: size,
        onPressed: () => _open(context),
      );
    }
    final theme = SailTheme.of(context);
    return SailTooltip(
      message: tooltip,
      child: SailTappable(
        onTap: () => _open(context),
        borderRadius: theme.chrome.radius,
        child: SizedBox(
          width: 28,
          height: 28,
          child: Center(
            child: SailSVG.fromAsset(SailSVGAsset.ellipsis, width: 14, height: 14, color: theme.colors.textSecondary),
          ),
        ),
      ),
    );
  }
}
