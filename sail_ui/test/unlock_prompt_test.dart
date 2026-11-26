import 'dart:async';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:sail_ui/pages/router.gr.dart' show UnlockWalletRoute;
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/gen/walletmanager/v1/walletmanager.pb.dart' as wmpb;

final _unlocked = wmpb.WatchWalletDataResponse(
  state: wmpb.WalletState.WALLET_STATE_UNLOCKED,
  encrypted: true,
  activeWalletId: 'core-1',
  wallets: [wmpb.WalletMetadata(id: 'core-1', name: 'Core', walletType: wmpb.WalletType.WALLET_TYPE_BITCOIN_CORE)],
);

final _locked = wmpb.WatchWalletDataResponse(
  state: wmpb.WalletState.WALLET_STATE_LOCKED,
  encrypted: true,
);

Future<RootStackRouter> _pumpApp(WidgetTester tester) async {
  final router = RootStackRouter.build(
    routes: [
      NamedRouteDef(name: 'HomeRoute', initial: true, builder: (_, _) => const Text('home')),
      NamedRouteDef(name: UnlockWalletRoute.name, builder: (_, _) => const Text('unlock page')),
    ],
  );
  await tester.pumpWidget(MaterialApp.router(routerConfig: router.config()));
  await tester.pumpAndSettle();
  return router;
}

int _unlockPages(StackRouter router) => router.stack.where((r) => r.name == UnlockWalletRoute.name).length;

void main() {
  setUpAll(() {
    if (!GetIt.I.isRegistered<Logger>()) {
      GetIt.I.registerSingleton<Logger>(Logger(level: Level.warning));
    }
  });

  testWidgets('a lock that the backend reports after the boot opens the unlock page one time', (tester) async {
    final router = await _pumpApp(tester);
    final reader = WalletReaderProvider(Directory.systemTemp)..applyWatchFrame(_unlocked);
    final prompt = UnlockPrompt(walletReader: reader, router: router)..start();
    addTearDown(prompt.dispose);
    await tester.pumpAndSettle();
    expect(_unlockPages(router), 0);

    reader.applyWatchFrame(_locked);
    await tester.pumpAndSettle();
    expect(find.text('unlock page'), findsOneWidget);

    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    reader.notifyListeners();
    await tester.pumpAndSettle();
    expect(_unlockPages(router), 1);

    reader.applyWatchFrame(_unlocked);
    router.pop();
    await tester.pumpAndSettle();
    expect(_unlockPages(router), 0);

    reader.applyWatchFrame(_locked);
    await tester.pumpAndSettle();
    expect(_unlockPages(router), 1, reason: 'a second lock asks for the password again');
  });

  testWidgets('the password guard waits for the page that the prompt opened', (tester) async {
    final router = await _pumpApp(tester);
    final reader = WalletReaderProvider(Directory.systemTemp)..applyWatchFrame(_locked);
    final prompt = UnlockPrompt(walletReader: reader, router: router)..start();
    addTearDown(prompt.dispose);
    await tester.pumpAndSettle();

    var guardDone = false;
    unawaited(openUnlockPage(router).then((_) => guardDone = true));
    await tester.pumpAndSettle();
    expect(_unlockPages(router), 1);
    expect(guardDone, isFalse);

    reader.applyWatchFrame(_unlocked);
    router.pop();
    await tester.pumpAndSettle();
    expect(guardDone, isTrue);
    expect(_unlockPages(router), 0);
  });

  test('needsPassword follows the wallet state of each frame', () {
    final reader = WalletReaderProvider(Directory.systemTemp);
    expect(reader.needsPassword, isFalse);

    reader.applyWatchFrame(_locked);
    expect(reader.needsPassword, isTrue);

    reader.applyWatchFrame(_unlocked);
    expect(reader.needsPassword, isFalse);

    reader.applyWatchFrame(wmpb.WatchWalletDataResponse(state: wmpb.WalletState.WALLET_STATE_NO_WALLET));
    expect(reader.needsPassword, isFalse);
  });
}
