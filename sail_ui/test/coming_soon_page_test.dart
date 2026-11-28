import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sail_ui/pages/router.dart';
import 'package:sail_ui/sail_ui.dart';

const _message = 'The M4 Explorer is where you would see the status of sidechain withdrawals.';

SailThemeData _theme({required bool light}) => light
    ? SailThemeData.lightTheme(SailColorScheme.orange, false, SailFontValues.inter, SailThemeStyle.bitwindowV2)
    : SailThemeData.darkTheme(SailColorScheme.orange, false, SailFontValues.inter, SailThemeStyle.bitwindowV2);

void main() {
  for (final light in [true, false]) {
    testWidgets('Coming soon is one card on the theme background over the stars in ${light ? 'light' : 'dark'} mode', (
      tester,
    ) async {
      final theme = _theme(light: light);
      await tester.pumpWidget(
        SailTheme(
          data: theme,
          child: MaterialApp(
            home: ComingSoonPage(router: AppRouter(), message: _message),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor, theme.colors.background);
      expect(find.byType(CustomPaint), findsWidgets);

      final card = tester.widget<Container>(find.byKey(const Key('coming-soon-card')));
      expect((card.decoration! as BoxDecoration).color, theme.colors.backgroundSecondary);
      for (final text in ['THIS COULD BE BITCOIN', _message]) {
        expect(
          find.descendant(of: find.byKey(const Key('coming-soon-card')), matching: find.text(text)),
          findsOneWidget,
        );
      }
      expect(find.widgetWithText(SailButton, 'Switch to Signet'), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) => w is SailIconBoxButton && w.icon == SailSVGAsset.chevronLeft),
        findsOneWidget,
      );
    });
  }
}
