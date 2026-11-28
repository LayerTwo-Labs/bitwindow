import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:zside/pages/tabs/zside/zside_transfer_page.dart';

import 'test_utils.dart';

UnshieldedUTXO transparent(int i) => UnshieldedUTXO(
  txid: 'transparent$i',
  address: 'address$i',
  amount: 0.5,
  confirmations: i + 1,
  generated: false,
  raw: 'raw$i',
);

ShieldedUTXO private(int i) => ShieldedUTXO(
  txid: 'private$i',
  pool: 'sapling',
  type: 'sapling',
  outindex: 0,
  confirmations: i + 1,
  spendable: true,
  address: 'zaddress$i',
  amount: 0.25,
  amountZat: 25000000,
  memo: '',
  change: false,
  raw: 'raw$i',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpTables(WidgetTester tester, int count, {List<String>? picked}) async {
    await tester.pumpSailPage(
      SizedBox(
        height: 600,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: TransparentUTXOTable(
                entries: List.generate(count, transparent),
                searchWidget: const SizedBox(height: 40),
                onSend: () async => picked?.add('send transparent'),
                menuItems: () => [
                  for (final label in ['Receive transparent coins', 'Copy address'])
                    SailMenuItem(onSelected: () => picked?.add(label), child: SailText.primary12(label)),
                ],
              ),
            ),
            Expanded(
              child: PrivateUTXOTable(
                entries: List.generate(count, private),
                searchWidget: const SizedBox(height: 40),
                onSend: () async => picked?.add('send private'),
                menuItems: () => [SailMenuItem(child: SailText.primary12('Receive private coins'))],
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final count in [0, 1, 50]) {
    testWidgets('transfer UTXO tables fill their card with $count rows', (tester) async {
      await pumpTables(tester, count);

      expect(tester.takeException(), isNull);
      expect(find.text('Confirmations'), findsNWidgets(2));
      if (count > 0) {
        expect(find.text('transparent0'), findsWidgets);
        expect(find.text('private0'), findsWidgets);
      }
    });
  }

  testWidgets('a transfer card shows its kind over the title, one send button and a "…" menu', (tester) async {
    final picked = <String>[];
    await pumpTables(tester, 1, picked: picked);

    expect(find.text('Transparent coins'), findsOneWidget);
    expect(find.text('Transparent UTXOs'), findsOneWidget);
    expect(find.text('Private coins'), findsOneWidget);
    expect(find.byType(SailButton), findsNWidgets(2));

    await tester.tap(find.text('Send transparent coins'));
    await tester.pump();
    expect(picked, ['send transparent']);

    await tester.tap(find.byType(SailRowMenuButton).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy address'));
    await tester.pumpAndSettle();
    expect(picked, ['send transparent', 'Copy address']);
  });

  testWidgets('the phone Transfer page scrolls, so the private card is reachable', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      SailTheme(
        data: SailThemeData.lightTheme(SailColorScheme.orange, false, SailFontValues.inter, SailThemeStyle.bitwindowV2),
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: TransferPhoneLayout(
            title: SizedBox(height: 60),
            transparent: SizedBox.expand(key: Key('transparent')),
            private: SizedBox.expand(key: Key('private')),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(tester.getRect(find.byKey(const Key('private'))).bottom, greaterThan(700));
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(const Key('private'))).bottom, lessThanOrEqualTo(700));
  });
}
