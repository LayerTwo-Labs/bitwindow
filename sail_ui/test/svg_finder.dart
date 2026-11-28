import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sail_ui/sail_ui.dart';

Finder findSailSVG(SailSVGAsset asset) => find.byWidgetPredicate(
  (w) =>
      w is SvgPicture &&
      w.bytesLoader is SvgAssetLoader &&
      (w.bytesLoader as SvgAssetLoader).assetName == asset.toAssetPath(),
);

ColorFilter tint(Color color) => ColorFilter.mode(color, BlendMode.srcIn);
