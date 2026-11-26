import 'package:bitwindow/pages/wallet/wallet_send.dart';
import 'package:bitwindow/utils/coin_selection.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sidechain_core/gen/wallet/v1/wallet.pb.dart' show UnspentOutput;

import 'test_utils.dart';

class _SendModel extends Fake implements SendPageViewModel {
  @override
  final List<UnspentOutput> allUtxos;

  @override
  final List<UnspentOutput> availableUtxos;

  @override
  final List<UnspentOutput> selectedUtxos = [];

  _SendModel({required this.allUtxos, required this.availableUtxos});

  @override
  CoinSelectionStrategy get coinSelectionStrategy => CoinSelectionStrategy.largestFirst;

  @override
  void onSelectionChanged(List<UnspentOutput> selected) {}
}

void main() {
  setUpAll(loadBundledFonts);
  tearDown(() => GetIt.I.reset());

  testWidgets('Pay from offers only available coins', (tester) async {
    final available = UnspentOutput(output: 'aaaaaa:0', valueSats: Int64(120000));
    final frozen = UnspentOutput(output: 'bbbbbb:0', valueSats: Int64(170000));
    final model = _SendModel(allUtxos: [available, frozen], availableUtxos: [available]);

    await tester.pumpSailPage(Builder(builder: (context) => const PayFromPanel().build(context, model)));
    await tester.tap(find.text('Select UTXO(s)'));
    await tester.pumpAndSettle();

    final availableRow = find.textContaining('aaaaaa..:0');
    expect(availableRow.hitTestable(), findsOneWidget);
    expect(find.textContaining('bbbbbb..:0'), findsNothing);

    await tester.tap(availableRow);
    await tester.pumpAndSettle();
    expect(model.selectedUtxos, [available]);
  });
}
