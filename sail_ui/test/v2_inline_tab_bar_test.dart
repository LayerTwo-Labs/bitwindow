import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sail_ui/sail_ui.dart';

SailThemeData _theme(SailThemeStyle style, {bool light = true}) => light
    ? SailThemeData.lightTheme(
        SailColorScheme.orange,
        true,
        SailFontValues.inter,
        style,
      )
    : SailThemeData.darkTheme(
        SailColorScheme.orange,
        true,
        SailFontValues.inter,
        style,
      );

Widget _app(SailThemeData theme) => MaterialApp(
  home: SailTheme(
    data: theme,
    child: Scaffold(
      body: SizedBox(
        width: 800,
        height: 400,
        child: InlineTabBar(
          tabs: [
            const TabItem(label: 'Overview', child: Text('Overview body')),
            const TabItem(label: 'Send', child: Text('Send body')),
            MultiSelectTabItem(
              title: 'Tools',
              items: const [
                TabItem(label: 'Deniability', child: Text('Deniability body')),
                TabItem(label: 'Consolidate', child: Text('Consolidate body')),
              ],
            ),
          ],
        ),
      ),
    ),
  ),
);

BoxDecoration? _segment(WidgetTester tester, String label) {
  final item = find.ancestor(
    of: find.text(label),
    matching: find.byType(SailTabItem),
  );
  final box = tester.widget<Container>(
    find.descendant(of: item, matching: find.byType(Container)).first,
  );
  return box.decoration as BoxDecoration?;
}

Text _label(WidgetTester tester, String label) => tester.widget<Text>(find.text(label));

void main() {
  for (final light in [true, false]) {
    final mode = light ? 'light' : 'dark';

    testWidgets('a BitWindow v2 tab row is a segmented control in $mode mode', (
      tester,
    ) async {
      final theme = _theme(SailThemeStyle.bitwindowV2, light: light);
      await tester.pumpWidget(_app(theme));

      final track = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(InlineTabBar),
              matching: find.byType(Container),
            ),
          )
          .first;
      final trackDecoration = track.decoration! as BoxDecoration;
      expect(trackDecoration.color, theme.colors.formField);
      expect(
        trackDecoration.borderRadius,
        const BorderRadius.all(Radius.circular(6)),
      );
      expect(track.padding, const EdgeInsets.all(3));

      final active = _segment(tester, 'Overview')!;
      expect(active.color, theme.colors.backgroundSecondary);
      expect(active.borderRadius, const BorderRadius.all(Radius.circular(4)));
      expect(_label(tester, 'Overview').style!.fontWeight, FontWeight.w600);
      expect(_label(tester, 'Overview').style!.color, theme.colors.text);

      expect(_segment(tester, 'Send')!.color, Colors.transparent);
      expect(_label(tester, 'Send').style!.color, theme.colors.textSecondary);
    });
  }

  testWidgets('a tap on a BitWindow v2 segment selects it', (tester) async {
    final theme = _theme(SailThemeStyle.bitwindowV2);
    await tester.pumpWidget(_app(theme));

    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(find.text('Send body'), findsOneWidget);
    expect(_segment(tester, 'Send')!.color, theme.colors.backgroundSecondary);
    expect(_segment(tester, 'Overview')!.color, Colors.transparent);
  });

  testWidgets('the BitWindow v2 dropdown segment still opens its items', (
    tester,
  ) async {
    final theme = _theme(SailThemeStyle.bitwindowV2);
    await tester.pumpWidget(_app(theme));

    await tester.tap(find.text('Tools'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Consolidate'));
    await tester.pumpAndSettle();

    expect(find.text('Consolidate body'), findsOneWidget);
    expect(
      _segment(tester, 'Consolidate')!.color,
      theme.colors.backgroundSecondary,
    );
  });

  testWidgets('a sail tab row keeps its look', (tester) async {
    final theme = _theme(SailThemeStyle.sail);
    await tester.pumpWidget(_app(theme));

    expect(_segment(tester, 'Overview')!.color, theme.colors.background);
    expect(_segment(tester, 'Overview')!.borderRadius, theme.chrome.radius);
  });

  testWidgets('a leading widget puts the strip at the right of the head', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SailTheme(
          data: _theme(SailThemeStyle.bitwindowV2),
          child: const Scaffold(
            body: SizedBox(
              width: 800,
              height: 400,
              child: InlineTabBar(
                leading: Text('Transaction (by id)'),
                tabs: [
                  TabItem(label: 'Overview', child: Text('Overview body')),
                  TabItem(label: 'Bytes', child: Text('Bytes body')),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final title = tester.getRect(find.text('Transaction (by id)'));
    final bytes = tester.getRect(find.text('Bytes'));
    expect(title.left, 0);
    expect(bytes.center.dy, closeTo(title.center.dy, 2));
    expect(bytes.right, greaterThan(760));
    expect(
      tester.getTopLeft(find.text('Overview body')).dy,
      greaterThan(title.bottom),
    );

    await tester.tap(find.text('Bytes'));
    await tester.pumpAndSettle();
    expect(find.text('Bytes body'), findsOneWidget);
  });
}
