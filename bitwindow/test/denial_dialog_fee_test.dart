import 'package:bitwindow/pages/wallet/denial_dialog.dart';
import 'package:bitwindow/providers/transactions_provider.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/gen/wallet/v1/wallet.pb.dart';

import 'mocks/api_mock.dart';
import 'test_utils.dart';

class _FakeTransactionProvider extends ChangeNotifier implements TransactionProvider {
  @override
  Future<void> fetch() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeWallet implements OrchestratorWalletRPC {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeOrchestrator implements OrchestratorRPC {
  @override
  final OrchestratorWalletRPC wallet = _FakeWallet();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _RecordingBitwindowd extends MockBitwindowdAPI {
  final List<({String txid, int hops, int delay})> denials = [];

  @override
  Future<void> createDenial({
    required String txid,
    required int vout,
    required int numHops,
    required int delaySeconds,
    List<int>? targetUtxoSizes,
  }) async {
    denials.add((txid: txid, hops: numHops, delay: delaySeconds));
  }
}

class _RecordingAPI extends MockAPI {
  _RecordingAPI() : super(binaryType: BinaryType.BINARY_TYPE_BITWINDOWD);

  final recorder = _RecordingBitwindowd();

  @override
  BitwindowAPI get bitwindowd => recorder;
}

Finder _fields() => find.descendant(of: find.byType(DenialDialog), matching: find.byType(EditableText));

void main() {
  late _RecordingAPI api;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadBundledFonts();
  });

  setUp(() async {
    await GetIt.I.reset();
    api = _RecordingAPI();
    GetIt.I.registerSingleton<BitwindowRPC>(api);
    GetIt.I.registerSingleton<OrchestratorRPC>(_FakeOrchestrator());
    GetIt.I.registerSingleton<TransactionProvider>(_FakeTransactionProvider());
  });

  tearDown(() => GetIt.I.reset());

  Future<void> pumpDialog(WidgetTester tester, {int? valueSats, List<UnspentOutput>? utxos}) async {
    // The test font draws the delay row wider than the app font; this file tests the fee and the errors only.
    final onError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (!details.exceptionAsString().contains('overflowed')) {
        onError?.call(details);
      }
    };
    addTearDown(() => FlutterError.onError = onError);
    await tester.pumpSailPage(
      SizedBox(
        width: 900,
        height: 700,
        child: utxos == null ? DenialDialog(output: '${'a' * 64}:0', valueSats: valueSats) : DenialDialog(utxos: utxos),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> start(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  String sats(int value) => GetIt.I<FormatterProvider>().formatSats(value);

  test('the smallest UTXO for 3 hops matches the server', () {
    expect(DenialDialog.minValueSats(3), 32184);
    expect(DenialDialog.maxHops(25000), 2);
    expect(DenialDialog.maxHops(9000), 0);
  });

  testWidgets('the dialog shows the fee of the hops', (tester) async {
    await pumpDialog(tester, valueSats: 100000000);

    expect(find.text('Fee: ${sats(10000)} per hop, ${sats(30000)} in total.'), findsOneWidget);

    await tester.enterText(_fields().at(3), '6');
    await tester.pumpAndSettle();

    expect(find.text('Fee: ${sats(10000)} per hop, ${sats(60000)} in total.'), findsOneWidget);
  });

  testWidgets('zero hops show a plain error and start no denial', (tester) async {
    await pumpDialog(tester, valueSats: 100000000);
    await tester.enterText(_fields().at(3), '0');
    await tester.pumpAndSettle();

    await start(tester, 'Start');

    expect(find.text('Enter 1 hop or more.'), findsOneWidget);
    expect(api.recorder.denials, isEmpty);
  });

  testWidgets('a zero delay shows a plain error and starts no denial', (tester) async {
    await pumpDialog(tester, valueSats: 100000000);
    await tester.enterText(_fields().at(0), '0');
    await tester.pumpAndSettle();

    await start(tester, 'Start');

    expect(find.text('Enter a delay of 1 minute or more.'), findsOneWidget);
    expect(api.recorder.denials, isEmpty);
  });

  testWidgets('a UTXO too small for the hop fees starts no denial', (tester) async {
    await pumpDialog(tester, valueSats: 25000);

    await start(tester, 'Start');

    expect(find.text('This UTXO can pay for 2 hops at most.'), findsOneWidget);
    expect(api.recorder.denials, isEmpty);

    await tester.enterText(_fields().at(3), '2');
    await tester.pumpAndSettle();
    await start(tester, 'Start');

    expect(api.recorder.denials.single.hops, 2);
  });

  testWidgets('a UTXO below one hop fee says so', (tester) async {
    await pumpDialog(tester, valueSats: 9000);

    await start(tester, 'Start');

    expect(find.text('This UTXO is too small to pay for a hop.'), findsOneWidget);
    expect(api.recorder.denials, isEmpty);
  });

  testWidgets('Deny All starts only the UTXOs that pay for the hops', (tester) async {
    final large = UnspentOutput(output: '${'b' * 64}:0', valueSats: Int64(100000000));
    final small = UnspentOutput(output: '${'c' * 64}:1', valueSats: Int64(25000));
    await pumpDialog(tester, utxos: [large, small]);

    expect(
      find.text('Starting deniability on 1 of 2 UTXOs. The others are too small for 3 hops.'),
      findsOneWidget,
    );
    expect(find.text('Fee: ${sats(10000)} per hop, ${sats(30000)} in total.'), findsOneWidget);

    await start(tester, 'Deny All');

    expect(api.recorder.denials.map((d) => d.txid), ['b' * 64]);
  });

  testWidgets('Deny All with no UTXO that pays shows a plain error', (tester) async {
    final small = UnspentOutput(output: '${'c' * 64}:1', valueSats: Int64(25000));
    await pumpDialog(tester, utxos: [small]);

    await start(tester, 'Deny All');

    expect(find.text('No UTXO can pay for 3 hops.'), findsOneWidget);
    expect(api.recorder.denials, isEmpty);
  });
}
