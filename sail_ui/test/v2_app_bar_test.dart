import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sail_ui/sail_ui.dart';

import 'svg_finder.dart';

SailThemeData _theme(SailThemeStyle style, {bool light = true}) => light
    ? SailThemeData.lightTheme(SailColorScheme.orange, true, SailFontValues.inter, style)
    : SailThemeData.darkTheme(SailColorScheme.orange, true, SailFontValues.inter, style);

Future<ColorFilter?> _backIconTint(WidgetTester tester, SailThemeData theme) async {
  await tester.pumpWidget(
    MaterialApp(
      home: SailTheme(
        data: theme,
        child: Builder(
          builder: (context) => Scaffold(
            appBar: SailAppBar.build(context, leading: SailAppBarBackButton(onPressed: () {})),
            body: const SizedBox(),
          ),
        ),
      ),
    ),
  );
  return tester.widget<SvgPicture>(findSailSVG(SailSVGAsset.arrowLeft)).colorFilter;
}

void main() {
  for (final light in [true, false]) {
    testWidgets('the v2 back icon takes the text color, light: $light', (tester) async {
      final theme = _theme(SailThemeStyle.bitwindowV2, light: light);
      expect(await _backIconTint(tester, theme), tint(theme.colors.text));
    });
  }

  testWidgets('other themes keep the icon color', (tester) async {
    final theme = _theme(SailThemeStyle.values.firstWhere((s) => s != SailThemeStyle.bitwindowV2));
    expect(await _backIconTint(tester, theme), tint(theme.colors.icon));
  });
}
