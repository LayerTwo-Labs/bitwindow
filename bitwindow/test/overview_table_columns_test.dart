import 'package:bitwindow/pages/overview_page.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';
import 'package:sail_ui/sail_ui.dart';

import 'test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final v2 = SailThemeData.lightTheme(SailColorScheme.orange, false, SailFontValues.inter, SailThemeStyle.bitwindowV2);
  final time = Timestamp.fromDateTime(DateTime.utc(2026, 11, 1, 9, 42, 13));

  Future<void> pump(WidgetTester tester, Widget table) async {
    SailStyleValues.phoneLayoutOverride = false;
    addTearDown(() => SailStyleValues.phoneLayoutOverride = null);
    await tester.pumpSailPage(
      SailTheme(
        data: v2,
        child: SizedBox(width: 700, height: 400, child: table),
      ),
    );
    await tester.pumpAndSettle();
  }

  void expectOwnColumn(WidgetTester tester, String header, String value) {
    final cell = find.text(value);
    expect(cell, findsOneWidget, reason: '$value must be a cell of its own');
    expect(
      tester.getTopLeft(cell).dx,
      closeTo(tester.getTopLeft(find.text(header)).dx, 2),
      reason: '$value must start under $header',
    );
  }

  testWidgets('latest transactions keep each value in its own column', (tester) async {
    const txid = '8c1f0a3e9b7d4e52a6f1c0d93b2e7a845f6c1d0e2b3a4c5d6e7f8091a2b3c4d5';
    await pump(
      tester,
      LatestTransactionTable(
        entries: [
          RecentTransaction(txid: txid, feeSats: Int64(226), virtualSize: 141, time: time, confirmedInBlock: 1022814),
        ],
      ),
    );

    final time0 = time.toDateTime().toLocal().toString();
    for (final (header, value) in [
      ('Time', time0),
      ('Fee', '226'),
      ('TxID', txid),
      ('Size', '141'),
      ('Height', '1022814'),
    ]) {
      expectOwnColumn(tester, header, value);
    }
    expect(find.textContaining('·'), findsNothing);
  });

  testWidgets('latest blocks keep each value in its own column', (tester) async {
    final block = Block(
      height: 1022814,
      hash: '00000000000000000312ab9f4c7e1d0b8f3a6e5c2d9b7a14f0e8c3d6b2a',
      blockTime: time,
    );
    await pump(tester, LatestBlocksTable(blocks: [block]));

    expectOwnColumn(tester, 'Time', time.toDateTime().toLocal().format());
    expectOwnColumn(tester, 'Height', '1022814');
    expectOwnColumn(tester, 'Block Hash', block.hash);
  });
}
