import 'dart:io';

import 'package:bitwindow/pages/wallet/wallet_hd.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/gen/walletmanager/v1/walletmanager.pb.dart' as wmpb;

import 'test_utils.dart';

const _phrase = 'fixture phrase';
const _master = 'fixture seed';
const _private = 'fixture extended key';
const _public = 'fixture public key';

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
    return wmpb.ExploreSeedResponse(
      mnemonic: _phrase,
      basePath: "m/84'/1'/0'/0",
      seedHex: _master,
      xprv: _private,
      xpub: _public,
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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late WalletReaderProvider reader;

  setUp(() async {
    final log = Logger(level: Level.off);
    GetIt.I.registerSingleton<Logger>(log);
    GetIt.I.registerSingleton<BitcoinConfProvider>(_BitcoinConf());
    GetIt.I.registerSingleton<OrchestratorRPC>(_Orchestrator());
    reader = WalletReaderProvider(Directory.systemTemp);
    GetIt.I.registerSingleton<WalletReaderProvider>(reader);
    reader.wallets = [
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
    ];
    reader.activeWalletId = 'wallet-one';
    await registerTestDependencies();
  });

  tearDown(() => GetIt.I.reset());

  for (final width in [1200.0, 480.0]) {
    testWidgets('keeps explorer secrets hidden at width ${width.toInt()}', (tester) async {
      SailStyleValues.phoneLayoutOverride = width < 600;
      addTearDown(() => SailStyleValues.phoneLayoutOverride = null);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 900);
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

      Finder field() => find.byWidgetPredicate(
        (widget) => widget is EditableText && widget.controller.text == _phrase,
      );

      await tester.tap(find.text('Use Wallet'));
      await tester.pumpAndSettle();
      expect(tester.widget<EditableText>(field()).obscureText, isTrue);

      final derive = find.text('Derive Addresses');
      await tester.ensureVisible(derive);
      await tester.tap(derive);
      await tester.pumpAndSettle();
      expect(find.text(_public), findsOneWidget);
      expect(find.text(_master), findsNothing);
      expect(find.text(_private), findsNothing);

      final show = find.text('Show');
      await tester.ensureVisible(show);
      await tester.tap(show);
      await tester.pumpAndSettle();
      expect(tester.widget<EditableText>(field()).obscureText, isFalse);
      expect(find.text(_master), findsOneWidget);
      expect(find.text(_private), findsOneWidget);

      await tester.tap(find.text('Use Wallet'));
      await tester.pumpAndSettle();
      expect(tester.widget<EditableText>(field()).obscureText, isTrue);

      final clear = find.text('Clear');
      await tester.ensureVisible(clear);
      await tester.tap(clear);
      await tester.pumpAndSettle();
      final input = find.byWidgetPredicate(
        (widget) => widget is SailTextField && widget.hintText == 'Enter mnemonic seed phrase',
      );
      await tester.enterText(find.descendant(of: input, matching: find.byType(EditableText)), _phrase);
      await tester.pumpAndSettle();
      expect(tester.widget<EditableText>(field()).obscureText, isTrue);
    });
  }
}
