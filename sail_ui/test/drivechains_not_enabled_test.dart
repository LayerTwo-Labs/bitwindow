import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/pages/network_switch_page.dart';
import 'package:sail_ui/sail_ui.dart';

class _Conf extends ChangeNotifier implements BitcoinConfProvider {
  @override
  BitcoinNetwork network = BitcoinNetwork.BITCOIN_NETWORK_MAINNET;

  @override
  List<NetworkOption> get drivechainNetworkOptions => [NetworkOption(id: 'signet', displayName: 'Signet')];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() => GetIt.I.registerSingleton<BitcoinConfProvider>(_Conf()));
  tearDown(() => GetIt.I.reset());

  testWidgets('on a desktop Drivechains Not Enabled is one 560 px card with a full-width Switch Network', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => SailTheme(
          data: SailThemeData.lightTheme(
            SailColorScheme.orange,
            false,
            SailFontValues.inter,
            SailThemeStyle.bitwindowV2,
          ),
          child: child ?? const SizedBox(),
        ),
        home: const NetworkSwitchPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final card = find.byKey(const Key('drivechains-not-enabled-card'));
    expect(tester.getSize(card).width, 560);
    for (final text in ['Drivechains Not Enabled', 'Select a network with drivechain support:']) {
      expect(find.descendant(of: card, matching: find.text(text)), findsOneWidget);
    }
    final button = tester.getRect(find.widgetWithText(SailButton, 'Switch Network'));
    expect(button.width, closeTo(560 - 2 * SailStyleValues.padding16, 2));
    expect(find.byType(AppBar), findsNothing);
  });
}
