import 'dart:io';

import 'package:bitwindow/providers/hd_wallet_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/gen/multisiglounge/v1/multisiglounge.pb.dart' as mlpb;

class _Lounge implements OrchestratorMultisigLoungeRPC {
  final calls = <({String walletId, String path})>[];

  @override
  Future<mlpb.DeriveWalletKeyResponse> deriveWalletKey({
    required String walletId,
    required String derivationPath,
  }) async {
    calls.add((walletId: walletId, path: derivationPath));
    return mlpb.DeriveWalletKeyResponse(
      xpub: 'tpubDC8msFGeGuwnKG9Upg7DM2b4DaRqg3CUZa5g8v2SRQ6K4NSkxUgd7HsL2XVWbVm39yBA4LAxysQAm397zwQSQoQgewGiYZqrA9DsP4zbQ1M',
      fingerprint: '73c5da0a',
      originPath: derivationPath.substring(2),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeOrchestrator implements OrchestratorRPC {
  _FakeOrchestrator(this.multisigLounge);

  @override
  final OrchestratorMultisigLoungeRPC multisigLounge;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Lounge lounge;
  late WalletReaderProvider reader;
  late HDWalletProvider hd;

  setUp(() async {
    await GetIt.I.reset();
    GetIt.I.registerSingleton<Logger>(Logger(level: Level.warning));
    reader = WalletReaderProvider(Directory.systemTemp);
    GetIt.I.registerSingleton<WalletReaderProvider>(reader);
    lounge = _Lounge();
    GetIt.I.registerSingleton<OrchestratorRPC>(_FakeOrchestrator(lounge));
    hd = HDWalletProvider();
  });

  tearDown(() async {
    hd.dispose();
    reader.dispose();
    await GetIt.I.reset();
  });

  test('uses the selected wallet and the test network account path', () async {
    reader.activeWalletId = 'first';

    final info = await hd.generateWalletXpub(3);

    expect(lounge.calls.single, (walletId: 'first', path: "m/84'/1'/3'"));
    expect(info['xpub'], startsWith('tpub'));
    expect(info['fingerprint'], '73c5da0a');
    expect(info['derivation_path'], "m/84'/1'/3'");
    expect(info['origin_path'], "84'/1'/3'");
    expect(info['xpub_with_origin'], "[73c5da0a/84'/1'/3']${info['xpub']}");
  });

  test('uses the new wallet after a switch', () async {
    reader.activeWalletId = 'first';
    await hd.generateWalletXpub(0);
    reader.activeWalletId = 'second';
    await hd.generateWalletXpub(0);

    expect(lounge.calls.map((call) => call.walletId), ['first', 'second']);
  });

  test('uses coin type 0 on mainnet', () async {
    reader.activeWalletId = 'first';
    await hd.generateWalletXpub(0, true);

    expect(lounge.calls.single.path, "m/84'/0'/0'");
  });

  test('does not derive a key without a selected wallet', () async {
    await expectLater(hd.generateWalletXpub(0), throwsStateError);
    expect(lounge.calls, isEmpty);
  });
}
