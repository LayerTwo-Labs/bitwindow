// Drives Thunder in the app process of a phone against the regtest stack of
// scripts/phone-regtest.sh: a deposit from L1 and a Thunder payment.
// Run it on a fresh install; see integration_test/phone_regtest/README.md.
import 'package:bitwindow/main.dart' as app;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sail_ui/sail_ui.dart';

import 'phone_regtest/regtest.dart';
import 'phone_regtest/thunder_rpc.dart';
import 'phone_regtest/ui.dart';

final _bcrt = RegExp(r'^bcrt1[0-9a-z]{20,}$');

Finder _button(String label) => find.byWidgetPredicate((w) => w is SailButton && w.label == label);

/// [finder] inside the card titled [title]. The app keeps other tabs with the same fields in the tree.
Finder _inCard(String title, Finder finder) =>
    find.descendant(of: find.widgetWithText(SailCard, title), matching: finder);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a phone deposits to Thunder and pays on Thunder', (tester) async {
    final regtest = RegtestControl.fromDefine();
    final thunder = ThunderRpc.fromDefine();
    final ui = PhoneUi(tester, binding);
    final testHandler = FlutterError.onError;
    final testErrorWidget = ErrorWidget.builder;
    try {
      await _thunder(tester, ui, regtest, thunder);
    } catch (_) {
      await ui.shot('failure');
      rethrow;
    } finally {
      FlutterError.onError = testHandler;
      ErrorWidget.builder = testErrorWidget;
    }
    expect(ui.layoutErrors, isEmpty, reason: 'layout overflows on a phone');
  }, timeout: const Timeout(Duration(minutes: 60)));
}

Future<void> _thunder(WidgetTester tester, PhoneUi ui, RegtestControl regtest, ThunderRpc thunder) async {
  app.main([]);
  await ui.waitFor(find.text('No wallet'), timeout: const Duration(minutes: 3), reason: 'the empty first start');
  await ui.settle(const Duration(seconds: 2));
  ui.watchLayoutErrors();

  ui.step('create-wallet');
  await ui.waitFor(find.text('All binaries connected'), timeout: const Duration(minutes: 4));
  await ui.tap(ui.topmost(find.text('No wallet')));
  await ui.tapText('Generate wallet');
  await ui.waitFor(find.text('Continue'));
  await ui.tapText('Continue');
  await ui.tapText('Skip and create wallet');
  await ui.tapText('Create without backup');
  await ui.waitFor(find.text('wallet1'), timeout: const Duration(minutes: 2));
  await ui.shot('wallet');

  ui.step('receive');
  await ui.navigate('Wallet');
  await ui.tapText('Receive');
  await ui.waitUntil(() => ui.fieldText(_bcrt).isNotEmpty, 'a receive address');
  final address = ui.fieldText(_bcrt);
  // A live BMM bid holds the coin it spends and its change, so the deposit gets a coin of its own.
  await regtest.send(address, '1');
  await regtest.send(address, '1');
  await regtest.mine(1);
  await ui.tapText('Overview');
  await ui.waitFor(find.text('Confirmed'), timeout: const Duration(minutes: 3), reason: 'a confirmed receive');
  await ui.shot('l1-funded');

  ui.step('start-thunder');
  await ui.navigate('Sidechains');
  await ui.waitFor(find.text('Thunder'), timeout: const Duration(minutes: 2), reason: 'the active Thunder slot');
  await ui.settle(const Duration(seconds: 2));
  await ui.longPressUntil(find.text('Thunder'), find.text('Start Thunder'));
  await ui.shot('thunder-menu');
  await ui.tapText('Start Thunder');
  // The start opens the chain page.
  final binaries = GetIt.I.get<BinaryProvider>();
  await ui.waitUntil(
    () {
      final error = binaries.connectionError(Thunder());
      if (error != null && error.startsWith('start thunder')) {
        throw TestFailure('Thunder did not start: $error');
      }
      return find.text('Running').evaluate().isNotEmpty;
    },
    'Thunder runs in the app',
    timeout: const Duration(minutes: 3),
  );
  await ui.waitUntilAsync(() async {
    try {
      await thunder.blockCount();
      return true;
    } on Object {
      return false;
    }
  }, 'the Thunder RPC');
  await ui.settle(const Duration(seconds: 3));
  await ui.shot('thunder-running');

  // A new tip is a new BMM round: the engine bids on it, and the next block takes the bid.
  Future<void> mineUntil(Future<bool> Function() done, String what) async {
    for (var block = 0; block < 40; block++) {
      if (await done()) {
        return;
      }
      await regtest.mine(1);
      await ui.settle(const Duration(seconds: 8));
    }
    if (!await done()) {
      throw TestFailure('mined 40 blocks and waited for $what');
    }
  }

  ui.step('deposit');
  await ui.tap(find.text('Deposit').hitTestable().first);
  await ui.waitFor(find.text('Deposit to Thunder'));
  await ui.waitUntil(() => ui.fieldText(RegExp(r'^s9_')).isNotEmpty, 'the deposit address from Thunder');
  await ui.enter(find.text('0.00'), '0.5');
  await ui.settle(const Duration(seconds: 3));
  await ui.shot('deposit-form');
  await ui.tap(_button('Deposit'));
  await ui.waitUntil(() => find.text('Deposit to Thunder').evaluate().isEmpty, 'the deposit sheet to close');
  ui.step('bmm');
  await ui.tapText('BMM');
  await ui.waitFor(find.text('Start auto-bidding').hitTestable(), timeout: const Duration(minutes: 2));
  await ui.shot('bmm');
  await ui.tap(find.text('Start auto-bidding'));
  await ui.waitFor(find.text('Stop auto-bidding'), reason: 'auto-bidding runs');
  final startHeight = await thunder.blockCount();
  await mineUntil(() async => await thunder.blockCount() >= startHeight + 2, 'two BMM blocks');
  await ui.shot('bmm-blocks');

  await mineUntil(() async => await thunder.availableSats() > 0, 'the deposit on Thunder');
  final deposited = await thunder.availableSats();
  expect(deposited, 50000000, reason: 'the deposit credits 0.5 BTC on Thunder');
  debugPrint('PROOF deposit on thunder sats=$deposited thunder_height=${await thunder.blockCount()}');
  await ui.tap(find.text('Overview'));
  await ui.settle(const Duration(seconds: 5));
  await ui.shot('deposit-on-thunder');

  ui.step('thunder-send');
  final second = await thunder.newAddress();
  await ui.enter(find.text('Enter a Thunder address'), second);
  await ui.enter(_inCard('Send on Sidechain', find.text('0.00')), '0.1');
  await ui.shot('thunder-send-form');
  await ui.tap(_inCard('Send on Sidechain', _button('Send')));
  await ui.waitFor(find.textContaining('You sent 0.1 BTC'), reason: 'the Thunder payment');
  await ui.shot('thunder-send-done');
  debugPrint('PROOF thunder send ${ui.textMatching(RegExp(r'^TXID: '))}');
  await ui.tapText('Close');
  final sentHeight = await thunder.blockCount();
  await mineUntil(() async => await thunder.blockCount() > sentHeight, 'a Thunder block with the payment');
  final mempool = (await thunder.call('list_mempool')) as List;
  expect(mempool, isEmpty, reason: 'the Thunder payment is in a block');
  await ui.shot('thunder-send-confirmed');
  debugPrint('PROOF thunder send in block thunder_height=${await thunder.blockCount()}');
}
