import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sail_ui/sail_ui.dart';

SailThemeData _theme(SailThemeStyle style) =>
    SailThemeData.lightTheme(SailColorScheme.orange, true, SailFontValues.inter, style);

Widget _app(SailThemeData theme) => MaterialApp(
  home: SailTheme(
    data: theme,
    child: Scaffold(
      body: SailSettingsScaffold(
        subtitle: 'Manage your settings',
        selectedIndex: 0,
        onSectionSelected: (_) {},
        sections: [
          SailSettingsSection(
            label: 'Network',
            builder: (_) => const SailSettingsBody(
              children: [
                SailSettingsGroup(
                  title: 'Bitcoin network',
                  children: [SailSettingsRow(label: 'Network')],
                ),
              ],
            ),
          ),
          SailSettingsSection(label: 'Reset', builder: (_) => const SizedBox()),
        ],
      ),
    ),
  ),
);

BoxDecoration _decorationOf(WidgetTester tester, Finder finder) {
  final widget = tester.widget(finder);
  return switch (widget) {
    Container(:final decoration?) => decoration as BoxDecoration,
    DecoratedBox(:final decoration) => decoration as BoxDecoration,
    _ => throw StateError('no decoration on $widget'),
  };
}

void main() {
  testWidgets('v2 puts the section list and each group on a card', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    final theme = _theme(SailThemeStyle.bitwindowV2);
    await tester.pumpWidget(_app(theme));

    final nav = _decorationOf(
      tester,
      find.descendant(of: find.byType(SideNav), matching: find.byType(Container)).first,
    );
    expect(nav, theme.chrome.panel(theme.colors));

    final group = _decorationOf(
      tester,
      find.descendant(of: find.byType(SailSettingsGroup), matching: find.byType(DecoratedBox)).first,
    );
    expect(group, theme.chrome.panel(theme.colors));
    expect(find.byType(SailSeparator), findsNothing);
  });

  testWidgets('other themes keep the divider under the page head', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    await tester.pumpWidget(_app(_theme(SailThemeStyle.values.firstWhere((s) => s != SailThemeStyle.bitwindowV2))));

    expect(find.byType(SailSeparator), findsOneWidget);
  });
}
