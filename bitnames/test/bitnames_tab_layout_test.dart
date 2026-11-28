import 'dart:io';
import 'dart:ui' as ui;

import 'package:bitnames/pages/tabs/reserve_register_page.dart';
import 'package:bitnames/providers/bitnames_provider.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/mocks/mocks.dart';

import 'mocks/rpc_mock_sidechain.dart';
import 'test_utils.dart';

final _bo = BitnameEntry(
  hash: '4c1e9f30ab${'7' * 54}',
  plaintextName: 'bo',
  details: BitnameDetails(seqId: '7', commitment: 'c' * 64, socketAddrV4: '203.0.113.7:6002', paymailFeeSats: 1000),
);
final _satoshi = BitnameEntry(
  hash: 'b81d0e6c42${'1' * 54}',
  plaintextName: 'satoshi',
  details: BitnameDetails(seqId: '12'),
);

class _RPC extends MockBitnamesRPC {
  @override
  Future<List<BitnameEntry>> listBitNames() async => [_bo, _satoshi];

  @override
  Future<List<SidechainUTXO>> listUTXOs() async => [];
}

const _screenKey = ValueKey('bitnames-tab-screen');

const _screenDir = String.fromEnvironment('BITNAMES_SCREEN_DIR');

void main() {
  setUpAll(() async {
    if (_screenDir.isEmpty) {
      return;
    }
    for (final (family, file) in [(SailFonts.inter, 'Inter'), (SailFonts.mono, 'IBMPlexMono')]) {
      final loader = FontLoader(family);
      for (final weight in ['Regular', 'Medium', 'Bold']) {
        loader.addFont(rootBundle.load('packages/sail_ui/assets/fonts/$file-$weight.ttf'));
      }
      await loader.load();
    }
  });

  late BitnamesProvider provider;
  late SidechainBalanceProvider balances;

  setUp(() async {
    await GetIt.I.reset();
    await registerTestDependencies();
    final sidechain = MockSidechainRPC();
    GetIt.I.registerSingleton<BitnamesRPC>(_RPC());
    GetIt.I.registerSingleton<SidechainRPC>(sidechain);
    GetIt.I.registerSingleton<NotificationProvider>(NotificationProvider());
    balances = SidechainBalanceProvider(sidechain: sidechain);
    GetIt.I.registerSingleton<SidechainBalanceProvider>(balances);
    provider = BitnamesProvider();
    GetIt.I.registerSingleton<BitnamesProvider>(provider);
  });

  tearDown(() async {
    provider.dispose();
    balances.dispose();
    await GetIt.I.reset();
  });

  Future<void> pumpTab(WidgetTester tester) async {
    await tester.pumpSailPage(const RepaintBoundary(key: _screenKey, child: BitnamesTabPage()));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(provider.entries, hasLength(2));
  }

  Finder panel(String title) => find.byWidgetPredicate((w) => w is SailSidePanel && w.title == title);

  testWidgets('the Register form opens in a 380 px side panel beside both tables', (tester) async {
    await pumpTab(tester);

    expect(panel('Register'), findsOneWidget);
    expect(tester.getSize(panel('Register')).width, SailSidePanel.width);
    expect(find.text('Your Bitnames'), findsOneWidget);
    expect(find.text('All Bitnames'), findsOneWidget);
    expect(tester.getTopLeft(panel('Register')).dx, greaterThan(tester.getTopRight(find.text('All Bitnames')).dx));
    expect(
      tester.getTopLeft(find.text('Plaintext Name').first).dx,
      lessThan(tester.getTopLeft(find.text('Hash').first).dx),
    );
    await _capture(tester, 'register');
  });

  testWidgets('× closes the panel and Register New Bitname opens it again', (tester) async {
    await pumpTab(tester);

    await tester.tap(find.byType(SailIconBoxButton));
    await tester.pump();
    expect(find.byType(SailSidePanel), findsNothing);

    await tester.tap(find.text('Register New Bitname'));
    await tester.pump();
    expect(panel('Register'), findsOneWidget);
  });

  testWidgets('the Reserve segment swaps the form in the panel', (tester) async {
    await pumpTab(tester);

    await tester.tap(find.text('Reserve'));
    await tester.pump();

    expect(panel('Reserve'), findsOneWidget);
    expect(find.text('Enter name to reserve'), findsOneWidget);
    expect(find.text('Enter name to register'), findsNothing);
  });

  testWidgets('a reserve with no name shows the error under the field', (tester) async {
    await pumpTab(tester);
    await tester.tap(find.text('Reserve'));
    await tester.pump();

    await tester.tap(find.byWidgetPredicate((w) => w is SailButton && w.label == 'Reserve'));
    await tester.pump();

    final field = find.byWidgetPredicate((w) => w is SailTextField && w.hintText == 'Enter name to reserve');
    expect(tester.widget<SailTextField>(field).errorText, 'Name cannot be empty');
    expect(find.text('Name cannot be empty'), findsOneWidget);
  });

  testWidgets('a bad postage shows the error under the postage field', (tester) async {
    await pumpTab(tester);
    final name = find.byWidgetPredicate((w) => w is SailTextField && w.hintText == 'Enter name to register');
    await tester.enterText(find.descendant(of: name, matching: find.byType(EditableText)), 'bo');
    final postage = find.byWidgetPredicate((w) => w is SailTextField && w.hintText == 'Minimum you accept per message');
    await tester.enterText(find.descendant(of: postage, matching: find.byType(EditableText)), '-5');

    final register = find.byWidgetPredicate((w) => w is SailButton && w.label == 'Register');
    await tester.ensureVisible(register);
    await tester.tap(register);
    await tester.pump();

    expect(
      tester.widget<SailTextField>(postage).errorText,
      'Paymail fee must be a whole number of sats, and zero or more',
    );
  });

  testWidgets('a row click shows the bitname in the details panel', (tester) async {
    await pumpTab(tester);

    await tester.tap(find.text('satoshi').last);
    await tester.pump();

    expect(panel('Bitname Details'), findsOneWidget);
    expect(panel('Register'), findsNothing);
    expect(find.descendant(of: panel('Bitname Details'), matching: find.text(_satoshi.hash)), findsWidgets);
  });

  testWidgets('the details panel shows the data the address serves', (tester) async {
    await pumpTab(tester);

    await tester.tap(find.text('bo').last);
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();

    expect(find.text('Data from address'), findsOneWidget);
    await _capture(tester, 'details');
  });
  testWidgets('a phone stacks the forms and shows no side panel', (tester) async {
    SailStyleValues.phoneLayoutOverride = true;
    addTearDown(() => SailStyleValues.phoneLayoutOverride = null);
    await pumpTab(tester);

    expect(find.byType(SailSidePanel), findsNothing);
    expect(find.text('Enter name to reserve'), findsOneWidget);
    expect(find.text('Register New Bitname'), findsNothing);
  });
}

Future<void> _capture(WidgetTester tester, String name) async {
  const directory = _screenDir;
  if (directory.isEmpty) {
    return;
  }
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_screenKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      await Directory(directory).create(recursive: true);
      await File('$directory/$name.png').writeAsBytes(bytes.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
