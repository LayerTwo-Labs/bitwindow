import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:zside/pages/tabs/zside/zside_shield_deshield_page.dart';

import 'transfer_utxo_table_test.dart' show transparent, private;
import 'test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a transparent row has no button; a click selects it and "…" holds Shield and Melt single UTXO', (
    tester,
  ) async {
    final events = <String>[];
    await tester.pumpSailPage(
      SizedBox(
        height: 400,
        child: UnshieldedUTXOTable(
          entries: [transparent(0), transparent(1)],
          onSelect: (utxo) => events.add('select ${utxo.txid}'),
          onShield: (utxo) => events.add('shield ${utxo.txid}'),
          onMeltSingle: (utxo) => events.add('melt ${utxo.txid}'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Actions'), findsNothing);
    expect(find.byType(SailButton), findsNothing);

    await tester.tap(find.text('transparent1'));
    await tester.pump(kDoubleTapTimeout);
    await tester.pumpAndSettle();
    expect(events, ['select transparent1']);

    await tester.tap(find.byType(SailRowMenuButton).first);
    await tester.pump(kDoubleTapTimeout);
    await tester.pumpAndSettle();
    expect(find.text('Shield'), findsOneWidget);
    await tester.tap(find.text('Melt single UTXO'));
    await tester.pumpAndSettle();
    expect(events.last, startsWith('melt '));
  });

  testWidgets('a private row "…" holds Deshield and Cast single UTXO', (tester) async {
    final events = <String>[];
    await tester.pumpSailPage(
      SizedBox(
        height: 400,
        child: ShieldedUTXOTable(
          entries: [private(0)],
          onSelect: (utxo) => events.add('select'),
          onDeshield: (utxo) => events.add('deshield'),
          onCastSingle: (utxo) => events.add('cast'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(SailRowMenuButton));
    await tester.pump(kDoubleTapTimeout);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deshield'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SailRowMenuButton));
    await tester.pump(kDoubleTapTimeout);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cast single UTXO'));
    await tester.pumpAndSettle();
    expect(events, ['deshield', 'cast']);
  });
}
