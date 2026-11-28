import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/pages/console_tab_page.dart';
import 'package:sail_ui/sail_ui.dart';

void main() {
  setUp(() async => GetIt.I.reset());

  for (final (style, card) in [(SailThemeStyle.bitwindowV2, true), (SailThemeStyle.sail, false)]) {
    testWidgets('the console tab ${card ? 'sits in one card' : 'has no card'} in the $style style', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SailTheme(
            data: SailThemeData.lightTheme(SailColorScheme.orange, true, SailFontValues.inter, style),
            child: const Scaffold(body: ConsoleTabPage()),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(CLIConsoleView), findsOneWidget);
      expect(
        find.ancestor(of: find.byType(CLIConsoleView), matching: find.byType(SailCard)),
        card ? findsOneWidget : findsNothing,
      );
    });
  }
}
