import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sail_ui/sail_ui.dart';

void main() {
  Future<void> pump(WidgetTester tester, SailThemeData theme) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SailTheme(
          data: theme,
          child: const Center(child: LayerTwoLabsLogo()),
        ),
      ),
    );
  }

  testWidgets('a light theme paints the light faces in the text color', (tester) async {
    final theme = SailThemeData.lightTheme(
      SailColorScheme.orange,
      false,
      SailFontValues.inter,
      SailThemeStyle.bitwindowV2,
    );
    await pump(tester, theme);

    final filtered = tester.widget<ColorFiltered>(find.byType(ColorFiltered));
    expect(filtered.colorFilter, LayerTwoLabsLogo.lightFacesFilter(theme.colors.text));
    expect(find.byType(SvgPicture), findsNWidgets(2));
  });

  testWidgets('a dark theme shows the logo as it is', (tester) async {
    await pump(
      tester,
      SailThemeData.darkTheme(SailColorScheme.orange, false, SailFontValues.inter, SailThemeStyle.bitwindowV2),
    );

    expect(find.byType(ColorFiltered), findsNothing);
    expect(find.byType(SvgPicture), findsOneWidget);
  });
}
