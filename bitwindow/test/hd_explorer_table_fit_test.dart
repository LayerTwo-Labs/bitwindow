import 'dart:io';

import 'package:bitwindow/pages/wallet/wallet_hd.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/gen/walletmanager/v1/walletmanager.pb.dart' as wmpb;

import 'test_utils.dart';

const _walletPath = "m/84'/1'/0'/0";
const _taprootAddress = 'bcrt1plelv4m5avu2p8vszg53ap3hlktf9hvd36zgrqcpcgmqtgjuv4r8qapj79j';
const _publicKey = '020953e9f40d8c1fe3a6b7b2e9f1f0a2c3d4e5f60718293a4b5c6d7e8f90a1b2c3';
const _wif = 'cVt4o7BGAig1UXywgGSmARhxMdzP5qvQsxKkSsc1XEkw3tDTQFpy';

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
          address: _taprootAddress,
          publicKey: _publicKey,
          wif: _wif,
          used: tracked,
          balanceSats: Int64(tracked ? 12345678 : 0),
        ),
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
  setUpAll(loadBundledFonts);

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

  Future<void> showKeys(WidgetTester tester, double width) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 1400);
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
          child: const Scaffold(
            body: Padding(
              padding: EdgeInsets.symmetric(horizontal: SailStyleValues.padding12),
              child: HDWalletTab(),
            ),
          ),
        ),
      ),
    );
    for (final label in ['Use Wallet', 'Derive Addresses', 'Show Private Keys']) {
      await tester.ensureVisible(find.text(label));
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }
  }

  bool cutShort(WidgetTester tester, String text) =>
      tester.renderObject<RenderParagraph>(find.text(text)).didExceedMaxLines;

  for (final width in [1024.0, 1280.0]) {
    testWidgets('every column of a taproot key fits in a $width wide window', (tester) async {
      await showKeys(tester, width);

      final right = tester.getRect(find.byType(HDWalletTab)).right;
      for (final header in ['Path', 'Address', 'Used', 'Balance', 'Public Key', 'Private Key (WIF)']) {
        final cell = tester.getRect(find.text(header));
        expect(cell.right, lessThanOrEqualTo(right), reason: '$header ends past the window');
        expect(cutShort(tester, header), isFalse, reason: '$header is cut short');
      }
      expect(find.text(_publicKey), findsOneWidget);
      expect(find.text(_wif), findsOneWidget);
    });
  }

  testWidgets('a 1280 wide window shows the full address', (tester) async {
    await showKeys(tester, 1280);

    expect(cutShort(tester, _taprootAddress), isFalse);
  });

  testWidgets('a copy of a cut address gives the full address', (tester) async {
    await showKeys(tester, 1024);
    final cell = tester.widget<SailTableCell>(
      find.ancestor(of: find.text(_taprootAddress), matching: find.byType(SailTableCell)),
    );

    expect(cell.copyValue, _taprootAddress);
  });
}
