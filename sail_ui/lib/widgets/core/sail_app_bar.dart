import 'package:flutter/material.dart';
import 'package:sail_ui/sail_ui.dart';

class SailAppBar {
  static PreferredSizeWidget build(
    BuildContext context, {
    title,
    Widget? leading,
    bool automaticallyImplyLeading = true,
  }) {
    final theme = SailTheme.of(context);
    final colors = theme.colors;

    return AppBar(
      elevation: 0,
      backgroundColor: colors.background,
      // The v2 icon grey is too faint for the back button, the only control in the bar.
      foregroundColor: theme.isBitwindowV2 ? colors.text : colors.icon,
      centerTitle: false,
      title: title,
      leading:
          leading ??
          (automaticallyImplyLeading && Navigator.canPop(context)
              ? SailButton(
                  variant: ButtonVariant.icon,
                  icon: SailSVGAsset.chevronLeft,
                  onPressed: () async => Navigator.pop(context),
                  iconHeight: 14,
                  iconWidth: 14,
                  small: true,
                )
              : null),
      toolbarHeight: 25,
    );
  }
}
