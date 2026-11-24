import 'package:bitwindow/pages/overview_page.dart';
import 'package:bitwindow/providers/news_provider.dart';
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

  @override
  Future<List<OPReturn>> listOPReturns() async {
    if (failure != null) {
      throw failure!;
    }
    return rows;
  }
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
    await GetIt.I.get<NewsProvider>().fetch();
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

  testWidgets('each header sorts by its own column', (tester) async {
    await pump(tester);
    expect(messages(tester), ['bravo', 'alpha', 'charlie'], reason: 'newest first');

    await tapHeader(tester, 'Message');
    expect(tester.takeException(), isNull);
    expect(messages(tester), ['alpha', 'bravo', 'charlie']);

    await tapHeader(tester, 'Height');
    expect(messages(tester), ['charlie', 'alpha', 'bravo']);

    await tapHeader(tester, 'Fee');
    expect(messages(tester), ['alpha', 'bravo', 'charlie']);

    await tapHeader(tester, 'Fee');
    expect(messages(tester), ['charlie', 'bravo', 'alpha']);

    await tapHeader(tester, 'Time');
    expect(messages(tester), ['bravo', 'alpha', 'charlie'], reason: 'time starts newest first');
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
    final news = GetIt.I.get<NewsProvider>();

    misc.failure = Exception('could not list op returns: connection refused');
    await news.fetch();
    await tester.pumpAndSettle();
    expect(find.textContaining('could not list op returns'), findsOneWidget);
    expect(messages(tester), hasLength(3), reason: 'the old rows stay');

    misc.failure = null;
    await news.fetch();
    await tester.pumpAndSettle();
    expect(find.textContaining('could not list op returns'), findsNothing);
    expect(find.text('Browse blockchain graffiti and OP_RETURN data'), findsOneWidget);
  });
}
