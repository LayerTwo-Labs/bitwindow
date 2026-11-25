import 'package:bitwindow/pages/wallet/wallet_send.dart';
import 'package:bitwindow/providers/address_book_provider.dart';
import 'package:bitwindow/utils/bitcoin_uri.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:sail_ui/sail_ui.dart';

import 'test_utils.dart';

const _address = 'bcrt1qc862dcz4ellepph35s0lmjg0nn5tt84zte54lw';

class _FakeAddressBook extends ChangeNotifier implements AddressBookProvider {
  final saved = <(String, String, Direction)>[];

  @override
  Future<void> createEntry(String label, String address, Direction direction) async {
    saved.add((label, address, direction));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() => GetIt.I.reset());
  tearDown(() => GetIt.I.reset());

  Future<_FakeAddressBook> pumpDialog(WidgetTester tester, String initialLabel) async {
    final book = _FakeAddressBook();
    await tester.pumpSailPage(
      SaveToAddressBookDialog(
        address: _address,
        initialLabel: initialLabel,
        addressBookProvider: book,
        log: Logger(),
      ),
    );
    return book;
  }

  group('uriLabelFor', () {
    final uri = BitcoinURI.parse('bitcoin:$_address?label=Rent%20%E2%82%BF');

    test('gives the label of the URI address', () {
      expect(uriLabelFor(uri, _address), 'Rent ₿');
    });

    test('gives no label for another address', () {
      expect(uriLabelFor(uri, 'bcrt1qw508d6qejxtdg4y5r3zarvary0c5xw7kygt080'), '');
    });

    test('gives no label with no URI, or with a URI that has none', () {
      expect(uriLabelFor(null, _address), '');
      expect(uriLabelFor(BitcoinURI.parse('bitcoin:$_address'), _address), '');
    });
  });

  testWidgets('the dialog starts with the label of the URI and saves it', (tester) async {
    final book = await pumpDialog(tester, 'Rent');

    expect(find.widgetWithText(SailTextField, 'Rent'), findsOneWidget);
    final save = find.widgetWithText(SailButton, 'Save');
    expect(tester.widget<SailButton>(save).disabled, isFalse);

    await tester.tap(save);
    // The toast holds a timer.
    await tester.pumpAndSettle(const Duration(seconds: 10));

    expect(book.saved, [('Rent', _address, Direction.DIRECTION_SEND)]);
  });

  testWidgets('the dialog starts empty with no label', (tester) async {
    await pumpDialog(tester, '');

    expect(tester.widget<SailButton>(find.widgetWithText(SailButton, 'Save')).disabled, isTrue);
  });
}
