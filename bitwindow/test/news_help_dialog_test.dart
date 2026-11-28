import 'package:bitwindow/pages/overview_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sail_ui/sail_ui.dart';

void main() {
  Future<void> open(WidgetTester tester, SailThemeData theme) async {
    await tester.pumpWidget(
      SailTheme(
        data: theme,
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showNewsHelp(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('in v2 News Help has only the × and no OK', (tester) async {
    await open(
      tester,
      SailThemeData.lightTheme(SailColorScheme.orange, false, SailFontValues.inter, SailThemeStyle.bitwindowV2),
    );

    expect(find.text('News Help'), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is SailButton && w.label == 'OK'), findsNothing);
    expect(find.byType(SailIconBoxButton), findsOneWidget);

    await tester.tap(find.byType(SailIconBoxButton));
    await tester.pumpAndSettle();
    expect(find.text('News Help'), findsNothing);
  });

  testWidgets('other themes keep the OK button', (tester) async {
    await open(tester, SailThemeData.lightTheme(SailColorScheme.orange, false, SailFontValues.inter));

    await tester.tap(find.byWidgetPredicate((w) => w is SailButton && w.label == 'OK'));
    await tester.pumpAndSettle();
    expect(find.text('News Help'), findsNothing);
  });
}
