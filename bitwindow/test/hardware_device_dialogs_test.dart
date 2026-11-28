import 'package:bitwindow/widgets/hardware_device_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sail_ui/sail_ui.dart';

void main() {
  final v2 = SailThemeData.lightTheme(SailColorScheme.orange, false, SailFontValues.inter, SailThemeStyle.bitwindowV2);

  Future<Future<String?>> open(WidgetTester tester, Widget dialog) async {
    late Future<String?> result;
    await tester.pumpWidget(
      SailTheme(
        data: v2,
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => result = showDialog<String>(context: context, builder: (_) => dialog),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  SailButton button(WidgetTester tester, String label) =>
      tester.widget<SailButton>(find.byWidgetPredicate((w) => w is SailButton && w.label == label));

  testWidgets('the PIN dialog has a ×, one full-width Unlock, and Clear beside the PIN', (tester) async {
    final result = await open(tester, const TrezorPinDialog());

    expect(find.byWidgetPredicate((w) => w is SailButton && w.label == 'Cancel'), findsNothing);
    final card = tester.getRect(find.byType(SailCard));
    final unlock = tester.getRect(find.byWidgetPredicate((w) => w is SailButton && w.label == 'Unlock'));
    expect(unlock.width, closeTo(card.width - 32, 1));
    expect(button(tester, 'Unlock').disabled, isTrue);

    await tester.tap(find.byWidgetPredicate((w) => w is SailButton && w.label == '•').first);
    await tester.pump();
    expect(button(tester, 'Unlock').disabled, isFalse);
    await tester.tap(find.byWidgetPredicate((w) => w is SailButton && w.label == 'Clear'));
    await tester.pump();
    expect(button(tester, 'Unlock').disabled, isTrue);

    await tester.tap(find.byType(SailIconBoxButton));
    await tester.pumpAndSettle();
    expect(await result, isNull);
  });

  testWidgets('the passphrase dialog has a × and one full-width Confirm', (tester) async {
    final result = await open(tester, const DevicePassphraseDialog());

    expect(find.byWidgetPredicate((w) => w is SailButton && w.label == 'Cancel'), findsNothing);
    final card = tester.getRect(find.byType(SailCard));
    final confirm = tester.getRect(find.byWidgetPredicate((w) => w is SailButton && w.label == 'Confirm'));
    expect(confirm.width, closeTo(card.width - 32, 1));

    await tester.enterText(find.byType(TextField), 'hidden');
    await tester.tap(find.byWidgetPredicate((w) => w is SailButton && w.label == 'Confirm'));
    await tester.pumpAndSettle();
    expect(await result, 'hidden');
  });
}
