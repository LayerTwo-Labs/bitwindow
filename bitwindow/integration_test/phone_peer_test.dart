// Runs on two phones that share one regtest stack, in three steps:
//   PHONE_QA_ROLE=first  (iOS, fresh install): receive, note, UTXO label, check, encrypt.
//   PHONE_QA_ROLE=second (Android, fresh install): receive, send to iOS, cash the iOS check.
//   PHONE_QA_ROLE=back   (iOS, same install): unlock, see the Android payment, send to Android.
// See phone_regtest/README.md.
import 'package:bitwindow/main.dart' as app;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:bitwindow/providers/transactions_provider.dart';

import 'phone_regtest/regtest.dart';
import 'phone_regtest/ui.dart';

const _role = String.fromEnvironment('PHONE_QA_ROLE');
const _password = 'phone-qa-pass';
final _bcrt = RegExp(r'^bcrt1[0-9a-z]{20,}$');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('two phones pay each other on regtest ($_role)', (tester) async {
    final regtest = RegtestControl.fromDefine();
    final ui = PhoneUi(tester, binding);
    final testHandler = FlutterError.onError;
    final testErrorWidget = ErrorWidget.builder;
    try {
      app.main([]);
      switch (_role) {
        case 'first':
          await _first(tester, ui, regtest);
        case 'second':
          await _second(tester, ui, regtest);
        case 'back':
          await _back(tester, ui, regtest);
        default:
          throw StateError('give --dart-define=PHONE_QA_ROLE=first, second or back');
      }
    } catch (_) {
      await ui.shot('failure');
      rethrow;
    } finally {
      FlutterError.onError = testHandler;
      ErrorWidget.builder = testErrorWidget;
    }
    expect(ui.layoutErrors, isEmpty, reason: 'layout overflows on a phone');
  }, timeout: const Timeout(Duration(minutes: 30)));
}

Future<void> _newWallet(PhoneUi ui) async {
  await ui.waitFor(find.text('No wallet'), timeout: const Duration(minutes: 3));
  await ui.waitFor(find.text('All binaries connected'), timeout: const Duration(minutes: 4));
  ui.watchLayoutErrors();
  await ui.tap(ui.topmost(find.text('No wallet')));
  await ui.tapText('Generate wallet');
  await ui.waitFor(find.text('Continue'));
  await ui.settle(const Duration(seconds: 3));
  await ui.tapText('Continue');
  await ui.tapText('Skip and create wallet');
  await ui.tapText('Create without backup');
  await ui.waitFor(find.text('wallet1'), timeout: const Duration(minutes: 2));
}

Future<String> _receiveAddress(PhoneUi ui) async {
  await ui.navigate('Wallet');
  await ui.tapText('Receive');
  await ui.waitUntil(() => ui.fieldText(_bcrt).isNotEmpty, 'a receive address');
  return ui.fieldText(_bcrt);
}

Future<void> _fund(PhoneUi ui, RegtestControl regtest, String address) async {
  await regtest.send(address, '2');
  await regtest.mine(1);
  await ui.tapText('Overview');
  await ui.waitFor(find.text('Confirmed'), timeout: const Duration(minutes: 3), reason: 'the funding');
}

Future<void> _send(PhoneUi ui, RegtestControl regtest, String to, String amount) async {
  await ui.tapText('Send');
  await ui.tap(ui.topmost(find.text('Create Transaction')));
  await ui.enter(find.textContaining('Enter a single L1'), to);
  await ui.enter(find.text('0.00'), amount);
  await ui.settle(const Duration(seconds: 3));
  await ui.tap(find.text('Create Transaction').last);
  await ui.waitFor(find.text('Broadcast'));
  await ui.settle(const Duration(seconds: 3));
  final before = (await regtest.mempool()).length;
  await ui.tapText('Broadcast');
  await ui.waitUntilAsync(() async => (await regtest.mempool()).length > before, 'the send in the mempool');
}

Future<void> _first(WidgetTester tester, PhoneUi ui, RegtestControl regtest) async {
  await _newWallet(ui);
  ui.step('receive');
  final address = await _receiveAddress(ui);
  await regtest.put('ios-address', address);
  await _fund(ui, regtest, address);

  ui.step('note');
  await ui.longPressUntil(find.text('Confirmed'), find.text('Add Note'));
  await ui.tapText('Add Note');
  await ui.waitFor(find.text('Save changes'));
  await tester.enterText(
    find.descendant(of: find.byType(SailCardEditValues), matching: find.byType(EditableText)),
    'rent for October',
  );
  await ui.settle();
  await ui.tapText('Save changes');
  await ui.settle(const Duration(seconds: 2));
  final note = GetIt.I<TransactionProvider>().walletTransactions.map((t) => t.note);
  expect(note, contains('rent for October'));
  await ui.tapText('UTXOs');
  await ui.tapText('Overview');
  await ui.settle();
  // The phone history has no note column, so the row menu shows the saved note as Update Note.
  await ui.longPressUntil(find.text('Confirmed'), find.text('Update Note'));
  await ui.shot('note');
  await ui.tapText('Update Note');
  await ui.waitFor(find.text('rent for October'), reason: 'the saved note');
  await tester.tapAt(const Offset(195, 100));
  await ui.settle();

  ui.step('utxo-label');
  await ui.tapText('UTXOs');
  await ui.settle(const Duration(seconds: 2));
  await ui.longPressUntil(find.textContaining('2.0000'), find.text('Edit Label'));
  await ui.tapText('Edit Label');
  await ui.settle();
  await ui.shot('utxo-label');
  await ui.enter(find.text('e.g., Cold storage, Exchange deposit'), 'savings');
  await ui.tap(find.text('Save').hitTestable().last);
  await ui.waitFor(find.text('savings'), reason: 'the UTXO label');
  await ui.shot('utxo-labelled');

  ui.step('check');
  await ui.tapText('Checks');
  await ui.tap(find.textContaining(RegExp(r'^Create (New|Your First) Check$')));
  await ui.waitFor(find.text('How much should the check be for?'));
  await ui.enter(find.text('0.00000000'), '0.3');
  await ui.tapText('Create');
  await ui.waitFor(find.text('Fund with Wallet'), timeout: const Duration(minutes: 1));
  await ui.tapText('Fund with Wallet');
  await ui.waitFor(find.text('View Details'), timeout: const Duration(minutes: 2), reason: 'the funded check');
  await ui.shot('check-list');
  await ui.tapText('View Details');
  await ui.waitFor(find.text('Private Key (WIF)'), timeout: const Duration(minutes: 2), reason: 'the check key');
  await ui.shot('check-funded');
  await regtest.put('check-wif', ui.textMatching(RegExp(r'^[cK-L5][1-9A-HJ-NP-Za-km-z]{50,51}$')));
  await regtest.mine(1);
  await tester.binding.handlePopRoute();
  await ui.settle();

  ui.step('encrypt');
  await ui.navigate('Encrypt Wallet');
  await ui.enter(find.text('Enter a password'), _password);
  await ui.enter(find.text('Confirm password'), _password);
  await ui.shot('encrypt');
  await ui.tap(find.widgetWithText(SailButton, 'Encrypt Wallet'));
  await ui.waitUntil(() => find.text('Confirm password').evaluate().isEmpty, 'the encrypt sheet to close');
}

Future<void> _second(WidgetTester tester, PhoneUi ui, RegtestControl regtest) async {
  await _newWallet(ui);
  ui.step('receive');
  final address = await _receiveAddress(ui);
  await regtest.put('android-address', address);
  await _fund(ui, regtest, address);

  ui.step('send-to-ios');
  await _send(ui, regtest, await regtest.take('ios-address'), '0.25');
  await ui.shot('sent-to-ios');
  await regtest.mine(1);

  ui.step('cash-check');
  await ui.tapText('Checks');
  await ui.tap(find.textContaining(RegExp(r'^Cash (a )?Check$')));
  await ui.enter(find.text('Private key (WIF format)'), await regtest.take('check-wif'));
  await ui.shot('cash-check');
  await ui.tap(find.widgetWithText(SailButton, 'Cash Check'));
  await ui.waitUntilAsync(() async => (await regtest.mempool()).isNotEmpty, 'the sweep in the mempool');
  await ui.settle(const Duration(seconds: 2));
  await ui.shot('check-cashed');
  await regtest.mine(1);
  await ui.tapText('Done');
  // 2 BTC in, 0.25 out plus a fee, and the 0.3 check swept in.
  await ui.waitUntil(
    () => find.textContaining('2.0499').evaluate().isNotEmpty,
    'the swept check in the balance',
    timeout: const Duration(minutes: 3),
  );
  await ui.shot('check-in-history');
}

Future<void> _back(WidgetTester tester, PhoneUi ui, RegtestControl regtest) async {
  ui.step('unlock');
  await ui.waitFor(find.text('Enter your password'), timeout: const Duration(minutes: 3), reason: 'the lock page');
  ui.watchLayoutErrors();
  await ui.shot('locked');
  await ui.enter(find.text('Enter your password'), _password);
  // The field submits on its own once the password is in.
  if (find.text('Decrypt Wallet').hitTestable().evaluate().isNotEmpty) {
    await ui.tap(find.text('Decrypt Wallet'));
  }
  await ui.waitFor(find.text('wallet1'), timeout: const Duration(minutes: 2));

  ui.step('received-from-android');
  await ui.navigate('Wallet');
  await ui.waitUntil(
    () => find.textContaining('+0.2500').evaluate().isNotEmpty,
    'the payment from Android',
    timeout: const Duration(minutes: 3),
  );
  await ui.shot('received-from-android');

  ui.step('send-to-android');
  await _send(ui, regtest, await regtest.take('android-address'), '0.1');
  await ui.shot('sent-to-android');
  await regtest.mine(1);
}
