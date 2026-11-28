import 'dart:async';

import 'package:bitwindow/providers/address_book_provider.dart';
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
  String? get historyError => null;

  @override
  ({DateTime start, DateTime end})? get dateRange => null;

  @override
  bool get filtered => false;

  final saved = <String, String>{};
  final feeDialog = Completer<void>();

  final bumped = <String>[];

  @override
  Future<void> openBumpFee(BuildContext context, walletpb.WalletTransaction tx) {
    bumped.add(tx.txid);
    return feeDialog.future;
  }

  @override
  Future<void> saveNote(BuildContext context, String txid, String note) async {
    saved[txid] = note;
    Navigator.of(context).pop();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Conf extends ChangeNotifier implements BitcoinConfProvider {
  @override
  BitcoinNetwork get network => BitcoinNetwork.BITCOIN_NETWORK_REGTEST;

  @override
  String get ecashNetworkId => '';

  @override
  String get currentNetworkOptionId => '';

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
    GetIt.I.registerSingleton<AddressBookProvider>(AddressBookProvider());
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
      confirmations: 1,
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
    expect(tester.widget<SailTable>(find.byType(SailTable)).resizableColumns, isFalse, reason: 'no header dividers');
    expect(tester.takeException(), isNull);
  });

  testWidgets('on the desktop each amount shows its unit on a second line', (tester) async {
    SailStyleValues.phoneLayoutOverride = false;
    await _pumpTable(tester, _Overview([_deposit]));

    final amount = find.text('-0.0100,0000');
    final unit = find.text('BTC');
    expect(amount, findsOneWidget);
    expect(unit, findsOneWidget);
    expect(tester.getRect(unit).top, greaterThanOrEqualTo(tester.getRect(amount).bottom));
  });

  for (final width in [1024.0, 1200.0]) {
    testWidgets('the history fee action sits in the row menu at desktop width $width', (tester) async {
      SailStyleValues.phoneLayoutOverride = false;
      final time = Timestamp.fromDateTime(DateTime.utc(2026, 11, 25, 9, 22));
      final outgoing = walletpb.WalletTransaction(
        txid: 'cd' * 32,
        address: 'bcrt1q00hcx2zjh338tnahn5lr89v4lycng73ls369q6',
        confirmationTime: walletpb.Confirmation(timestamp: time),
        sentSatoshi: Int64(1234567),
        feeSats: Int64(10000),
      );
      final coinbase = walletpb.WalletTransaction(
        txid: 'ef' * 32,
        address: 'bcrt1qj7tvw28e5a85rxl6fhkajlh2d2ka9vz6rxzesr',
        confirmationTime: walletpb.Confirmation(height: 103, timestamp: time),
        confirmations: 1,
        immature: true,
        receivedSatoshi: Int64(5000000000),
      );
      GetIt.I.registerSingleton<BitcoinConfProvider>(_Conf());
      final model = _Overview([outgoing, coinbase]);
      await tester.pumpSailPage(
        Center(
          child: SizedBox(
            width: width - 24,
            height: 550,
            child: TransactionTable(searchWidget: const SizedBox.shrink(), model: model),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(SailButton, 'Bump fee'), findsNothing, reason: 'no buttons in rows');
      final table = find.byType(SailTable);
      final menu = find.byType(SailRowMenuButton);
      expect(menu, findsNWidgets(2));
      final sentRow = tester.getCenter(find.text('Sent')).dy;
      final sentMenu = menu.evaluate().firstWhere(
        (element) => (tester.getCenter(find.byWidget(element.widget)).dy - sentRow).abs() < 20,
      );
      expect(tester.getRect(find.byWidget(sentMenu.widget)).right, lessThanOrEqualTo(tester.getRect(table).right));
      await tester.tap(find.byWidget(sentMenu.widget));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bump fee'));
      await tester.pumpAndSettle();
      expect(model.bumped, ['cd' * 32]);
      expect(tester.takeException(), isNull);
      model.feeDialog.complete();
      await tester.pumpAndSettle();
    });
  }

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

  testWidgets('on a phone the row menu opens again after a note', (tester) async {
    SailStyleValues.phoneLayoutOverride = true;
    final tx = walletpb.WalletTransaction(
      txid: 'ef' * 32,
      confirmations: 1,
      confirmationTime: walletpb.Confirmation(height: 120, timestamp: Timestamp.fromDateTime(DateTime.utc(2026))),
      receivedSatoshi: Int64(50000000),
    );
    GetIt.I.registerSingleton<BitcoinConfProvider>(_Conf());
    final model = _Overview([tx]);
    await _pumpTable(tester, model);

    for (var i = 1; i <= 2; i++) {
      await tester.longPress(find.text('Confirmed'));
      await tester.pumpAndSettle();
      expect(find.text('Add Note'), findsOneWidget, reason: 'press $i opens the menu');
      await tester.tap(find.text('Add Note'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText).last, 'rent $i');
      await tester.tap(find.text('Save changes').last);
      await tester.pumpAndSettle();
      expect(model.saved[tx.txid], 'rent $i');
    }
  });
}
