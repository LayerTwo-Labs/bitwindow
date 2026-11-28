import 'dart:io';

import 'package:bitwindow/pages/sidechains_page.dart' show SidechainIconTile;
import 'package:bitwindow/widgets/starters_tab.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:sail_ui/sail_ui.dart';

import 'test_utils.dart';

const _master = 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
const _thunder = 'zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo wrong';

class _Conf extends ChangeNotifier implements BitcoinConfProvider {
  @override
  bool get networkSupportsSidechains => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _WalletReader extends ChangeNotifier implements WalletReaderProvider {
  @override
  String? get activeWalletId => null;

  @override
  WalletData? get primaryWallet => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _WalletWriter extends ChangeNotifier implements WalletWriterProvider {
  @override
  Future<Map<String, dynamic>?> loadMasterStarter() async => {'name': 'Master', 'mnemonic': _master};

  @override
  Future<String?> getL1Starter() async => null;

  @override
  Future<String?> getSidechainStarter(int sidechainSlot) async => sidechainSlot == Thunder().slot ? _thunder : null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() async {
    await GetIt.I.reset();
    GetIt.I.registerSingleton<Logger>(Logger(level: Level.off));
    GetIt.I.registerSingleton<BitcoinConfProvider>(_Conf());
    GetIt.I.registerSingleton<WalletReaderProvider>(_WalletReader());
    GetIt.I.registerSingleton<WalletWriterProvider>(_WalletWriter());
    GetIt.I.registerSingleton<BinaryProvider>(
      BinaryProvider.test(appDir: Directory.systemTemp, binaries: [BitcoinCore(), Thunder(), BitNames()]),
    );
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  Future<void> pumpStarters(WidgetTester tester) async {
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await tester.pumpSailPage(const StartersTab());
    await tester.binding.setSurfaceSize(const Size(1440, 1024));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pump(const Duration(seconds: 1));
  }

  double top(WidgetTester tester, String text) => tester.getTopLeft(find.text(text)).dy;

  testWidgets('the table groups the starters by layer, and only a starter with a mnemonic has a "…"', (tester) async {
    await pumpStarters(tester);

    expect(top(tester, 'Master'), lessThan(top(tester, 'Layer 1')));
    expect(top(tester, 'Layer 1'), lessThan(top(tester, 'Bitcoin Core')));
    expect(top(tester, 'Bitcoin Core'), lessThan(top(tester, 'Layer 2')));
    expect(top(tester, 'Layer 2'), lessThan(top(tester, 'Thunder')));
    expect(find.text('No starter generated'), findsNWidgets(2), reason: 'Bitcoin Core and Bitnames');
    expect(find.byType(SailRowMenuButton), findsNWidgets(2), reason: 'Master and Thunder');
    expect(find.byType(SailSidePanel), findsNothing);
  });

  testWidgets('a row click opens the panel with Reveal, and × closes it', (tester) async {
    await pumpStarters(tester);

    await tester.tap(find.text('Thunder'));
    await tester.pump(const Duration(seconds: 1));

    final panel = find.byType(StarterPanel);
    expect(panel, findsOneWidget);
    expect(tester.getSize(panel).width, SailSidePanel.width);
    expect(find.descendant(of: panel, matching: find.byType(SidechainIconTile)), findsOneWidget);
    expect(find.descendant(of: panel, matching: find.text('Layer 2')), findsOneWidget);
    expect(find.descendant(of: panel, matching: find.widgetWithText(SailButton, 'Reveal')), findsOneWidget);
    expect(find.text(_thunder), findsNothing);

    await tester.tap(find.byWidgetPredicate((w) => w is SailIconBoxButton && w.icon == SailSVGAsset.x));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(StarterPanel), findsNothing);
  });

  testWidgets('a click on a starter with no mnemonic opens no panel', (tester) async {
    await pumpStarters(tester);

    await tester.tap(find.text('Bitnames'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(StarterPanel), findsNothing);
  });

  testWidgets('the row menu offers Reveal and Copy', (tester) async {
    await pumpStarters(tester);

    await tester.tap(find.byType(SailRowMenuButton).first);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Reveal'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
  });
}
