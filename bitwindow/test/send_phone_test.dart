import 'package:bitwindow/pages/wallet/wallet_send.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';

import 'test_utils.dart';

Finder _button(String label) => find.byWidgetPredicate((w) => w is SailButton && w.label == label);

Future<void> _pumpRow(WidgetTester tester) async {
  await tester.pumpSailPage(
    SizedBox(
      width: double.infinity,
      child: RecipientRow(
        index: 0,
        recipient: RecipientModel(),
        addressBookEntries: const [],
        onAddressSelected: (_) {},
        onUseAvailableBalance: (_) async {},
        currentUnit: BitcoinUnit.btc,
        onSaveToAddressBook: (context, address) async {},
        onRemove: () {},
      ),
    ),
  );
  if (SailStyleValues.phoneLayoutOverride == true) {
    await tester.usePhoneSize();
  }
  await tester.pumpAndSettle();
}

Future<void> _pumpSummary(WidgetTester tester) async {
  await tester.pumpSailPage(
    SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SendSummaryPanel(
            total: '0.1000,0000 BTC',
            totalOtherUnit: '10 000 000 sats',
            details: const [],
            creating: false,
            sendsNow: false,
            onCreate: () async {},
            onCancel: () {},
            onClear: () async {},
            onAirgap: () async {},
            deviceType: null,
            onDevice: () async {},
            showGraph: false,
            onToggleGraph: () {},
          ),
        ],
      ),
    ),
  );
  if (SailStyleValues.phoneLayoutOverride == true) {
    await tester.usePhoneSize();
  }
  await tester.pump();
}

void main() {
  setUpAll(loadBundledFonts);

  setUp(() async {
    await GetIt.I.reset();
  });

  tearDown(() async {
    SailStyleValues.phoneLayoutOverride = null;
    await GetIt.I.reset();
  });

  testWidgets('on a phone the amount and the remove button share a line under the address', (tester) async {
    SailStyleValues.phoneLayoutOverride = true;
    await _pumpRow(tester);

    final address = tester.getRect(find.byKey(const Key('recipient_address_0')));
    final amount = tester.getRect(find.byKey(const Key('recipient_amount_0')));
    final remove = tester.getRect(find.byKey(const Key('recipient_remove_0')));
    expect(amount.top, greaterThanOrEqualTo(address.bottom));
    expect(remove.center.dy, closeTo(amount.center.dy, 1));
    expect(remove.left, greaterThan(amount.right - 1));
  });

  testWidgets('on a phone the address wraps and its tools sit under it, inside the field', (tester) async {
    SailStyleValues.phoneLayoutOverride = true;
    await _pumpRow(tester);

    final field = find.byKey(const Key('recipient_address_0'));
    final text = tester.getRect(find.descendant(of: field, matching: find.byType(EditableText)));
    final paste = find.descendant(of: field, matching: find.byType(PasteButton));
    expect(paste, findsOneWidget);
    expect(tester.getRect(paste).top, greaterThanOrEqualTo(text.bottom));
    expect(tester.getRect(paste).bottom, lessThan(tester.getRect(field).bottom));
    expect(tester.widget<EditableText>(find.byType(EditableText).first).maxLines, isNull);
  });

  testWidgets('on a phone the amount field shows the unit before MAX', (tester) async {
    SailStyleValues.phoneLayoutOverride = true;
    await _pumpRow(tester);

    final unit = find.descendant(
      of: find.byKey(const Key('recipient_amount_0')),
      matching: find.text(BitcoinUnit.btc.symbol),
    );
    expect(unit, findsOneWidget);
    expect(tester.getRect(unit).right, lessThan(tester.getRect(_button('MAX')).left));
  });

  testWidgets('on a desktop the address, the amount and the remove button share one row', (tester) async {
    SailStyleValues.phoneLayoutOverride = false;
    await tester.binding.setSurfaceSize(const Size(1200, 720));
    await tester.pumpSailPage(
      SizedBox(
        width: 1000,
        child: RecipientRow(
          index: 0,
          recipient: RecipientModel(),
          addressBookEntries: const [],
          onAddressSelected: (_) {},
          onUseAvailableBalance: (_) async {},
          currentUnit: BitcoinUnit.btc,
          onSaveToAddressBook: (context, address) async {},
          onRemove: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final address = tester.getRect(find.byKey(const Key('recipient_address_0')));
    final amount = tester.getRect(find.byKey(const Key('recipient_amount_0')));
    expect(amount.left, greaterThan(address.right));
    expect(
      find.descendant(of: find.byKey(const Key('recipient_amount_0')), matching: find.text(BitcoinUnit.btc.symbol)),
      findsNothing,
    );
  });

  testWidgets('on a phone the summary fills the width under the form, with one button', (tester) async {
    SailStyleValues.phoneLayoutOverride = true;
    await _pumpSummary(tester);

    final column = tester.getSize(
      find.ancestor(of: find.byType(SendSummaryPanel), matching: find.byType(Column)).first,
    );
    expect(tester.getSize(find.byType(SailSidePanel)).width, column.width);
    expect(column.width, greaterThan(SailSidePanel.width));
    expect(tester.getSize(_button('Create Transaction')).width, closeTo(column.width - 32, 1));
    expect(find.byType(SailButton), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
