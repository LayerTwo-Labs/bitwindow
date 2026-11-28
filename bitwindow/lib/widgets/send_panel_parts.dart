import 'package:flutter/widgets.dart';
import 'package:sail_ui/sail_ui.dart';

/// The big amount at the top of a side panel, with the same sum in the other unit under it.
class SendAmountBlock extends StatelessWidget {
  final String? label;
  final String amount;
  final String otherUnit;

  /// Swaps the unit of the wallet. Null hides the swap icon.
  final Future<void> Function()? onSwapUnit;

  const SendAmountBlock({
    super.key,
    this.label,
    required this.amount,
    required this.otherUnit,
    this.onSwapUnit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) SailText.primary12(label!, color: theme.colors.textSecondary),
        SailText.primary24(amount, bold: true),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: SailText.primary15(otherUnit, color: theme.colors.textSecondary)),
            if (onSwapUnit != null) ...[
              const SizedBox(width: 6),
              SailTappable(
                key: const Key('send_swap_unit'),
                onTap: onSwapUnit,
                borderRadius: theme.chrome.radius,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: SailSVG.fromAsset(
                    SailSVGAsset.arrowDownUp,
                    width: 14,
                    height: 14,
                    color: theme.colors.textSecondary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// A square dialog: an optional ←, the title, an optional "…" menu and the × in the head, then the body and [button]
/// at full width.
class SignDialog extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? error;
  final Widget? child;
  final Widget? button;
  final Future<void> Function()? onBack;
  final List<SailMenuEntity> Function()? menuItems;

  /// Runs on a tap on the ×. Null pops the route.
  final Future<void> Function()? onClose;

  /// True disables the ← and the ×.
  final bool busy;
  final double maxWidth;

  const SignDialog({
    super.key,
    required this.title,
    this.child,
    this.subtitle,
    this.error,
    this.button,
    this.onBack,
    this.menuItems,
    this.onClose,
    this.busy = false,
    this.maxWidth = 480,
  });

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    final note = error ?? subtitle;
    return SailModal(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: SailCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                if (onBack != null) ...[
                  SailIconBoxButton(icon: SailSVGAsset.arrowLeft, tooltip: 'Back', onPressed: busy ? null : onBack),
                  const SizedBox(width: SailStyleValues.padding08),
                ],
                Expanded(child: SailText.primary16(title, bold: true)),
                if (menuItems != null) ...[
                  const SizedBox(width: SailStyleValues.padding08),
                  SailRowMenuButton(items: menuItems!),
                ],
                const SizedBox(width: SailStyleValues.padding08),
                SailIconBoxButton(
                  icon: SailSVGAsset.x,
                  tooltip: 'Close',
                  onPressed: busy ? null : () async => onClose == null ? Navigator.of(context).pop() : onClose!(),
                ),
              ],
            ),
            if (note != null) ...[
              const SizedBox(height: SailStyleValues.padding08),
              SailText.primary13(
                note,
                color: error != null ? theme.colors.error : theme.colors.textSecondary,
                overflow: TextOverflow.visible,
              ),
            ],
            if (child != null) ...[
              const SizedBox(height: SailStyleValues.padding16),
              Flexible(child: SingleChildScrollView(child: child)),
            ],
            if (button != null) ...[
              const SizedBox(height: SailStyleValues.padding16),
              SizedBox(width: double.infinity, child: button),
            ],
          ],
        ),
      ),
    );
  }
}

/// A plain text item of a "…" menu. A null [onSelected] greys it out.
SailMenuItem sendMenuItem(BuildContext context, String label, VoidCallback? onSelected) => SailMenuItem(
  onSelected: onSelected,
  child: SailText.primary13(label, color: onSelected == null ? SailTheme.of(context).colors.textTertiary : null),
);
