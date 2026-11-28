import 'dart:async';

import 'package:bitwindow/pages/welcome/multisig_config_step.dart';
import 'package:bitwindow/widgets/setup_action_button.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/gen/walletmanager/v1/walletmanager.pb.dart' as wmpb;

import 'test_utils.dart';

const _defaultPath = "m/84'/1'/0'";
const _secondAccount = "m/84'/1'/1'";

class _FakeWallet implements OrchestratorWalletRPC {
  final derivedPaths = <String>[];
  Completer<void>? pathsGate;

  @override
  Future<wmpb.ListDerivationPathsResponse> listDerivationPaths({
    required String scriptType,
    required bool multisig,
    int account = 0,
  }) async {
    await pathsGate?.future;
    return wmpb.ListDerivationPathsResponse(defaultPath: multisig ? "m/48'/1'/$account'/2'" : _defaultPath);
  }

  @override
  Future<wmpb.ValidateDerivationPathResponse> validateDerivationPath(String path, {bool multisig = false}) async =>
      wmpb.ValidateDerivationPathResponse(normalized: path);

  @override
  Future<List<wmpb.HardwareDevice>> enumerateHardwareDevices({String? passphrase}) async => [
    wmpb.HardwareDevice(type: 'trezor', model: 'Trezor T', path: 'usb:1', fingerprint: 'd34db33f'),
  ];

  @override
  Future<wmpb.DeriveKeystoreResponse> deriveKeystore({
    String? mnemonic,
    String? passphrase,
    wmpb.HardwareDeviceSelector? device,
    String? rawKey,
    String scriptType = '',
    bool multisig = false,
    int account = 0,
    String derivationPath = '',
  }) async {
    derivedPaths.add(derivationPath);
    return wmpb.DeriveKeystoreResponse(
      xpub: 'tpubD6NzVbkrYhZ4X',
      originPath: derivationPath.substring(2).replaceAll("'", 'h'),
      fingerprint: 'd34db33f',
    );
  }

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

void main() {
  late _FakeWallet wallet;

  setUp(() async {
    await GetIt.I.reset();
    GetIt.I.registerSingleton<Logger>(Logger(level: Level.off));
    wallet = _FakeWallet();
    GetIt.I.registerSingleton<OrchestratorRPC>(_FakeOrchestrator(wallet));
  });

  tearDown(() async {
    SailStyleValues.phoneLayoutOverride = null;
    await GetIt.I.reset();
  });

  testWidgets('on a phone the key sources are normal buttons and links with no dots', (tester) async {
    SailStyleValues.phoneLayoutOverride = true;
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await loadBundledFonts();
    await tester.pumpSailPage(
      SizedBox(width: 390, height: 720, child: MultisigConfigStep(onConfigured: (_) async {})),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SetupActionButton), findsNothing);
    expect(find.text('\u00b7'), findsNothing);
    expect(tester.widget<Text>(find.text('Keys')).style!.fontSize, 15);
    final generate = tester.getRect(find.widgetWithText(SailButton, 'Generate new seed').first);
    expect(generate.height, lessThan(44));
    expect(generate.width, lessThan(200));
    final keys = tester.getRect(find.text('Keys'));
    expect(generate.left, closeTo(keys.left, 2));
    expect(tester.getRect(find.text('xPub/ Watch Only').first).left, closeTo(keys.left, 16));
    expect(tester.takeException(), isNull);
  });

  testWidgets('on the desktop the key sources keep the large buttons and dotted links', (tester) async {
    SailStyleValues.phoneLayoutOverride = false;
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await tester.pumpSailPage(MultisigConfigStep(onConfigured: (_) async {}));
    await tester.pumpAndSettle();

    expect(find.byType(SetupActionButton), findsNWidgets(2));
    expect(find.text('\u00b7'), findsWidgets);
  });

  testWidgets('a hardware wallet reads the account the user picks', (tester) async {
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await tester.pumpSailPage(MultisigConfigStep(onConfigured: (_) async {}));
    await tester.pumpAndSettle();

    final pathField = find.widgetWithText(SailTextField, _defaultPath);
    expect(pathField, findsOneWidget, reason: 'the path shows before a key is added');

    await tester.enterText(find.descendant(of: pathField, matching: find.byType(EditableText)), _secondAccount);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hardware Wallet').hitTestable().first);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Trezor T'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(wallet.derivedPaths, [_secondAccount]);
    expect(find.widgetWithText(SailTextField, 'm/84h/1h/1h'), findsOneWidget, reason: 'the field shows the new key');
  });

  testWidgets('a new key slot shows its own path, and the device reads it', (tester) async {
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await tester.pumpSailPage(MultisigConfigStep(onConfigured: (_) async {}));
    await tester.pumpAndSettle();

    final pathField = find.widgetWithText(SailTextField, _defaultPath);
    await tester.enterText(find.descendant(of: pathField, matching: find.byType(EditableText)), _secondAccount);
    await tester.pumpAndSettle();
    final addKey = find.byWidgetPredicate((w) => w is SailIconBoxButton && w.icon == SailSVGAsset.plus);
    await tester.tap(addKey.hitTestable().first);
    await tester.pumpAndSettle();

    const slotPath = "m/48'/1'/1'/2'";
    expect(find.widgetWithText(SailTextField, slotPath), findsOneWidget);
    await tester.tap(find.text('Hardware Wallet').hitTestable().first);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Trezor T'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(wallet.derivedPaths, [slotPath]);
  });

  testWidgets('a smaller quorum shows the path of the slot it selects', (tester) async {
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await tester.pumpSailPage(MultisigConfigStep(onConfigured: (_) async {}));
    await tester.pumpAndSettle();

    final addKey = find.byWidgetPredicate((w) => w is SailIconBoxButton && w.icon == SailSVGAsset.plus);
    await tester.tap(addKey.hitTestable().first);
    await tester.pumpAndSettle();
    await tester.tap(addKey.hitTestable().first);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(SailTextField, "m/48'/1'/2'/2'"), findsOneWidget);

    tester.widget<SailSlider>(find.byType(SailSlider).first).onRangeChanged!(2, 2);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(SailTextField, "m/48'/1'/1'/2'"), findsOneWidget);
  });

  testWidgets('a switch to one key clears the multisig path at once', (tester) async {
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await tester.pumpSailPage(MultisigConfigStep(onConfigured: (_) async {}));
    await tester.pumpAndSettle();

    final addKey = find.byWidgetPredicate((w) => w is SailIconBoxButton && w.icon == SailSVGAsset.plus);
    await tester.tap(addKey.hitTestable().first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Key 1').hitTestable().first);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(SailTextField, "m/48'/1'/0'/2'"), findsOneWidget);

    final gate = Completer<void>();
    wallet.pathsGate = gate;
    tester.widget<SailSlider>(find.byType(SailSlider).first).onRangeChanged!(1, 1);
    await tester.pump();
    expect(find.widgetWithText(SailTextField, "m/48'/1'/0'/2'"), findsNothing);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.widgetWithText(SailTextField, _defaultPath), findsOneWidget);
  });

  Future<SingleSigResult> addKeyAndNext(WidgetTester tester, Future<void> Function() addKey) async {
    WalletSetupResult? result;
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await tester.pumpSailPage(MultisigConfigStep(onConfigured: (r) async => result = r));
    await tester.pumpAndSettle();
    await addKey();
    await tester.tap(find.text('Next'));
    await tester.pump(const Duration(milliseconds: 500));
    return result!.single!;
  }

  testWidgets('a pasted xpub is watched by Bitcoin Core on a full node', (tester) async {
    const key =
        '[73c5da0a/84h/1h/0h]tpubDC8msFGeGuwnKG9Upg7DM2b4DaRqg3CUZa5g8v2SRQ6K4NSkxUgd7HsL2XVWbVm39yBA4LAxysQAm397zwQSQoQgewGiYZqrA9DsP4zbQ1M';
    final single = await addKeyAndNext(tester, () async {
      await tester.tap(find.text('xPub/ Watch Only').hitTestable().first);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.enterText(find.byType(EditableText).last, key);
      await tester.tap(find.text('Add'));
      await tester.pump(const Duration(milliseconds: 500));
    });

    expect(single.provider, 'core');
    expect(single.mnemonic, isNull);
    expect(single.xpubOrDescriptor, 'wpkh($key)');
  });

  testWidgets('a hardware key stays on electrum, which signs with the device', (tester) async {
    final single = await addKeyAndNext(tester, () async {
      await tester.tap(find.text('Hardware Wallet').hitTestable().first);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Trezor T'));
      await tester.pumpAndSettle();
    });

    expect(single.provider, 'electrum');
    expect(single.hardwareDeviceType, 'trezor');
  });

  const pastedKey =
      '[73c5da0a/84h/1h/0h]tpubDC8msFGeGuwnKG9Upg7DM2b4DaRqg3CUZa5g8v2SRQ6K4NSkxUgd7HsL2XVWbVm39yBA4LAxysQAm397zwQSQoQgewGiYZqrA9DsP4zbQ1M';
  final addKeyBox = find.byWidgetPredicate((w) => w is SailIconBoxButton && w.icon == SailSVGAsset.plus);

  Future<void> pasteKey(WidgetTester tester) async {
    await tester.tap(find.text('xPub/ Watch Only').hitTestable().first);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.enterText(find.byType(EditableText).last, pastedKey);
    await tester.tap(find.text('Add'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  }

  testWidgets('an empty key offers Delete key in a "…" next to "+"', (tester) async {
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await tester.pumpSailPage(MultisigConfigStep(onConfigured: (_) async {}));
    await tester.pumpAndSettle();
    expect(find.byType(SailRowMenuButton), findsNothing, reason: 'the last key cannot be deleted');

    await tester.tap(addKeyBox.hitTestable().first);
    await tester.pumpAndSettle();
    expect(find.text('Key 2'), findsOneWidget);
    expect(tester.widgetList<SailTabItem>(find.byType(SailTabItem)).where((t) => t.trailing != null), isEmpty);

    await tester.tap(find.byType(SailRowMenuButton));
    await tester.pumpAndSettle();
    expect(find.text('Rename key'), findsNothing);
    await tester.tap(find.text('Delete key'));
    await tester.pumpAndSettle();

    expect(find.text('Key 2'), findsNothing);
    expect(find.text('Key 1'), findsOneWidget);
  });

  testWidgets('a filled key has a green check on its tab and Rename key in the details "…"', (tester) async {
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await tester.pumpSailPage(MultisigConfigStep(onConfigured: (_) async {}));
    await tester.pumpAndSettle();
    await pasteKey(tester);

    final tab = find.ancestor(of: find.text('Key 1'), matching: find.byType(SailTabItem));
    expect(tester.widget<SailTabItem>(tab).leading, isNotNull);
    expect(tester.widget<SailTabItem>(tab).onLabelChanged, isNull);
    expect(find.byType(SailStatusPill), findsOneWidget);

    await tester.tap(find.byType(SailRowMenuButton));
    await tester.pumpAndSettle();
    expect(find.text('Delete key'), findsNothing, reason: 'the last key cannot be deleted');
    await tester.tap(find.text('Rename key'));
    await tester.pumpAndSettle();

    expect(find.text('Rename key'), findsOneWidget);
    await tester.enterText(find.byType(EditableText).last, 'Cold key');
    await tester.tap(find.widgetWithText(SailButton, 'Rename'));
    await tester.pumpAndSettle();

    expect(find.text('Cold key'), findsOneWidget);
    expect(find.text('Cold key Details'), findsOneWidget);
  });
}
