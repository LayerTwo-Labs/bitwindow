import 'package:bitwindow/pages/wallet/widgets/wallet_v2_parts.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';

import 'test_utils.dart';

void main() {
  testWidgets('the ⇅ swaps the amount and the sats line, and the unit setting stays', (tester) async {
    await tester.pumpSailPage(
      const WalletAmountBlock(label: 'Balance', amount: '1.50000000 BTC', sats: '150 000 000 sats'),
    );
    await tester.pump();
    final unit = GetIt.I<SettingsProvider>().bitcoinUnit;

    double size(String text) => tester.widget<Text>(find.text(text)).style!.fontSize!;
    expect(size('1.50000000 BTC'), greaterThan(size('150 000 000 sats')));

    await tester.tap(find.byKey(const Key('wallet_swap_unit')));
    await tester.pump();
    expect(size('150 000 000 sats'), greaterThan(size('1.50000000 BTC')));
    expect(GetIt.I<SettingsProvider>().bitcoinUnit, unit);

    await tester.tap(find.byKey(const Key('wallet_swap_unit')));
    await tester.pump();
    expect(size('1.50000000 BTC'), greaterThan(size('150 000 000 sats')));
  });

  testWidgets('a block with no sats line has no ⇅', (tester) async {
    await tester.pumpSailPage(const WalletAmountBlock(amount: '1.50000000 BTC'));
    await tester.pump();

    expect(find.byKey(const Key('wallet_swap_unit')), findsNothing);
  });
}
