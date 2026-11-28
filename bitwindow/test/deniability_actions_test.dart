import 'package:bitwindow/pages/wallet/denability_page.dart';
import 'package:bitwindow/providers/transactions_provider.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/gen/wallet/v1/wallet.pb.dart';

import 'test_utils.dart';

class _FakeTransactionProvider extends ChangeNotifier implements TransactionProvider {
  @override
  List<UnspentOutput> utxos = [];

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadBundledFonts();
  });

  setUp(() async {
    await GetIt.I.reset();
    await registerTestDependencies();
    GetIt.I.registerSingleton<TransactionProvider>(_FakeTransactionProvider());
  });

  tearDown(() => GetIt.I.reset());

  test('Deny All skips coins with a paused denial', () {
    final paused = UnspentOutput(
      output: '${'a' * 64}:0',
      denialInfo: DenialInfo(
        id: Int64(1),
        numHops: 3,
        pausedAt: Timestamp.fromDateTime(DateTime.utc(2026)),
      ),
    );
    final free = UnspentOutput(output: '${'b' * 64}:0');
    final cancelled = UnspentOutput(
      output: '${'c' * 64}:0',
      denialInfo: paused.denialInfo.deepCopy()..cancelTime = Timestamp.fromDateTime(DateTime.utc(2026)),
    );
    final change = UnspentOutput(
      output: '${'d' * 64}:0',
      denialInfo: paused.denialInfo.deepCopy()..isChange = true,
    );
    final scheduled = UnspentOutput(
      output: '${'e' * 64}:0',
      denialInfo: DenialInfo(nextExecutionTime: Timestamp.fromDateTime(DateTime.utc(2027))),
    );
    final completed = UnspentOutput(
      output: '${'f' * 64}:0',
      denialInfo: DenialInfo(numHops: 3, hopsCompleted: 3),
    );
    final provider = GetIt.I<TransactionProvider>() as _FakeTransactionProvider;
    provider.utxos = [paused, free, cancelled, change, scheduled, completed];
    final model = DeniabilityViewModel();
    addTearDown(model.dispose);

    expect(model.utxosWithoutDenial, [free, cancelled, change, completed]);
  });

  Future<List<String>> pumpTable(WidgetTester tester) async {
    final calls = <String>[];
    final theme = SailThemeData.lightTheme(
      SailColorScheme.orange,
      false,
      SailFontValues.inter,
      SailThemeStyle.bitwindowV2,
    );
    await tester.pumpSailPage(
      SailTheme(
        data: theme,
        child: SizedBox(
          width: 1100,
          height: 600,
          child: DeniabilityTable(
            newWindowButton: null,
            error: null,
            utxos: [
              UnspentOutput(
                output: '${'a' * 64}:0',
                valueSats: Int64(1000),
                denialInfo: DenialInfo(
                  id: Int64(1),
                  numHops: 3,
                  nextExecutionTime: Timestamp.fromDateTime(DateTime.utc(2030)),
                ),
              ),
              UnspentOutput(output: '${'b' * 64}:0', valueSats: Int64(2000)),
            ],
            model: DeniabilityViewModel(),
            onDeny: (output, _) => calls.add('deny $output'),
            onCancel: (id) => calls.add('cancel $id'),
            onPause: (id) => calls.add('pause $id'),
            onResume: (id) => calls.add('resume $id'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return calls;
  }

  Future<void> openMenu(WidgetTester tester, int row) async {
    await tester.tap(find.byType(SailRowMenuButton).at(row));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
  }

  testWidgets('the rows hold no buttons; each row has one "…"', (tester) async {
    await pumpTable(tester);

    expect(find.byType(SailButton), findsNothing);
    expect(find.byType(SailRowMenuButton), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the "…" of a running denial holds Pause, Cancel and Show Details', (tester) async {
    final calls = await pumpTable(tester);

    await openMenu(tester, 0);
    expect(find.text('Pause'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Show Details'), findsOneWidget);
    expect(find.text('Deny'), findsNothing);

    await tester.tap(find.text('Pause'));
    await tester.pumpAndSettle();
    expect(calls, ['pause 1']);
  });

  testWidgets('the "…" of a UTXO with no denial holds Deny and Show Details', (tester) async {
    final calls = await pumpTable(tester);

    await openMenu(tester, 1);
    expect(find.text('Deny'), findsOneWidget);
    expect(find.text('Show Details'), findsOneWidget);
    expect(find.text('Pause'), findsNothing);
    expect(find.text('Cancel'), findsNothing);

    await tester.tap(find.text('Deny'));
    await tester.pumpAndSettle();
    expect(calls, ['deny ${'b' * 64}:0']);
  });

  testWidgets('the UTXO panel has the first row action as its one button and Cancel in its "…"', (tester) async {
    final calls = <String>[];
    final theme = SailThemeData.lightTheme(
      SailColorScheme.orange,
      false,
      SailFontValues.inter,
      SailThemeStyle.bitwindowV2,
    );
    final utxo = UnspentOutput(
      output: '${'a' * 64}:0',
      valueSats: Int64(1000),
      denialInfo: DenialInfo(
        id: Int64(4),
        numHops: 3,
        pausedAt: Timestamp.fromDateTime(DateTime.utc(2026)),
        nextExecutionTime: Timestamp.fromDateTime(DateTime.utc(2030)),
      ),
    );
    await tester.pumpSailPage(
      SailTheme(
        data: theme,
        child: Align(
          alignment: Alignment.topRight,
          child: SizedBox(
            height: 700,
            child: DenialUtxoPanel(
              utxo: utxo,
              onClose: () async {},
              onDeny: (output, _) => calls.add('deny'),
              onCancel: (id) => calls.add('cancel $id'),
              onPause: (id) => calls.add('pause $id'),
              onResume: (id) => calls.add('resume $id'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(SailButton, 'Resume'), findsOneWidget);
    expect(find.widgetWithText(SailStatusPill, 'Paused'), findsOneWidget);
    expect(find.text('a' * 64), findsOneWidget);

    await tester.tap(find.byType(SailRowMenuButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SailButton, 'Resume'));
    await tester.pumpAndSettle();
    expect(calls, ['cancel 4', 'resume 4']);
  });
}
