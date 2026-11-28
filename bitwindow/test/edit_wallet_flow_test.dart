import 'dart:async';

import 'package:bitwindow/widgets/edit_wallet_flow.dart';
import 'package:connectrpc/connect.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/gen/walletmanager/v1/walletmanager.pb.dart' as wmpb;

import 'test_utils.dart';

WalletData _data(String id, String name, {bool starter = false}) => WalletData(
  version: 1,
  master: MasterWallet(mnemonic: '', seedHex: '', masterKey: '', chainCode: ''),
  l1: L1Wallet(mnemonic: ''),
  sidechains: const [],
  id: id,
  name: name,
  gradient: WalletGradient.fromWalletId(id),
  createdAt: DateTime(2026),
  walletType: BinaryType.BINARY_TYPE_BITCOIND,
  isStarter: starter,
);

WalletMetadata _meta(WalletData w) => WalletMetadata(
  id: w.id,
  name: w.name,
  gradient: w.gradient,
  createdAt: w.createdAt,
  lastUsed: w.createdAt,
);

class _Wallet implements OrchestratorWalletRPC {
  Object? balanceError;
  wmpb.GetBalanceResponse balance = wmpb.GetBalanceResponse();

  @override
  Future<wmpb.GetBalanceResponse> getBalance(String walletId) async {
    if (balanceError case final e?) {
      throw e;
    }
    return balance;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Orchestrator implements OrchestratorRPC {
  @override
  final OrchestratorWalletRPC wallet;

  _Orchestrator(this.wallet);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Reader implements WalletReaderProvider {
  @override
  List<WalletData> wallets;
  Object? saveError;

  _Reader(this.wallets);

  @override
  Future<void> updateWalletMetadata(String walletId, String name, WalletGradient gradient) async {
    if (saveError case final e?) {
      throw e;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final alpha = _data('alpha', 'Alpha', starter: true);
  final beta = _data('beta', 'Beta');

  group('deleteBlockedReason', () {
    test('blocks the starter while another wallet exists', () {
      expect(
        deleteBlockedReason([alpha, beta], _meta(alpha)),
        'Alpha makes the sidechain starters. Delete the other wallets first.',
      );
    });

    test('allows the last wallet and every other wallet', () {
      expect(deleteBlockedReason([alpha], _meta(alpha)), isNull);
      expect(deleteBlockedReason([alpha, beta], _meta(beta)), isNull);
    });
  });

  group('deleteWalletSubtitle', () {
    test('names the coins that leave with the wallet', () {
      expect(
        deleteWalletSubtitle('Beta', 123456789),
        'Beta holds 1.2345,6789 BTC. The wallet leaves this computer. Its backup is the only way back.',
      );
    });

    test('an empty wallet gets the plain text', () {
      expect(deleteWalletSubtitle('Beta', 0), 'The wallet leaves this computer. Its backup is the only way back.');
    });
  });

  group('editWallet', () {
    late _Wallet wallet;
    late _Reader reader;

    Future<void> open(WidgetTester tester, WalletData target) async {
      await tester.pumpSailPage(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => unawaited(editWallet(context, _meta(target))),
            child: const Text('open'),
          ),
        ),
      );
      wallet = _Wallet();
      reader = _Reader([alpha, beta]);
      GetIt.I.registerSingleton<OrchestratorRPC>(_Orchestrator(wallet));
      GetIt.I.registerSingleton<WalletReaderProvider>(reader);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    SailButton button(WidgetTester tester, String label) =>
        tester.widget<SailButton>(find.widgetWithText(SailButton, label).last);

    tearDown(() => GetIt.I.reset());

    testWidgets('turns Delete off for the starter while another wallet exists', (tester) async {
      await open(tester, alpha);

      expect(button(tester, 'Delete wallet').disabled, isTrue);
      expect(find.text('Alpha makes the sidechain starters. Delete the other wallets first.'), findsOneWidget);
    });

    testWidgets('the confirm shows the balance of the wallet', (tester) async {
      await open(tester, beta);
      wallet.balance = wmpb.GetBalanceResponse(confirmedSats: 100000000, unconfirmedSats: 23456789);

      await tester.tap(find.widgetWithText(SailButton, 'Delete wallet'));
      await settle(tester);

      expect(find.text('Delete Beta?'), findsOneWidget);
      expect(find.textContaining('Beta holds 1.2345,6789 BTC.'), findsOneWidget);
      expect(button(tester, 'Delete wallet').disabled, isFalse);
    });

    testWidgets('a failed balance read turns the confirm off', (tester) async {
      await open(tester, beta);
      wallet.balanceError = ConnectException(Code.unavailable, 'unable to connect to Bitcoin Core');

      await tester.tap(find.widgetWithText(SailButton, 'Delete wallet'));
      await settle(tester);

      expect(
        find.text(
          'Could not read the balance of Beta: unable to connect to Bitcoin Core. Delete is off until the balance shows.',
        ),
        findsOneWidget,
      );
      expect(button(tester, 'Delete wallet').disabled, isTrue);
    });
  });
}
