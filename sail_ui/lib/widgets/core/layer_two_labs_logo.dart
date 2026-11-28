import 'package:flutter/widgets.dart';
import 'package:sail_ui/sail_ui.dart';

/// The LayerTwo Labs logo. In a light theme its white and grey faces take the text color, so they show on the light background.
class LayerTwoLabsLogo extends StatelessWidget {
  final double height;

  const LayerTwoLabsLogo({super.key, this.height = 71});

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    final logo = SailSVG.fromAsset(SailSVGAsset.layerTwoLabsLogo, height: height);
    if (!theme.isLightMode()) {
      return logo;
    }
    return Stack(
      children: [
        logo,
        ColorFiltered(colorFilter: lightFacesFilter(theme.colors.text), child: logo),
      ],
    );
  }

  /// Paints [color] over the white faces and half over the grey faces. The red faces have almost no green, so they stay clear.
  @visibleForTesting
  static ColorFilter lightFacesFilter(Color color) {
    return ColorFilter.matrix([
      0, 0, 0, 0, color.r * 255, //
      0, 0, 0, 0, color.g * 255, //
      0, 0, 0, 0, color.b * 255, //
      0, 1.92, 0, 1, -1.86 * 255, //
    ]);
  }
}
