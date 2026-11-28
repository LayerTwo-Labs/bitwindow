import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sail_ui/sail_ui.dart';

SailThemeData _v2({bool light = true}) => light
    ? SailThemeData.lightTheme(SailColorScheme.orange, true, SailFontValues.inter, SailThemeStyle.bitwindowV2)
    : SailThemeData.darkTheme(SailColorScheme.orange, true, SailFontValues.inter, SailThemeStyle.bitwindowV2);

Widget _app(SailThemeData theme, Widget child, {Size size = const Size(1200, 800)}) => MaterialApp(
  home: SailTheme(
    data: theme,
    child: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: size.width, height: size.height, child: child),
      ),
    ),
  ),
);

BoxDecoration _boxOf(WidgetTester tester, Finder within) => tester
    .widgetList<DecoratedBox>(find.descendant(of: within, matching: find.byType(DecoratedBox)))
    .map((b) => b.decoration)
    .whereType<BoxDecoration>()
    .first;

void main() {
  group('SailIconBoxButton', () {
    testWidgets('is a 28 px square with the form field fill and calls back on tap', (tester) async {
      var taps = 0;
      final theme = _v2();
      await tester.pumpWidget(
        _app(
          theme,
          Align(
            alignment: Alignment.topLeft,
            child: SailIconBoxButton(icon: SailSVGAsset.x, onPressed: () async => taps++),
          ),
        ),
      );

      expect(tester.getSize(find.byType(SailIconBoxButton)), const Size(28, 28));
      final box = _boxOf(tester, find.byType(SailIconBoxButton));
      expect(box.color, theme.colors.formField);
      expect(box.borderRadius, const BorderRadius.all(Radius.circular(6)));

      await tester.tap(find.byType(SailIconBoxButton));
      expect(taps, 1);
    });
  });

  group('SailRowMenuButton', () {
    testWidgets('opens its menu and runs the picked item', (tester) async {
      final picked = <String>[];
      await tester.pumpWidget(
        _app(
          _v2(),
          Center(
            child: SailRowMenuButton(
              items: () => [
                SailMenuItem(onSelected: () => picked.add('copy'), child: const Text('Copy TXID')),
                SailMenuItem(onSelected: () => picked.add('explorer'), child: const Text('Open in explorer')),
              ],
            ),
          ),
        ),
      );

      expect(tester.getSize(find.byType(SailRowMenuButton)), const Size(28, 28));
      expect(find.text('Copy TXID'), findsNothing);

      await tester.tap(find.byType(SailRowMenuButton));
      await tester.pumpAndSettle();
      expect(find.text('Copy TXID'), findsOneWidget);

      await tester.tap(find.text('Open in explorer'));
      await tester.pumpAndSettle();
      expect(picked, ['explorer']);
      expect(find.text('Copy TXID'), findsNothing);
    });

    testWidgets('an unfilled button draws no fill', (tester) async {
      await tester.pumpWidget(
        _app(
          _v2(),
          Center(child: SailRowMenuButton(filled: false, items: () => [])),
        ),
      );

      expect(find.byType(SailIconBoxButton), findsNothing);
      expect(tester.getSize(find.byType(SailRowMenuButton)), const Size(28, 28));
    });
  });

  group('SailStatusPill', () {
    for (final light in [true, false]) {
      testWidgets('takes its dot color from the tone in ${light ? 'light' : 'dark'} mode', (tester) async {
        final theme = _v2(light: light);
        for (final (tone, color) in [
          (SailStatusTone.success, theme.colors.success),
          (SailStatusTone.warning, theme.colors.warning),
          (SailStatusTone.error, theme.colors.error),
          (SailStatusTone.info, theme.colors.info),
          (SailStatusTone.neutral, theme.colors.textHint),
        ]) {
          await tester.pumpWidget(
            _app(
              theme,
              Align(
                alignment: Alignment.topLeft,
                child: SailStatusPill(label: 'Unconfirmed', tone: tone),
              ),
            ),
          );

          final dot = tester.widget<Container>(find.byType(Container).last).decoration! as BoxDecoration;
          expect(dot.color, color);
          expect(dot.shape, BoxShape.circle);
        }

        final pill = _boxOf(tester, find.byType(SailStatusPill));
        expect(pill.color, theme.colors.formField);
        expect(pill.borderRadius, const BorderRadius.all(Radius.circular(6)));
        expect(find.text('Unconfirmed'), findsOneWidget);
      });
    }
  });

  group('SailStat', () {
    testWidgets('puts a 12 px grey label over a 14 px value', (tester) async {
      final theme = _v2();
      await tester.pumpWidget(
        _app(
          theme,
          const Align(
            alignment: Alignment.topLeft,
            child: SailStat(label: 'Lifetime fees', value: '0.0001,2840'),
          ),
        ),
      );

      final label = tester.widget<Text>(find.text('Lifetime fees'));
      final value = tester.widget<Text>(find.text('0.0001,2840'));
      expect(label.style!.fontSize, 12);
      expect(label.style!.color, theme.colors.textSecondary);
      expect(label.style!.fontWeight, FontWeight.w500);
      expect(value.style!.fontSize, 14);
      expect(value.style!.color, theme.colors.text);
      expect(value.style!.fontWeight, FontWeight.w500);
      expect(
        tester.getTopLeft(find.text('0.0001,2840')).dy,
        greaterThan(tester.getBottomLeft(find.text('Lifetime fees')).dy),
      );
    });
  });

  group('SailStrip', () {
    testWidgets('lays out lead, stats, status and actions in one row inside a card', (tester) async {
      final theme = _v2();
      await tester.pumpWidget(
        _app(
          theme,
          Align(
            alignment: Alignment.topLeft,
            child: SailStrip(
              lead: const Text('1.5000,0000 ECX'),
              stats: const [
                SailStat(label: 'Unconfirmed', value: '-0.2500,0000'),
                SailStat(label: 'UTXOs', value: '6 on 5 addresses'),
              ],
              status: const SailStatusPill(label: 'Synced'),
              actions: [
                SailButton(label: 'Send', onPressed: () async {}),
                SailButton(label: 'Receive', variant: ButtonVariant.secondary, onPressed: () async {}),
              ],
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      final card = _boxOf(tester, find.byType(SailStrip));
      expect(card.color, theme.colors.backgroundSecondary);
      expect(card.borderRadius, const BorderRadius.all(Radius.circular(8)));

      final lead = tester.getRect(find.text('1.5000,0000 ECX'));
      final stat = tester.getRect(find.text('UTXOs'));
      final pill = tester.getRect(find.byType(SailStatusPill));
      final send = tester.getRect(find.text('Send'));
      final receive = tester.getRect(find.text('Receive'));
      expect(stat.left, greaterThan(lead.right));
      expect(pill.left, greaterThan(stat.right));
      expect(send.left, greaterThan(pill.right));
      expect(receive.left, greaterThan(send.right));
      expect(receive.right, lessThanOrEqualTo(1200 - 16));
    });

    testWidgets('wraps the stats on a narrow page instead of an overflow', (tester) async {
      await tester.pumpWidget(
        _app(
          _v2(),
          SailStrip(
            stats: [for (var i = 0; i < 8; i++) SailStat(label: 'Stat $i', value: 'Value $i')],
            actions: [SailButton(label: 'Send', onPressed: () async {})],
          ),
          size: const Size(500, 400),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(tester.getTopLeft(find.text('Stat 7')).dy, greaterThan(tester.getTopLeft(find.text('Stat 0')).dy));
    });
  });

  group('SailSidePanel', () {
    testWidgets('is 380 wide with a title, a menu, a close button and a body that scrolls', (tester) async {
      var closed = 0;
      final theme = _v2(light: false);
      await tester.pumpWidget(
        _app(
          theme,
          Align(
            alignment: Alignment.topRight,
            child: SizedBox(
              height: 400,
              child: SailSidePanel(
                title: 'Rent',
                menuItems: () => [SailMenuItem(onSelected: () {}, child: const Text('Copy TXID'))],
                onClose: () async => closed++,
                child: Column(children: [for (var i = 0; i < 40; i++) Text('Detail $i')]),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(SailSidePanel)).width, SailSidePanel.width);
      final card = _boxOf(tester, find.byType(SailSidePanel));
      expect(card.color, theme.colors.backgroundSecondary);
      expect(card.borderRadius, const BorderRadius.all(Radius.circular(8)));
      expect(tester.widget<Text>(find.text('Rent')).style!.fontWeight, FontWeight.w600);

      await tester.tap(find.byType(SailRowMenuButton));
      await tester.pumpAndSettle();
      expect(find.text('Copy TXID'), findsOneWidget);
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      await tester.tap(find.byType(SailIconBoxButton).last);
      expect(closed, 1);

      expect(find.text('Detail 39').hitTestable(), findsNothing);
      await tester.dragUntilVisible(find.text('Detail 39'), find.byType(SingleChildScrollView), const Offset(0, -200));
      expect(find.text('Detail 39').hitTestable(), findsOneWidget);
    });

    testWidgets('takes a wider width when a page asks for it', (tester) async {
      await tester.pumpWidget(
        _app(
          _v2(),
          const Align(
            alignment: Alignment.topRight,
            child: SailSidePanel(title: 'Seed', panelWidth: 480, child: Text('Body')),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(SailSidePanel)).width, 480);
    });

    testWidgets('hides the menu and the close button when it has none', (tester) async {
      await tester.pumpWidget(
        _app(
          _v2(),
          const Align(
            alignment: Alignment.topRight,
            child: SailSidePanel(title: 'Exchange', child: Text('Body')),
          ),
        ),
      );

      expect(find.byType(SailRowMenuButton), findsNothing);
      expect(find.byType(SailIconBoxButton), findsNothing);
      expect(find.text('Body'), findsOneWidget);
    });
  });
}
