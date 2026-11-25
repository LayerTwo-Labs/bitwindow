import 'package:bitwindow/models/multisig_group.dart';
import 'package:bitwindow/widgets/psbt_coordinator_modal.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'test_utils.dart';

void main() {
  setUpAll(loadBundledFonts);

  tearDown(() => GetIt.I.reset());

  for (final size in [const Size(1200, 800), const Size(1024, 700)]) {
    testWidgets('shows the fee policy at ${size.width.toInt()} × ${size.height.toInt()}', (tester) async {
      final group = MultisigGroup(
        id: 'group',
        name: 'Multisig group',
        n: 2,
        m: 2,
        created: 0,
        keys: const [],
        balance: 0.42,
        utxos: 1,
      );
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpSailPage(PSBTCoordinatorModal(group: group));
      await tester.binding.setSurfaceSize(size);
      await tester.pump();

      const hint = 'The fee comes from change. If you spend the full balance, it comes from the payment.';
      expect(find.text(hint).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
