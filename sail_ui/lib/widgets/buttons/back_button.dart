import 'package:flutter/material.dart';
import 'package:sail_ui/sail_ui.dart';

class SailAppBarBackButton extends StatelessWidget {
  final VoidCallback? onPressed;

  const SailAppBarBackButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 8),
      child: IconButton(
        icon: Builder(
          builder: (context) {
            final iconTheme = IconTheme.of(context);
            return SailSVG.fromAsset(
              SailSVGAsset.arrowLeft,
              width: iconTheme.size,
              height: iconTheme.size,
              color: iconTheme.color,
            );
          },
        ),
        onPressed: onPressed,
      ),
    );
  }
}
