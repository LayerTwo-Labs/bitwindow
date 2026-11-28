import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';

SailThemeData _theme({required bool light}) => light
    ? SailThemeData.lightTheme(SailColorScheme.orange, false, SailFontValues.inter, SailThemeStyle.bitwindowV2)
    : SailThemeData.darkTheme(SailColorScheme.orange, false, SailFontValues.inter, SailThemeStyle.bitwindowV2);

class _Update extends ChangeNotifier implements UpdateProvider {
  @override
  bool updateAvailable = true;

  @override
  String? latestVersion = '1.1.0';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() => GetIt.I.registerSingleton<UpdateProvider>(_Update()));

  tearDown(() => GetIt.I.reset());

  for (final light in [true, false]) {
    testWidgets('the update chip takes the theme success color in ${light ? 'light' : 'dark'} mode', (tester) async {
      final theme = _theme(light: light);
      await tester.pumpWidget(
        SailTheme(
          data: theme,
          child: const MaterialApp(home: Scaffold(body: UpdateIndicator())),
        ),
      );

      expect(tester.widget<Text>(find.text('Update available')).style?.color, theme.colors.success);
    });
  }
}
