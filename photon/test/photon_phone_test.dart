import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:photon/pages/tabs/block_explorer_page.dart';
import 'package:photon/pages/tabs/mempool_explorer_page.dart';
import 'package:photon/pages/tabs/withdrawals_page.dart';
import 'package:sail_ui/pages/sidechains/sidechain_overview_page.dart';
import 'package:sail_ui/sail_ui.dart';

import 'test_utils.dart';

class _Rpc implements PhotonRPC {
  @override
  Future<List<SidechainUTXO>> listAllUTXOs() async => [];

  @override
  Future<PendingWithdrawalBundle?> getPendingWithdrawalBundle() async => null;

  @override
  Future<int?> getLatestFailedWithdrawalBundleHeight() async => 1262;

  @override
  Future<int> getBlockCount() async => 1284;

  @override
  Future<String?> getBestSidechainBlockHash() async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(WidgetTester tester, Widget child, {required bool phone}) async {
  SailStyleValues.phoneLayoutOverride = phone;
  await tester.binding.setSurfaceSize(Size(phone ? 390 : 1200, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: SailTheme(
        data: SailThemeData.lightTheme(SailColorScheme.orange, true, SailFontValues.inter),
        child: Scaffold(body: child),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  addTearDown(() => tester.pumpWidget(const SizedBox()));
}

Finder _header(String name) => find.byWidgetPredicate((w) => w is SailTableHeaderCell && w.name == name);

void main() {
  setUp(() async {
    await registerTestDependencies();
    GetIt.I.registerSingleton<PhotonRPC>(_Rpc());
  });

  tearDown(() async {
    SailStyleValues.phoneLayoutOverride = null;
    await GetIt.I.reset();
  });

  testWidgets('a phone lists the mempool totals in one panel', (tester) async {
    await _pump(tester, const MempoolExplorerPage(), phone: true);

    expect(tester.takeException(), isNull);
    expect(find.byType(SailStatList), findsOneWidget);
    expect(_header('Outpoint'), findsNothing);
    final value = tester.widget<SailTableHeaderCell>(find.widgetWithText(SailTableHeaderCell, 'Value'));
    expect(value.alignment, Alignment.centerRight);
  });

  for (final phone in [true, false]) {
    testWidgets('the withdrawal strip shows a neutral pill and the red failure line (phone: $phone)', (tester) async {
      await _pump(tester, const WithdrawalsPage(), phone: phone);

      expect(tester.takeException(), isNull);
      final pill = tester.widget<SailStatusPill>(find.byType(SailStatusPill));
      expect(pill.label, 'No pending withdrawal bundle');
      expect(pill.tone, SailStatusTone.neutral);
      final theme = SailTheme.of(tester.element(find.byType(SailStatusPill)));
      final failure = tester.widget<Text>(find.text('Last failed bundle at height: 1262'));
      expect(failure.style!.color, theme.colors.error);
      expect(find.text('Spent UTXOs'), findsOneWidget);
      expect(find.text('No pending bundle'), findsOneWidget);
    });
  }

  testWidgets('the desktop mempool puts the totals and Refresh in one strip over the table', (tester) async {
    await _pump(tester, const MempoolExplorerPage(), phone: false);

    expect(tester.takeException(), isNull);
    expect(find.byType(SailStrip), findsOneWidget);
    expect(find.descendant(of: find.byType(SailStrip), matching: find.text('Total UTXOs')), findsOneWidget);
    expect(find.descendant(of: find.byType(SailStrip), matching: find.byType(SailButton)), findsOneWidget);
    expect(tester.getTopLeft(_header('Outpoint')).dx, lessThan(tester.getTopLeft(_header('Type')).dx));
  });

  testWidgets('a block that cannot load shows the error line under the controls', (tester) async {
    await _pump(tester, const BlockExplorerPage(), phone: false);

    expect(tester.takeException(), isNull);
    expect(find.byType(SidechainNotice), findsOneWidget);
    expect(find.text('Could not get best hash'), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is SailIconBoxButton && w.tooltip == 'Previous block'), findsOneWidget);
  });
}
