import 'package:coinshift/pages/swap_analytics_page.dart';
import 'package:coinshift/pages/tabs/swaps_page.dart';
import 'package:coinshift/providers/analytics_provider.dart';
import 'package:coinshift/providers/swap_provider.dart';
import 'package:coinshift/widgets/swap/swap_card.dart';
import 'package:coinshift/widgets/swap/swap_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';

import 'test_utils.dart';

class _Analytics extends ChangeNotifier implements AnalyticsProvider {
  @override
  AnalyticsTimeRange get selectedTimeRange => AnalyticsTimeRange.values.first;

  @override
  SwapStatistics get statistics => SwapStatistics.empty();

  @override
  Map<ParentChainType, ChainHealth> get chainHealth => {};

  @override
  List<CoinShiftSwap> get swapsNeedingAttention => [];

  @override
  bool get isLoading => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Swaps extends ChangeNotifier implements SwapProvider {
  @override
  List<CoinShiftSwap> swaps = [];

  @override
  List<CoinShiftSwap> get activeSwaps => [];

  @override
  List<CoinShiftSwap> get claimableSwaps => [
    for (final swap in swaps)
      if (swap.state.isReadyToClaim) swap,
  ];

  @override
  List<CoinShiftSwap> get completedSwaps => [];

  @override
  bool get isLoading => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(WidgetTester tester, Widget child, {SailThemeStyle style = SailThemeStyle.sail}) async {
  final width = SailStyleValues.phoneLayoutOverride == true ? 390.0 : 1200.0;
  await tester.binding.setSurfaceSize(Size(width, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: SailTheme(
        data: SailThemeData.lightTheme(SailColorScheme.orange, true, SailFontValues.inter, style),
        child: Scaffold(body: child),
      ),
    ),
  );
  await tester.pump();
}

CoinShiftSwap _swap(String id, SwapState state) => CoinShiftSwap(
  id: id,
  direction: SwapDirection.l2ToL1,
  parentChain: ParentChainType.signet,
  requiredConfirmations: 3,
  state: state,
  l2Amount: 250000,
  createdAtHeight: 1281,
);

double _fontSize(WidgetTester tester, String text) => tester.widget<Text>(find.text(text).first).style!.fontSize!;

void main() {
  setUp(() async {
    await registerTestDependencies();
    GetIt.I.registerLazySingleton<FormatterProvider>(() => FormatterProvider(GetIt.I.get<SettingsProvider>()));
    GetIt.I.registerSingleton<AnalyticsProvider>(_Analytics());
    GetIt.I.registerSingleton<SwapProvider>(_Swaps());
  });

  tearDown(() async {
    SailStyleValues.phoneLayoutOverride = null;
    await GetIt.I.reset();
  });

  testWidgets('a phone shows the swap analytics in one stat panel under a 16 px title', (tester) async {
    SailStyleValues.phoneLayoutOverride = true;
    await _pump(tester, const SwapAnalyticsPage());

    expect(tester.takeException(), isNull);
    expect(find.byType(SailStatList), findsOneWidget);
    expect(find.byType(SailStatRow), findsNWidgets(5));
    expect(_fontSize(tester, 'Swap Analytics'), 16);
  });

  testWidgets('the desktop puts the title, the five stats and the time range in one strip', (tester) async {
    SailStyleValues.phoneLayoutOverride = false;
    await _pump(tester, const SwapAnalyticsPage());

    expect(tester.takeException(), isNull);
    expect(find.byType(SailStatList), findsNothing);
    final strip = find.byType(SailStrip);
    expect(strip, findsOneWidget);
    expect(find.descendant(of: strip, matching: find.text('Swap Analytics')), findsOneWidget);
    expect(find.descendant(of: strip, matching: find.byType(SailStat)), findsNWidgets(5));
    expect(find.descendant(of: strip, matching: find.text('Time Range:')), findsOneWidget);
  });

  for (final (phone, size) in [(true, 15.0), (false, 14.0)]) {
    testWidgets('the swap counts are $size px when phoneLayout is $phone', (tester) async {
      SailStyleValues.phoneLayoutOverride = phone;
      await _pump(tester, SwapStats(model: SwapsPageViewModel()));

      expect(tester.takeException(), isNull);
      expect(_fontSize(tester, '0'), size);
    });
  }

  for (final (phone, size) in [(true, 13.0), (false, 15.0)]) {
    testWidgets('an empty swap list reads at $size px when phoneLayout is $phone', (tester) async {
      SailStyleValues.phoneLayoutOverride = phone;
      await _pump(tester, const SwapList());

      expect(_fontSize(tester, 'No swaps found'), size);
    });
  }

  testWidgets('the desktop swap strip holds the counts and Create Swap opens the form as a dialog', (tester) async {
    SailStyleValues.phoneLayoutOverride = false;
    await _pump(tester, SwapStats(model: SwapsPageViewModel()));

    expect(find.byType(SailStrip), findsOneWidget);
    expect(find.byType(SailStat), findsNWidgets(4));
    await tester.tap(find.byType(SailButton).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(SwapForm), findsOneWidget);
    expect(find.text('Create Swap (L2 → L1)'), findsOneWidget);
    expect(find.text('Amount you want (sats)'), findsOneWidget);
  });

  testWidgets('a swap row opens its side panel, and a ready swap has Claim in the panel and the row menu', (
    tester,
  ) async {
    SailStyleValues.phoneLayoutOverride = false;
    (GetIt.I.get<SwapProvider>() as _Swaps).swaps = [
      _swap('a3f19c42aa', SwapState(state: 'ReadyToClaim')),
      _swap('7c41e0f9bb', SwapState(state: 'WaitingConfirmations', currentConfirmations: 2, requiredConfirmations: 3)),
    ];
    await _pump(tester, const SwapList(), style: SailThemeStyle.bitwindowV2);
    await tester.pumpAndSettle();

    expect(find.text('Ready to Claim'), findsOneWidget);
    expect(find.text('2 / 3'), findsOneWidget);
    expect(find.byType(SwapSidePanel), findsNothing);

    await tester.tap(find.text('a3f19c42...'));
    await tester.pumpAndSettle();
    expect(find.byType(SwapSidePanel), findsOneWidget);
    expect(find.descendant(of: find.byType(SwapSidePanel), matching: find.byType(SailButton)), findsOneWidget);

    final table = tester.widget<SailTable>(find.byType(SailTable));
    expect(table.contextMenuItems!('a3f19c42aa'), hasLength(2));
    expect(table.contextMenuItems!('7c41e0f9bb'), hasLength(1));
  });

  testWidgets('a phone search that finds one swap opens its sheet', (tester) async {
    SailStyleValues.phoneLayoutOverride = true;
    (GetIt.I.get<SwapProvider>() as _Swaps).swaps = [
      _swap('a3f19c42aa', SwapState(state: 'ReadyToClaim')),
      _swap('7c41e0f9bb', SwapState(state: 'WaitingConfirmations', currentConfirmations: 2, requiredConfirmations: 3)),
    ];
    await _pump(tester, const SwapList(), style: SailThemeStyle.bitwindowV2);
    await tester.pumpAndSettle();
    expect(find.byType(SwapSidePanel), findsNothing);

    await tester.enterText(find.byType(TextField).first, '7c41');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.byType(SwapSidePanel), findsOneWidget);
    expect(tester.widget<SwapSidePanel>(find.byType(SwapSidePanel)).swap.idHex, '7c41e0f9bb');
  });

  testWidgets('an open phone sheet follows the provider, so a swap that becomes ready gets Claim', (tester) async {
    SailStyleValues.phoneLayoutOverride = true;
    final provider = GetIt.I.get<SwapProvider>() as _Swaps;
    provider.swaps = [
      _swap('7c41e0f9bb', SwapState(state: 'WaitingConfirmations', currentConfirmations: 2, requiredConfirmations: 3)),
    ];
    await _pump(tester, const SwapList(), style: SailThemeStyle.bitwindowV2);
    await tester.pumpAndSettle();

    await tester.tap(find.text('7c41e0f9...'));
    await tester.pumpAndSettle();
    final panel = find.byType(SwapSidePanel);
    expect(panel, findsOneWidget);
    expect(find.descendant(of: panel, matching: find.byType(SailButton)), findsNothing);

    provider.swaps = [_swap('7c41e0f9bb', SwapState(state: 'ReadyToClaim'))];
    provider.notifyListeners();
    await tester.pumpAndSettle();

    expect(find.descendant(of: find.byType(SwapSidePanel), matching: find.byType(SailButton)), findsOneWidget);
  });
}
