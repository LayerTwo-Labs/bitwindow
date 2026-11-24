import 'package:bitwindow/pages/overview_page.dart';

import 'dart:async';

import 'package:fixnum/fixnum.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';
import 'package:sail_ui/sail_ui.dart';

import 'mocks/api_mock.dart';
import 'test_utils.dart';

class _Misc extends MockMiscAPI {
  List<OPReturn> rows = [];
  Exception? failure;
  final requests = <ListOPReturnRequest>[];

  /// When set, the next read waits for this future.
  Future<void>? hold;

  @override
  Future<List<OPReturn>> listOPReturns(ListOPReturnRequest request) async {
    requests.add(request);
    final rowsNow = rows;
    final wait = hold;
    hold = null;
    if (wait != null) {
      await wait;
    }
    if (failure != null) {
      throw failure!;
    }
    return rowsNow;
  }

  ListOPReturnRequest get last => requests.last;
}

class _API extends MockAPI {
  _API(this._misc) : super(binaryType: BinaryType.BINARY_TYPE_BITWINDOWD);

  final _Misc _misc;

  @override
  _Misc get misc => _misc;
}

OPReturn graffiti(int id, String message, {required int height, required int feeSats, required int minute}) => OPReturn(
  id: Int64(id),
  message: message,
  txid: ('$id' * 8).padRight(64, 'a'),
  height: height,
  feeSats: Int64(feeSats),
  createTime: Timestamp.fromDateTime(DateTime(2026, 11, 23, 12, minute)),
);

void main() {
  setUpAll(loadBundledFonts);

  late _Misc misc;

  setUp(() async {
    await GetIt.I.reset();
    misc = _Misc()
      ..rows = [
        graffiti(1, 'bravo', height: 103, feeSats: 160, minute: 3),
        graffiti(2, 'charlie', height: 101, feeSats: 1092, minute: 1),
        graffiti(3, 'alpha', height: 102, feeSats: 0, minute: 2),
      ];
    GetIt.I.registerLazySingleton<BitwindowRPC>(() => _API(misc));
    await registerTestDependencies();
  });
  tearDown(() async {
    SailStyleValues.phoneLayoutOverride = null;
    await GetIt.I.reset();
  });

  Future<void> pump(WidgetTester tester) async {
    SailStyleValues.phoneLayoutOverride = false;
    await tester.pumpSailPage(const SizedBox(width: 1200, height: 700, child: GraffitiExplorerView()));
    await tester.pumpAndSettle();
  }

  List<String> messages(WidgetTester tester) =>
      tester.widget<GraffitiTable>(find.byType(GraffitiTable)).entries.map((e) => e.message).toList();

  Future<void> tapHeader(WidgetTester tester, String name) async {
    final header = find.descendant(of: find.byType(GraffitiTable), matching: find.text(name));
    await tester.ensureVisible(header);
    await tester.tap(header);
    await tester.pumpAndSettle();
  }

  testWidgets('each header asks the server for its own sort', (tester) async {
    await pump(tester);
    expect(misc.last.sort, OPReturnSort.OP_RETURN_SORT_TIME);
    expect(misc.last.ascending, isFalse, reason: 'newest first');
    expect(messages(tester), ['bravo', 'charlie', 'alpha'], reason: 'the server order stays');

    await tapHeader(tester, 'Message');
    expect(tester.takeException(), isNull);
    expect((misc.last.sort, misc.last.ascending), (OPReturnSort.OP_RETURN_SORT_MESSAGE, true));

    await tapHeader(tester, 'Height');
    expect((misc.last.sort, misc.last.ascending), (OPReturnSort.OP_RETURN_SORT_HEIGHT, true));

    await tapHeader(tester, 'Fee');
    expect((misc.last.sort, misc.last.ascending), (OPReturnSort.OP_RETURN_SORT_FEE, true));

    await tapHeader(tester, 'Fee');
    expect((misc.last.sort, misc.last.ascending), (OPReturnSort.OP_RETURN_SORT_FEE, false));

    await tapHeader(tester, 'TXID');
    expect((misc.last.sort, misc.last.ascending), (OPReturnSort.OP_RETURN_SORT_TXID, true));

    await tapHeader(tester, 'Time');
    expect((misc.last.sort, misc.last.ascending), (OPReturnSort.OP_RETURN_SORT_TIME, false));
  });

  testWidgets('a search asks the server once, after the typing stops', (tester) async {
    await pump(tester);
    final before = misc.requests.length;
    misc.rows = [graffiti(9, 'the oldest graffiti', height: 1, feeSats: 200, minute: 0)];

    await tester.enterText(find.byType(EditableText).first, ' old');
    await tester.pump(GraffitiExplorerViewModel.searchDelay ~/ 2);
    await tester.enterText(find.byType(EditableText).first, ' oldest ');
    await tester.pump(GraffitiExplorerViewModel.searchDelay);
    await tester.pumpAndSettle();

    expect(misc.requests.length, before + 1);
    expect(misc.last.search, 'oldest');
    expect(messages(tester), ['the oldest graffiti']);
  });

  testWidgets('a date range asks for whole local days', (tester) async {
    await pump(tester);
    final vm = GraffitiExplorerViewModel()..setFromDate(DateTime(2026, 3, 29, 15));
    addTearDown(vm.dispose);
    vm.setToDate(DateTime(2026, 3, 30, 9));
    await tester.pumpAndSettle();

    expect(misc.last.from.toDateTime(), DateTime(2026, 3, 29).toUtc());
    expect(misc.last.to.toDateTime(), DateTime(2026, 3, 31).toUtc());
  });

  testWidgets('an old read that ends late does not replace a newer read', (tester) async {
    await pump(tester);
    final slow = Completer<void>();
    misc.hold = slow.future;
    misc.rows = [graffiti(7, 'stale', height: 1, feeSats: 1, minute: 0)];
    await tapHeader(tester, 'Height');

    misc.rows = [graffiti(8, 'fresh', height: 2, feeSats: 1, minute: 0)];
    await tapHeader(tester, 'Height');
    expect(messages(tester), ['fresh']);

    slow.complete();
    await tester.pumpAndSettle();
    expect(messages(tester), ['fresh']);
  });

  testWidgets('the fee of each graffiti shows, and an unknown fee shows a dash', (tester) async {
    await pump(tester);
    final formatter = GetIt.I.get<FormatterProvider>();

    expect(find.text(formatter.formatSats(160)), findsOneWidget);
    expect(find.text(formatter.formatSats(1092)), findsOneWidget);
    expect(find.text(formatter.formatSats(0)), findsNothing);
  });

  testWidgets('the message shows next to a short txid', (tester) async {
    await pump(tester);

    final message = tester.getRect(find.text('charlie'));
    final table = tester.getRect(find.byType(GraffitiTable));
    expect(message.right, lessThanOrEqualTo(table.right));
    expect(find.text(misc.rows[1].txid), findsNothing);
  });

  testWidgets('a failed read shows on the card until a read works', (tester) async {
    await pump(tester);

    misc.failure = Exception('could not list op returns: connection refused');
    await tapHeader(tester, 'Height');
    expect(find.textContaining('could not list op returns'), findsOneWidget);
    expect(messages(tester), hasLength(3), reason: 'the old rows stay');

    misc.failure = null;
    await tapHeader(tester, 'Height');
    expect(find.textContaining('could not list op returns'), findsNothing);
    expect(find.text('Browse blockchain graffiti and OP_RETURN data'), findsOneWidget);
  });

  testWidgets('the parsed tip refreshes graffiti after the mainchain tip arrives', (tester) async {
    final sync = GetIt.I.get<SyncProvider>();
    sync.mainchainSyncInfo = SyncInfo(progressCurrent: 104, progressGoal: 104, lastBlockAt: null);
    sync.enforcerSyncInfo = SyncInfo(progressCurrent: 104, progressGoal: 104, lastBlockAt: null);
    sync.bitwindowdSyncInfo = SyncInfo(progressCurrent: 103, progressGoal: 104, lastBlockAt: null);
    misc.rows = [graffiti(4, 'new row', height: 0, feeSats: 190, minute: 4)];
    await pump(tester);
    sync.notifyListeners();
    await tester.pumpAndSettle();
    final reads = misc.requests.length;

    misc.rows = [graffiti(4, 'new row', height: 104, feeSats: 190, minute: 4)];
    sync.bitwindowdSyncInfo = SyncInfo(progressCurrent: 104, progressGoal: 104, lastBlockAt: null);
    sync.notifyListeners();
    await tester.pumpAndSettle();

    expect(tester.widget<GraffitiTable>(find.byType(GraffitiTable)).entries.single.height, 104);
    expect(misc.requests.length, reads + 1);
    sync.notifyListeners();
    await tester.pumpAndSettle();
    expect(misc.requests.length, reads + 1);

    await tester.pumpWidget(const SizedBox.shrink());
    sync.bitwindowdSyncInfo = SyncInfo(progressCurrent: 105, progressGoal: 105, lastBlockAt: null);
    sync.notifyListeners();
    await tester.pumpAndSettle();
    expect(misc.requests.length, reads + 1);
  });
}
