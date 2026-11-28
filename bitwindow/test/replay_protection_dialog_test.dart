import 'package:bitwindow/widgets/replay_protection_dialog.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/gen/wallet/v1/wallet.pb.dart';

import 'test_utils.dart';

UnspentOutput coin(String address, int sats) =>
    UnspentOutput(output: '$address:0', address: address, valueSats: Int64(sats));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(loadBundledFonts);

  setUp(() async {
    await GetIt.I.reset();
    await registerTestDependencies();
  });

  tearDown(() async {
    SailStyleValues.phoneLayoutOverride = null;
    await GetIt.I.reset();
  });

  Finder button(String label) => find.byWidgetPredicate((w) => w is SailButton && w.label == label);

  Future<ReplayChoice?> openDialog(WidgetTester tester, List<UnspentOutput> coins, {bool coinsKnown = true}) async {
    ReplayChoice? choice;
    await tester.pumpSailPage(
      Builder(
        builder: (context) => TextButton(
          onPressed: () async => choice = await askReplayProtection(context, coins: coins, coinsKnown: coinsKnown),
          child: const Text('open'),
        ),
      ),
    );
    if (SailStyleValues.phoneLayoutOverride == true) {
      await tester.usePhoneSize();
    }
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return choice;
  }

  testWidgets('the dialog names every coin that exists on both chains', (tester) async {
    await openDialog(tester, [
      coin('tb1qm4v000000000000000008xr2', 30000000),
      coin('tb1qk9d000000000000000003ptu', 10000000),
    ]);

    expect(find.text('These coins exist on both chains'), findsOneWidget);
    expect(find.text('tb1qm4…8xr2'), findsOneWidget);
    expect(find.text('tb1qk9…3ptu'), findsOneWidget);
  });

  testWidgets('one coin reads in the singular', (tester) async {
    await openDialog(tester, [coin('tb1qm4v000000000000000008xr2', 30000000)]);

    expect(find.text('This coin exists on both chains'), findsOneWidget);
  });

  testWidgets('the protected send is the one button; Send without protection is in "…"', (tester) async {
    await openDialog(tester, [coin('tb1qm4v000000000000000008xr2', 30000000)]);

    expect(find.byType(SailButton), findsOneWidget);
    expect(button('Enable replay protection'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
    expect(find.text('Send without protection'), findsNothing);

    await tester.tap(find.byType(SailRowMenuButton));
    await tester.pumpAndSettle();
    expect(find.text('Send without protection'), findsOneWidget);
  });

  testWidgets('an unread wallet raises the prompt without a coin list', (tester) async {
    await openDialog(tester, [], coinsKnown: false);

    expect(find.text('These coins exist on both chains'), findsOneWidget);
    expect(find.text('Coins on both chains'), findsNothing);
    expect(find.text('Enable replay protection'), findsWidgets);
  });

  testWidgets('the dialog hugs its content instead of filling the screen', (tester) async {
    await openDialog(tester, [coin('tb1qm4v000000000000000008xr2', 30000000)]);

    final card = tester.getSize(find.byType(SailCard).first);
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(card.height, lessThan(screen.height * 0.7));
  });

  Future<ReplayChoice?> answer(WidgetTester tester, Future<void> Function() act) async {
    ReplayChoice? choice;
    await tester.pumpSailPage(
      Builder(
        builder: (context) => TextButton(
          onPressed: () async =>
              choice = await askReplayProtection(context, coins: [coin('tb1qm4v000000000000000008xr2', 30000000)]),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await act();
    await tester.pumpAndSettle();
    return choice;
  }

  testWidgets('Enable replay protection sends protected', (tester) async {
    final choice = await answer(tester, () => tester.tap(button('Enable replay protection')));
    expect(choice, ReplayChoice.sendProtected);
  });

  testWidgets('Send without protection in "…" sends plain', (tester) async {
    final choice = await answer(tester, () async {
      await tester.tap(find.byType(SailRowMenuButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send without protection'));
    });
    expect(choice, ReplayChoice.sendPlain);
  });

  testWidgets('the × cancels the send', (tester) async {
    final choice = await answer(
      tester,
      () => tester.tap(find.byWidgetPredicate((w) => w is SailIconBoxButton && w.icon == SailSVGAsset.x)),
    );
    expect(choice, ReplayChoice.cancel);
  });
}
