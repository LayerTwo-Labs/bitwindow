import 'dart:io';

import 'package:bitwindow/pages/wallet/wallet_hd.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/gen/walletmanager/v1/walletmanager.pb.dart' as wmpb;

import 'test_utils.dart';

const _walletPath = "m/84'/1'/0'/0";
const _typedSeed = 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

class _Wallet implements OrchestratorWalletRPC {
  @override
  Future<wmpb.ExploreSeedResponse> exploreSeed({
    String mnemonic = '',
    String passphrase = '',
    String walletId = '',
    required String basePath,
    required int startIndex,
    required int count,
  }) async {
    final path = basePath.isEmpty ? _walletPath : basePath;
    final tracked = walletId.isNotEmpty && path == _walletPath;
    return wmpb.ExploreSeedResponse(
      mnemonic: walletId.isEmpty ? '' : 'words of the wallet',
      basePath: path,
      seedHex: 'seed',
      xprv: 'xprv',
      xpub: 'xpub',
      walletTracksKeys: tracked,
      keys: [
        wmpb.ExploredKey(
          path: '$path/0',
          address: 'address-zero',
          publicKey: 'pub-0',
          wif: 'wif-0',
          used: tracked,
          balanceSats: Int64(tracked ? 12345678 : 0),
        ),
        wmpb.ExploredKey(path: '$path/1', address: 'address-one', publicKey: 'pub-1', wif: 'wif-1'),
      ],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Orchestrator implements OrchestratorRPC {
  @override
  final OrchestratorWalletRPC wallet = _Wallet();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _BitcoinConf implements BitcoinConfProvider {
  @override
  bool get usesMainnetParams => false;

  @override
  BitcoinNetwork get network => BitcoinNetwork.BITCOIN_NETWORK_REGTEST;

  @override
  String ecashNetworkId = '';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() async {
    GetIt.I.registerSingleton<Logger>(Logger(level: Level.off));
    GetIt.I.registerSingleton<BitcoinConfProvider>(_BitcoinConf());
    GetIt.I.registerSingleton<OrchestratorRPC>(_Orchestrator());
    final reader = WalletReaderProvider(Directory.systemTemp)
      ..wallets = [
        WalletData(
          version: 1,
          master: MasterWallet(mnemonic: '', seedHex: '', masterKey: '', chainCode: ''),
          l1: L1Wallet(mnemonic: ''),
          sidechains: const [],
          id: 'wallet-one',
          name: 'Wallet one',
          gradient: WalletGradient.fromWalletId('wallet-one'),
          createdAt: DateTime.utc(2026),
          walletType: BinaryType.BINARY_TYPE_BITCOIND,
        ),
      ]
      ..activeWalletId = 'wallet-one';
    GetIt.I.registerSingleton<WalletReaderProvider>(reader);
    await registerTestDependencies();
  });

  tearDown(() => GetIt.I.reset());

  Future<void> pumpExplorer(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 1400);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        home: SailTheme(
          data: SailThemeData.lightTheme(
            SailColorScheme.orange,
            false,
            SailFontValues.inter,
            SailThemeStyle.bitwindowV2,
          ),
          child: const Scaffold(body: HDWalletTab()),
        ),
      ),
    );
  }

  Future<void> tap(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets('the keys of the wallet show the use that the wallet reports', (tester) async {
    await pumpExplorer(tester);

    await tester.tap(find.byType(SailRowMenuButton));
    await tester.pumpAndSettle();
    await tap(tester, 'Use Wallet');
    await tap(tester, 'Derive Addresses');

    final formatter = GetIt.I.get<FormatterProvider>();
    expect(find.text('Used'), findsOneWidget);
    expect(find.text('Balance'), findsOneWidget);
    expect(find.text('Yes'), findsOneWidget);
    expect(find.text('No'), findsOneWidget);
    expect(find.text(formatter.formatSats(12345678)), findsOneWidget);
    expect(find.text(formatter.formatSats(0)), findsOneWidget);
  });

  testWidgets('a typed seed shows no use columns', (tester) async {
    await pumpExplorer(tester);

    await tester.enterText(find.byType(EditableText).first, _typedSeed);
    await tester.pumpAndSettle();
    await tap(tester, 'Derive Addresses');

    expect(find.text('address-zero'), findsOneWidget);
    expect(find.text('Used'), findsNothing);
    expect(find.text('Balance'), findsNothing);
  });
}
