import 'package:bitwindow/pages/transaction_censorship_page.dart';
import 'package:bitwindow/providers/mempool_watch_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';

import 'test_utils.dart';

class _Alarmed extends MempoolWatchProvider {
  @override
  int get alarmCount => 1;
}

void main() {
  setUp(() {
    final provider = MempoolWatchProvider()
      ..initialized = true
      ..status = GetMempoolWatchStatusResponse(enabled: true, running: true);
    GetIt.I.registerSingleton<MempoolWatchProvider>(provider);
  });

  tearDown(() {
    SailStyleValues.phoneLayoutOverride = null;
    return GetIt.I.reset();
  });

  Finder button(String label) => find.widgetWithText(SailButton, label);

  testWidgets('on a phone Stop watching and Reset tracker are small outline buttons on one row', (tester) async {
    SailStyleValues.phoneLayoutOverride = true;
    await loadBundledFonts();
    await tester.pumpSailPage(const TransactionCensorshipPage());
    await tester.binding.setSurfaceSize(const Size(390, 800));
    await tester.pump();

    expect(tester.takeException(), isNull);
    for (final label in ['Stop watching', 'Reset tracker']) {
      final widget = tester.widget<SailButton>(button(label));
      expect(widget.variant, ButtonVariant.outline);
      expect(widget.small, isTrue);
    }
    final stop = tester.getRect(button('Stop watching'));
    final reset = tester.getRect(button('Reset tracker'));
    expect(reset.center.dy, closeTo(stop.center.dy, 1));
    expect(tester.getRect(find.byType(SailTextField)).top, greaterThan(stop.bottom));
  });

  testWidgets('on desktop the strip holds one primary toggle and Reset tracker moves into the menu', (tester) async {
    await tester.pumpSailPage(const TransactionCensorshipPage());
    await tester.pump();

    final strip = find.byType(SailStrip);
    final stripButtons = find.descendant(of: strip, matching: find.byType(SailButton));
    expect(stripButtons, findsOneWidget);
    final stop = tester.widget<SailButton>(stripButtons);
    expect(stop.label, 'Stop watching');
    expect(stop.variant, ButtonVariant.primary);
    expect(button('Reset tracker'), findsNothing);
    expect(find.byType(SailTextField), findsOneWidget);

    await tester.tap(find.descendant(of: strip, matching: find.byType(SailRowMenuButton)));
    await tester.pumpAndSettle();
    expect(find.text('Reset tracker'), findsOneWidget);
  });

  testWidgets('an alarm is a red row over the table with a white dot and text', (tester) async {
    await GetIt.I.reset();
    GetIt.I.registerSingleton<MempoolWatchProvider>(
      _Alarmed()
        ..initialized = true
        ..status = GetMempoolWatchStatusResponse(enabled: true, running: true),
    );
    await tester.pumpSailPage(const TransactionCensorshipPage());
    await tester.pump();

    expect(tester.takeException(), isNull);
    final alarm = find.byKey(const Key('censorship-alarm'));
    final colors = SailTheme.of(tester.element(alarm)).colors;
    final box = tester.widget<Container>(alarm).decoration! as BoxDecoration;
    expect(box.color, colors.destructiveButtonBackground);
    final text = find.text('Censorship alarm: 1 pending transaction scores above 100');
    expect(tester.widget<Text>(text).style?.color, colors.destructiveButtonText);
    expect(find.byType(SailAlert), findsNothing);
  });
}
