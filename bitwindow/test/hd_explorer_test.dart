import 'dart:async';
import 'dart:io';

import 'package:bitwindow/pages/wallet/wallet_hd.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/gen/walletmanager/v1/walletmanager.pb.dart' as wmpb;

const _mnemonic = 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

class _Explore {
  _Explore(this.mnemonic, this.walletId, this.basePath, this.startIndex, this.count);

  final String mnemonic;
  final String walletId;
  final String basePath;
  final int startIndex;
  final int count;
}

class _FakeWallet implements OrchestratorWalletRPC {
  final explores = <_Explore>[];
  final walletPaths = {'w1': "m/84'/1'/0'/0", 'w2': "m/84'/1'/2'/0"};
  Object? exploreError;
  Completer<void>? gate;

  @override
  Future<wmpb.ExploreSeedResponse> exploreSeed({
    String mnemonic = '',
    String passphrase = '',
    String walletId = '',
    required String basePath,
    required int startIndex,
    required int count,
  }) async {
    explores.add(_Explore(mnemonic, walletId, basePath, startIndex, count));
    await gate?.future;
    if (exploreError != null) {
      throw exploreError!;
    }
    final path = walletId.isNotEmpty && basePath.isEmpty ? walletPaths[walletId]! : basePath;
    final tracked = walletId.isNotEmpty && path == walletPaths[walletId];
    return wmpb.ExploreSeedResponse(
      walletTracksKeys: tracked,
      seedHex: walletId.isEmpty ? 'seed' : 'seed-$walletId',
      mnemonic: walletId.isEmpty ? '' : 'words of $walletId',
      basePath: path,
      xprv: 'xprv-master',
      xpub: 'xpub-master',
      bip47PaymentCode: 'PM8code',
      watchDescriptor: 'wpkh($path)',
      keys: [
        for (var i = startIndex; i < startIndex + 2; i++)
          wmpb.ExploredKey(
            path: '$path/$i',
            address: '${walletId}addr-$i',
            publicKey: 'pub-$i',
            wif: 'wif-$i',
            used: tracked && i == 0,
            balanceSats: Int64(tracked && i == 0 ? 1000 : 0),
          ),
      ],
    );
  }

  @override
  Future<String> generateMnemonic() async => _mnemonic;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeOrchestrator implements OrchestratorRPC {
  _FakeOrchestrator(this.wallet);

  @override
  final OrchestratorWalletRPC wallet;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Conf extends ChangeNotifier implements BitcoinConfProvider {
  @override
  bool get usesMainnetParams => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

WalletData _wallet(String id, {bool starter = false}) => WalletData(
  version: 1,
  master: MasterWallet(mnemonic: '', seedHex: '', masterKey: '', chainCode: ''),
  l1: L1Wallet(mnemonic: starter ? 'starter words' : ''),
  sidechains: const [],
  id: id,
  name: id,
  gradient: WalletGradient.fromWalletId(id),
  createdAt: DateTime(2026),
  walletType: BinaryType.BINARY_TYPE_BITCOIND,
  isStarter: starter,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeWallet wallet;
  late WalletReaderProvider reader;

  setUp(() async {
    await GetIt.I.reset();
    wallet = _FakeWallet();
    GetIt.I.registerSingleton<Logger>(Logger(level: Level.off));
    reader = WalletReaderProvider(Directory.systemTemp)
      ..wallets = [_wallet('w1', starter: true), _wallet('w2')]
      ..activeWalletId = 'w2';
    GetIt.I.registerSingleton<WalletReaderProvider>(reader);
    GetIt.I.registerSingleton<BitcoinConfProvider>(_Conf());
    GetIt.I.registerSingleton<OrchestratorRPC>(_FakeOrchestrator(wallet));
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  test('derives the first page of the default path in the orchestrator', () async {
    final model = HDWalletViewModel()..mnemonicController.text = _mnemonic;

    await model.deriveAddresses();

    final call = wallet.explores.single;
    expect(call.mnemonic, _mnemonic);
    expect(call.basePath, "m/84'/0'/0'/0");
    expect(call.startIndex, 0);
    expect(call.count, 20);
    expect(model.errorMessage, isNull);
    expect(model.masterSeed, 'seed');
    expect(model.xpriv, 'xprv-master');
    expect(model.xpub, 'xpub-master');
    expect(model.bip47PaymentCode, 'PM8code');
    expect(model.derivedEntries.map((e) => (e.path, e.address, e.publicKey, e.privateKey)), [
      ("m/84'/0'/0'/0/0", 'addr-0', 'pub-0', 'wif-0'),
      ("m/84'/0'/0'/0/1", 'addr-1', 'pub-1', 'wif-1'),
    ]);
  });

  test('the next page starts twenty keys later', () async {
    final model = HDWalletViewModel()..mnemonicController.text = _mnemonic;
    await model.deriveAddresses();

    await model.changePage(true);

    expect(wallet.explores.last.startIndex, 20);
    expect(model.derivedEntries.first.path, "m/84'/0'/0'/0/20");
  });

  test('a failed page keeps the page on the screen and its number', () async {
    final model = HDWalletViewModel()..mnemonicController.text = _mnemonic;
    await model.deriveAddresses();
    wallet.exploreError = Exception('connection refused');

    await model.changePage(true);

    expect(model.currentPage, 0);
    expect(model.derivedEntries.first.path, "m/84'/0'/0'/0/0");
    expect(model.errorMessage, contains('connection refused'));

    wallet.exploreError = null;
    await model.changePage(true);

    expect(model.currentPage, 1);
    expect(model.derivedEntries.first.path, "m/84'/0'/0'/0/20");
    expect(model.errorMessage, isNull);
  });

  test('a new derive starts at the first page', () async {
    final model = HDWalletViewModel()..mnemonicController.text = _mnemonic;
    await model.deriveAddresses();
    await model.changePage(true);
    await model.changePage(true);

    await model.deriveAddresses();

    expect(model.currentPage, 0);
    expect(wallet.explores.last.startIndex, 0);
  });

  test('an edit of the mnemonic or of the path drops the keys of the old one', () async {
    for (final edit in <void Function(HDWalletViewModel)>[
      (m) => m.mnemonicController.text = '$_mnemonic about',
      (m) => m.derivationPathController.text = "m/86'/0'/0'/0",
    ]) {
      final model = HDWalletViewModel()..mnemonicController.text = _mnemonic;
      await model.deriveAddresses();
      await model.changePage(true);
      expect(model.xpriv, isNotEmpty);

      edit(model);

      expect(model.masterSeed, isEmpty);
      expect(model.xpriv, isEmpty);
      expect(model.xpub, isEmpty);
      expect(model.bip47PaymentCode, isEmpty);
      expect(model.watchDescriptor, isEmpty);
      expect(model.derivedEntries, isEmpty);
      expect(model.currentPage, 0);
      expect(model.canGoNext, isFalse);
    }
  });

  test('an answer for an older mnemonic does not show', () async {
    wallet.gate = Completer<void>();
    final model = HDWalletViewModel()..mnemonicController.text = _mnemonic;

    final pending = model.deriveAddresses();
    model.mnemonicController.text = '$_mnemonic about';
    wallet.gate!.complete();
    await pending;

    expect(model.xpriv, isEmpty);
    expect(model.derivedEntries, isEmpty);
  });

  test('the orchestrator alone decides if a path is valid', () async {
    final model = HDWalletViewModel()..mnemonicController.text = _mnemonic;
    var changes = 0;
    model.addListener(() => changes++);

    for (final path in ["m/0'/0", '84h/0h/0h/0', "m/48'/0'/0'/2'/0", 'm/0']) {
      model.derivationPathController.text = path;
      expect(model.canDeriveAddresses, isTrue, reason: path);
    }
    expect(changes, 4);

    model.derivationPathController.text = ' ';
    expect(model.canDeriveAddresses, isFalse);
  });

  test('shows the watch descriptor of the account', () async {
    final model = HDWalletViewModel()..mnemonicController.text = _mnemonic;

    await model.deriveAddresses();

    expect(model.watchDescriptor, "wpkh(m/84'/0'/0'/0)");
  });

  test('shows the reason when the orchestrator refuses', () async {
    wallet.exploreError = Exception('invalid mnemonic');
    final model = HDWalletViewModel()..mnemonicController.text = 'abandon abandon';

    await model.deriveAddresses();

    expect(model.errorMessage, contains('invalid mnemonic'));
    expect(model.derivedEntries, isEmpty);
  });

  test('asks for nothing without a mnemonic', () async {
    final model = HDWalletViewModel();

    await model.deriveAddresses();

    expect(wallet.explores, isEmpty);
    expect(model.errorMessage, 'Please enter a mnemonic seed phrase');
  });

  test('a random mnemonic comes from the orchestrator', () async {
    final model = HDWalletViewModel();

    await model.generateRandomMnemonic();

    expect(model.mnemonicController.text, _mnemonic);
  });

  test('Clear drops the keys of a request that is still open', () async {
    wallet.gate = Completer<void>();
    final model = HDWalletViewModel()..mnemonicController.text = _mnemonic;

    final pending = model.deriveAddresses();
    model.clearAll();
    wallet.gate!.complete();
    await pending;

    expect(model.masterSeed, isEmpty);
    expect(model.xpriv, isEmpty);
    expect(model.bip47PaymentCode, isEmpty);
    expect(model.derivedEntries, isEmpty);
  });

  test('Use Wallet explores the active wallet by its stored seed', () async {
    final model = HDWalletViewModel();

    await model.useWalletMnemonic();

    expect(wallet.explores.single.walletId, 'w2');
    expect(wallet.explores.single.mnemonic, isEmpty);
    expect(model.mnemonicController.text, 'words of w2');
    expect(model.derivationPathController.text, "m/84'/1'/2'/0");
    expect(model.derivedEntries, isEmpty);

    await model.deriveAddresses();

    final call = wallet.explores.last;
    expect(call.walletId, 'w2');
    expect(call.mnemonic, isEmpty);
    expect(call.basePath, "m/84'/1'/2'/0");
    expect(model.masterSeed, 'seed-w2');
    expect(model.derivedEntries.first.address, 'w2addr-0');
  });

  test('an edited mnemonic is explored as typed, not as the wallet', () async {
    final model = HDWalletViewModel();
    await model.useWalletMnemonic();
    model.mnemonicController.text = _mnemonic;

    await model.deriveAddresses();

    expect(wallet.explores.last.walletId, isEmpty);
    expect(wallet.explores.last.mnemonic, _mnemonic);
  });

  test('a switch to another wallet drops the keys of the old one', () async {
    final model = HDWalletViewModel();
    await model.useWalletMnemonic();
    await model.deriveAddresses();
    expect(model.derivedEntries, isNotEmpty);

    reader.activeWalletId = 'w1';
    reader.notifyListeners();

    expect(model.mnemonicController.text, isEmpty);
    expect(model.masterSeed, isEmpty);
    expect(model.derivedEntries, isEmpty);
    expect(model.derivationPathController.text, model.defaultDerivationPath);
  });

  test('keys of a wallet chain carry the use that the wallet reports', () async {
    final model = HDWalletViewModel();
    await model.useWalletMnemonic();

    await model.deriveAddresses();

    expect(model.walletTracksKeys, isTrue);
    expect(model.derivedEntries.map((e) => (e.used, e.balanceSats)), [(true, 1000), (false, 0)]);
  });

  test('keys off the wallet chains carry no use', () async {
    final model = HDWalletViewModel();
    await model.useWalletMnemonic();
    await model.deriveAddresses();

    model.derivationPathController.text = "m/86'/1'/2'/0";
    expect(model.walletTracksKeys, isFalse, reason: 'an edit drops the keys and their use');
    await model.deriveAddresses();

    expect(model.walletTracksKeys, isFalse);
    expect(model.derivedEntries.map((e) => (e.used, e.balanceSats)), [(null, null), (null, null)]);
  });

  test('Use Wallet shows the reason when the wallet holds no seed', () async {
    wallet.exploreError = Exception('wallet w2 holds no single seed to explore');
    final model = HDWalletViewModel();

    await model.useWalletMnemonic();

    expect(model.errorMessage, contains('holds no single seed'));
    expect(model.mnemonicController.text, isEmpty);
  });

  test('Use Wallet drops the answer when another wallet becomes active first', () async {
    wallet.gate = Completer<void>();
    final model = HDWalletViewModel();

    final pending = model.useWalletMnemonic();
    reader.activeWalletId = 'w1';
    reader.notifyListeners();
    wallet.gate!.complete();
    await pending;

    expect(model.mnemonicController.text, isEmpty);
    expect(model.derivationPathController.text, model.defaultDerivationPath);
  });
}
