import 'package:bitwindow/pages/wallet/wallet_overview.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/gen/wallet/v1/wallet.pb.dart' as walletpb;

import 'test_utils.dart';

class _Overview extends ChangeNotifier implements OverviewViewModel {
  @override
  final List<walletpb.WalletTransaction> entries;

  @override
  final bool loading;

  _Overview(this.entries, {this.loading = false});

  @override
  String? get transactionsError => null;

  @override
  ({DateTime start, DateTime end})? get dateRange => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _deposit = walletpb.WalletTransaction(
  txid: 'ab' * 32,
  confirmationTime: walletpb.Confirmation(height: 0),
  sentSatoshi: Int64(1000000),
  depositRequest: walletpb.DepositRequest(slot: 9),
);

Future<void> _pumpTable(WidgetTester tester, _Overview model, {bool settle = true}) async {
  await tester.pumpSailPage(
    Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        height: 600,
        child: TransactionTable(searchWidget: const SizedBox.shrink(), model: model),
      ),
    ),
  );
  if (SailStyleValues.phoneLayoutOverride == true) {
    await tester.usePhoneSize();
  }
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(loadBundledFonts);

  setUp(() async {
    await GetIt.I.reset();
    await registerTestDependencies();
  });

  tearDown(() async {
    SailStyleValues.phoneLayoutOverride = null;
    await GetIt.I.reset();
  });

  testWidgets('on a phone each row is one line: date, status, and the amount with no unit', (tester) async {
    SailStyleValues.phoneLayoutOverride = true;
    final at = DateTime(2026, 10, 31, 18, 42);
    Timestamp stamp(DateTime t) => Timestamp.fromDateTime(t.toUtc());
    final unconfirmed = walletpb.WalletTransaction(
      txid: 'cd' * 32,
      confirmationTime: walletpb.Confirmation(height: 0, timestamp: stamp(at)),
      sentSatoshi: Int64(25000000),
    );
    final confirmed = walletpb.WalletTransaction(
      txid: 'ef' * 32,
      confirmationTime: walletpb.Confirmation(height: 120, timestamp: stamp(at.subtract(const Duration(days: 1)))),
      receivedSatoshi: Int64(50000000),
    );
    await _pumpTable(tester, _Overview([unconfirmed, confirmed]));

    final date = find.text('2026-10-31 18:42');
    final status = find.text('Unconfirmed');
    final amount = find.text('-0.2500,0000');
    expect(date, findsOneWidget);
    expect(amount, findsOneWidget);
    expect(find.textContaining('BTC'), findsNothing);
    final line = tester.getSize(find.text('Confirmed')).height;
    for (final cell in [date, status, amount]) {
      expect(tester.getSize(cell).height, line, reason: 'one line');
    }
    final statusText = tester.widget<Text>(status);
    final painter = TextPainter(
      text: TextSpan(text: 'Unconfirmed', style: statusText.style),
      textDirection: TextDirection.ltr,
    )..layout();
    expect(tester.getSize(status).width, greaterThanOrEqualTo(painter.width - 0.5), reason: 'no ellipsis');
    painter.dispose();
    expect(tester.getRect(status).left, greaterThan(tester.getRect(date).right));
    expect(tester.getRect(find.text('Date')).left, closeTo(tester.getRect(date).left, 1));
    expect(tester.getRect(find.text('Amount')).left, closeTo(tester.getRect(amount).left, 1));
    expect(tester.getRect(amount).left, greaterThan(tester.getRect(status).right));
    expect(
      tester.widget<Text>(amount).style!.fontFamily,
      tester.widget<Text>(find.text('Confirmed')).style!.fontFamily,
      reason: 'the amount uses the normal font',
    );
    expect(tester.widget<SailTable>(find.byType(SailTable)).drawGrid, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('on the desktop the history keeps the grid and the unit', (tester) async {
    SailStyleValues.phoneLayoutOverride = false;
    await _pumpTable(tester, _Overview([_deposit]));

    expect(tester.widget<SailTable>(find.byType(SailTable)).drawGrid, isTrue);
    expect(find.textContaining('BTC'), findsWidgets);
  });

  testWidgets('on a phone the loading table shows bars in a panel and what it waits for', (tester) async {
    SailStyleValues.phoneLayoutOverride = true;
    await _pumpTable(tester, _Overview(const [], loading: true));

    expect(find.byType(OverviewLoadingSkeleton), findsOneWidget);
    expect(find.text('Waiting for enforcer to boot and wallet to sync..'), findsOneWidget);
    for (var i = 0; i < OverviewLoadingSkeleton.barCount; i++) {
      final bar = find.byKey(ValueKey('overview_skeleton_bar_$i'));
      expect(tester.getSize(bar).height, OverviewLoadingSkeleton.barHeight);
    }
  });

  testWidgets('on a desktop the loading table keeps the skeletonizer', (tester) async {
    SailStyleValues.phoneLayoutOverride = false;
    // The shimmer never stops, so the frames never settle.
    await _pumpTable(tester, _Overview(const [], loading: true), settle: false);

    expect(find.byType(OverviewLoadingSkeleton), findsNothing);
    expect(find.byType(SailSkeletonizer), findsWidgets);
  });
}
