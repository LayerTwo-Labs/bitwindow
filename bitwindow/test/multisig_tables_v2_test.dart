import 'package:bitwindow/models/multisig_group.dart';
import 'package:bitwindow/models/multisig_transaction.dart';
import 'package:bitwindow/pages/wallet/wallet_multisig_lounge.dart';
import 'package:bitwindow/widgets/create_multisig_modal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';

import 'test_utils.dart';

final _group = MultisigGroup(
  id: 'a3f9c21e',
  name: 'Cold storage',
  n: 3,
  m: 2,
  keys: [
    MultisigKey(owner: 'MyKey0', xpub: 'xpub-mine', derivationPath: "m/48'/1'/0'/2'", isWallet: true),
    MultisigKey(owner: 'Alice', xpub: 'xpub-alice', derivationPath: "m/48'/1'/0'/2'", isWallet: false),
  ],
  created: 0,
  txid: '9f3c${'0' * 56}21a0',
  balance: 1.5,
  utxos: 3,
);

final _tx = MultisigTransaction(
  id: 'tx_a41f',
  groupId: _group.id,
  initialPSBT: 'cHNidP8',
  keyPSBTs: const [
    KeyPSBTStatus(keyId: 'xpub-mine', psbt: 'cHNidP8', isSigned: false),
    KeyPSBTStatus(keyId: 'xpub-alice', psbt: 'cHNidP8', isSigned: true),
  ],
  type: TxType.withdrawal,
  created: DateTime(2026, 10, 31, 18, 20),
  amount: 0.2,
  destination: 'ecash:qq9t2a6fz8',
  fee: 0.00000282,
  inputs: const [],
  requiredSignatures: 2,
);

Widget _v2(Widget child) => SailTheme(
  data: SailThemeData.lightTheme(SailColorScheme.orange, false, SailFontValues.inter, SailThemeStyle.bitwindowV2),
  child: SizedBox(width: 1100, height: 400, child: child),
);

void main() {
  setUpAll(loadBundledFonts);

  setUp(() async {
    await GetIt.I.reset();
    await registerTestDependencies();
  });

  tearDown(() => GetIt.I.reset());

  testWidgets('a group row shows its short TXID in its own column and Copy TXID in its "…"', (tester) async {
    final picked = <String>[];
    await tester.pumpSailPage(
      _v2(
        MultisigGroupsTable(
          groups: [_group],
          selectedGroup: null,
          onSelectGroup: (g) => picked.add('select ${g?.id}'),
          rowMenu: (g) => [
            SailMenuItem(onSelected: () => picked.add('fund ${g.id}'), child: const Text('Fund This Group')),
            SailMenuItem(onSelected: () => picked.add('copy ${g.id}'), child: const Text('Copy TXID')),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final headers = tester.widgetList<SailTableHeaderCell>(find.byType(SailTableHeaderCell)).map((h) => h.name);
    expect(headers, [
      'Name',
      'ID',
      'Keys Required',
      'Total Keys',
      'Type',
      'UTXOs',
      'TXID (If Broadcasted)',
      'Balance (BTC)',
    ]);
    expect(find.text('9f3c${'0' * 6}...${'0' * 6}21a0'), findsOneWidget);
    expect(find.byType(SailButton), findsNothing);

    await tester.tap(find.byType(SailRowMenuButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy TXID'));
    await tester.pumpAndSettle();
    expect(picked, ['copy a3f9c21e']);

    await tester.tap(find.text('Cold storage'));
    await tester.pumpAndSettle();
    expect(picked.last, 'select a3f9c21e');
  });

  testWidgets('a transaction row has a status dot, no Action column, and a click selects it', (tester) async {
    final selected = <String?>[];
    await tester.pumpSailPage(
      _v2(
        MultisigTransactionsTable(
          transactionRows: [TransactionRow(transaction: _tx, hasWalletKeys: true, walletHasSigned: false)],
          groups: [_group],
          onAction: (_, _) {},
          onBroadcast: () {},
          onView: (_) {},
          onSign: (_, _) {},
          onSelectTransaction: selected.add,
          rowMenu: (row, group) => [SailMenuItem(onSelected: () {}, child: const Text('Sign'))],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Action'), findsNothing);
    expect(find.byType(SailButton), findsNothing);
    expect(find.byType(SailStatusDot), findsOneWidget);
    expect(find.text('1/2'), findsOneWidget);

    await tester.tap(find.text('Cold storage'));
    await tester.pumpAndSettle();
    expect(selected, ['tx_a41f']);
  });
}
