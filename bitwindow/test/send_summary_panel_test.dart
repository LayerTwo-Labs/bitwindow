import 'package:bitwindow/pages/wallet/wallet_send.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';

import 'test_utils.dart';

Finder _button(String label) => find.byWidgetPredicate((w) => w is SailButton && w.label == label);

class _Calls {
  int creates = 0;
  int cancels = 0;
  int clears = 0;
  int airgaps = 0;
  int devices = 0;
  int graphToggles = 0;
}

Future<_Calls> _pumpPanel(
  WidgetTester tester, {
  bool creating = false,
  bool sendsNow = false,
  bool oneKey = true,
  String? deviceType,
  bool showGraph = false,
  String? error,
}) async {
  final calls = _Calls();
  await tester.pumpSailPage(
    Align(
      alignment: Alignment.topRight,
      child: SizedBox(
        width: sendSideColumnWidth,
        child: SendSummaryPanel(
          total: '0.3500,0226 BTC',
          totalOtherUnit: '35 000 226 sats',
          details: [SailText.primary13('Recipients')],
          error: error,
          creating: creating,
          sendsNow: sendsNow,
          onCreate: () async => calls.creates++,
          onCancel: () => calls.cancels++,
          onClear: () async => calls.clears++,
          onAirgap: oneKey ? () async => calls.airgaps++ : null,
          deviceType: deviceType,
          onDevice: () async => calls.devices++,
          showGraph: showGraph,
          onToggleGraph: () => calls.graphToggles++,
        ),
      ),
    ),
  );
  await tester.pump();
  return calls;
}

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byType(SailRowMenuButton));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

List<String> _menuLabels(WidgetTester tester) => [
  for (final item in tester.widgetList<SailMenuItem>(find.byType(SailMenuItem)))
    (find.descendant(of: find.byWidget(item), matching: find.byType(Text)).evaluate().first.widget as Text).data!,
];

void main() {
  setUpAll(loadBundledFonts);

  setUp(() async {
    await GetIt.I.reset();
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  group('the main button', () {
    testWidgets('an idle form has one button: Create Transaction', (tester) async {
      final calls = await _pumpPanel(tester);

      expect(find.text('Summary'), findsOneWidget);
      expect(find.text('You send'), findsOneWidget);
      expect(find.text('0.3500,0226 BTC'), findsOneWidget);
      expect(find.text('35 000 226 sats'), findsOneWidget);
      expect(find.byType(SailButton), findsOneWidget);
      expect(tester.widget<SailButton>(_button('Create Transaction')).disabled, isFalse);

      await tester.tap(_button('Create Transaction'));
      await tester.pump();
      expect(calls.creates, 1);
    });

    testWidgets('a send to a payment code reads Send', (tester) async {
      await _pumpPanel(tester, sendsNow: true);

      expect(_button('Send'), findsOneWidget);
      expect(_button('Create Transaction'), findsNothing);
    });

    testWidgets('a build reads Creating… and Cancel under it stops the build', (tester) async {
      final calls = await _pumpPanel(tester, creating: true);

      final create = tester.widget<SailButton>(_button('Create Transaction'));
      expect(create.disabled, isTrue);
      expect(create.loading, isTrue);
      expect(find.text('Creating…'), findsWidgets);

      await tester.tap(_button('Cancel'));
      await tester.pump();
      expect(calls.cancels, 1);
    });

    testWidgets('an error shows under the button', (tester) async {
      await _pumpPanel(tester, error: 'The fee changed. Check the new fee and send again.');

      final button = tester.getRect(_button('Create Transaction'));
      final error = tester.getRect(find.textContaining('The fee changed'));
      expect(error.top, greaterThan(button.bottom - 1));
    });
  });

  group('the "…" menu', () {
    testWidgets('a one-key wallet offers airgap, the graph and Clear All', (tester) async {
      final calls = await _pumpPanel(tester);
      await _openMenu(tester);

      expect(_menuLabels(tester), ['External signer (airgap)', 'Show graph', 'Clear All']);

      await tester.tap(find.text('Clear All'));
      await tester.pumpAndSettle();
      expect(calls.clears, 1);
    });

    testWidgets('a hardware wallet also signs with its device', (tester) async {
      final calls = await _pumpPanel(tester, deviceType: 'trezor');
      await _openMenu(tester);

      expect(_menuLabels(tester), ['External signer (airgap)', 'Sign with trezor', 'Show graph', 'Clear All']);

      await tester.tap(find.text('Sign with trezor'));
      await tester.pumpAndSettle();
      expect(calls.devices, 1);
    });

    testWidgets('a multisig wallet has no airgap item', (tester) async {
      await _pumpPanel(tester, oneKey: false);
      await _openMenu(tester);

      expect(_menuLabels(tester), ['Show graph', 'Clear All']);
    });

    testWidgets('an open graph reads Hide graph, and the item toggles it', (tester) async {
      final calls = await _pumpPanel(tester, showGraph: true);
      await _openMenu(tester);

      expect(_menuLabels(tester), contains('Hide graph'));
      await tester.tap(find.text('Hide graph'));
      await tester.pumpAndSettle();
      expect(calls.graphToggles, 1);
    });

    testWidgets('while it creates, Cancel replaces Clear All and the sign items wait', (tester) async {
      final calls = await _pumpPanel(tester, creating: true, deviceType: 'trezor');
      await _openMenu(tester);

      expect(_menuLabels(tester), ['External signer (airgap)', 'Sign with trezor', 'Show graph', 'Cancel']);
      final airgap = tester.widget<SailMenuItem>(
        find.ancestor(of: find.text('External signer (airgap)'), matching: find.byType(SailMenuItem)),
      );
      expect(airgap.onSelected, isNull);

      await tester.tap(find.descendant(of: find.byType(SailMenu), matching: find.text('Cancel')));
      await tester.pump(const Duration(milliseconds: 500));
      expect(calls.cancels, 1);
      expect(calls.airgaps, 0);
    });
  });

  group('the address book menu', () {
    const saved = 'bcrt1qsaved0000000000000000000000000000000';
    const fresh = 'bcrt1qfresh0000000000000000000000000000000';
    final entries = [
      AddressBookEntry(id: Int64(1), label: 'Exchange', address: saved, direction: Direction.DIRECTION_SEND),
    ];

    Future<({List<AddressBookEntry> picked, List<String> savedAddresses})> pumpButton(
      WidgetTester tester, {
      required List<AddressBookEntry> entries,
      required String address,
    }) async {
      final picked = <AddressBookEntry>[];
      final savedAddresses = <String>[];
      await tester.pumpSailPage(
        Center(
          child: AddressBookButton(
            entries: entries,
            address: address,
            onPick: picked.add,
            onSave: (address) async => savedAddresses.add(address),
          ),
        ),
      );
      await tester.tap(find.byType(AddressBookButton));
      await tester.pumpAndSettle();
      return (picked: picked, savedAddresses: savedAddresses);
    }

    SailMenuItem item(WidgetTester tester, String label) =>
        tester.widget<SailMenuItem>(find.ancestor(of: find.text(label), matching: find.byType(SailMenuItem)));

    testWidgets('the book offers Pick and Save', (tester) async {
      await pumpButton(tester, entries: entries, address: fresh);

      expect(_menuLabels(tester), ['Pick from address book', 'Save to address book']);
    });

    testWidgets('Pick lists the entries and fills the address', (tester) async {
      final calls = await pumpButton(tester, entries: entries, address: '');

      await tester.tap(find.text('Pick from address book'));
      await tester.pumpAndSettle();
      expect(find.text('Address Book'), findsOneWidget);
      expect(find.text('Exchange'), findsOneWidget);
      expect(find.text(saved), findsOneWidget);

      await tester.tap(find.text('Exchange'));
      await tester.pumpAndSettle();
      expect(calls.picked.single.address, saved);
    });

    testWidgets('an empty book says so', (tester) async {
      await pumpButton(tester, entries: const [], address: '');

      await tester.tap(find.text('Pick from address book'));
      await tester.pumpAndSettle();
      expect(find.text('No Addresses Saved'), findsOneWidget);
      expect(item(tester, 'No Addresses Saved').onSelected, isNull);
    });

    testWidgets('Save saves an address the book does not hold', (tester) async {
      final calls = await pumpButton(tester, entries: entries, address: fresh);

      await tester.tap(find.text('Save to address book'));
      await tester.pumpAndSettle();
      expect(calls.savedAddresses, [fresh]);
    });

    testWidgets('Save waits for a new address', (tester) async {
      await pumpButton(tester, entries: entries, address: saved);
      expect(item(tester, 'Save to address book').onSelected, isNull);
    });

    testWidgets('Save waits for an address', (tester) async {
      await pumpButton(tester, entries: entries, address: '');
      expect(item(tester, 'Save to address book').onSelected, isNull);
    });
  });

  group('feeChoiceLabel', () {
    test('names the target and its rate', () {
      expect(feeChoiceLabel(1, 1), 'Next block · 1 ${activeTicker.feeRate}');
      expect(feeChoiceLabel(3, 2.5), '3 blocks · 2.5 ${activeTicker.feeRate}');
    });

    test('names only the target with no rate, and Custom for a typed fee', () {
      expect(feeChoiceLabel(6, null), '6 blocks');
      expect(feeChoiceLabel(null, 4), 'Custom');
    });
  });
}
