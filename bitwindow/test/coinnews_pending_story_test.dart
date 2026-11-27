import 'package:bitwindow/providers/news_provider.dart';
import 'package:bitwindow/widgets/coinnews.dart';
import 'package:bitwindow/widgets/fee_coinnews.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';
import 'package:sail_ui/sail_ui.dart';

import 'mocks/api_mock.dart';
import 'test_utils.dart';

const _txid = 'ba08cba329fae1afd6e71e0766a1c90b53cbadd76d7474e1e9f4f0410c5c7e56';
const _itemId = 'fb599d776890a0d5079cbaff';

class _MiscAPI extends MockMiscAPI {
  final List<String> reads = [];

  @override
  Future<List<Comment>> listComments(String itemId) async {
    reads.add(itemId);
    return [];
  }
}

class _API extends MockAPI {
  _API() : super(binaryType: BinaryType.BINARY_TYPE_BITWINDOWD);

  final _MiscAPI fakeMisc = _MiscAPI();

  @override
  _MiscAPI get misc => fakeMisc;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _API rpc;
  final seen = DateTime.utc(2026, 11, 27, 9, 13);
  final mined = DateTime.utc(2026, 11, 27, 9, 15);

  final pending = CoinNews(
    headline: 'QA pending story',
    content: 'Body of the pending story.',
    topic: 'a1a1a1a1',
    feeSats: Int64(3000),
    txid: _txid,
    vout: 0,
    createTime: Timestamp.fromDateTime(seen),
    pending: true,
  );
  final confirmed = pending.deepCopy()
    ..pending = false
    ..itemId = _itemId
    ..createTime = Timestamp.fromDateTime(mined);

  setUp(() async {
    await GetIt.I.reset();
    rpc = _API();
    GetIt.I.registerSingleton<BitwindowRPC>(rpc);
    await registerTestDependencies();
    final news = GetIt.I.get<NewsProvider>();
    news.topics = [Topic(id: Int64(1), topic: 'a1a1a1a1', name: 'US Weekly', confirmed: true)];
    news.news = [pending];
  });

  tearDown(() => GetIt.I.reset());

  void readNews(List<CoinNews> news) {
    final provider = GetIt.I.get<NewsProvider>();
    provider.news = news;
    provider.notifyListeners();
  }

  test('storyTime gives Pending for a story in the mempool and the time for a story in a block', () {
    expect(storyTime(pending, formatDate), 'Pending');
    expect(storyTime(confirmed, formatDate), formatDate(mined));
  });

  testWidgets('the fee table shows Pending in place of the time of a story in the mempool', (tester) async {
    await tester.pumpSailPage(
      SizedBox(
        width: 700,
        height: 300,
        child: FeeCoinNewsTable(entries: [pending], loading: false),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pending'), findsOneWidget);
    expect(find.text(formatDate(seen, long: false)), findsNothing);
  });

  testWidgets('the article panel shows the comments after the block of an open pending story', (tester) async {
    await tester.pumpSailPage(
      SizedBox(
        width: 1000,
        height: 600,
        child: CoinNewsArticlePanel(news: pending, onClose: () {}),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('US Weekly  ·  Pending'), findsOneWidget);
    expect(find.text('Comments open when the story is in a block.'), findsOneWidget);
    expect(find.widgetWithText(SailButton, 'Comment'), findsNothing);
    expect(rpc.misc.reads, isEmpty);

    readNews([confirmed]);
    await tester.pumpAndSettle();

    expect(find.text('US Weekly  ·  ${formatDate(mined)}'), findsOneWidget);
    expect(find.text('No comments yet. Be the first.'), findsOneWidget);
    expect(find.widgetWithText(SailButton, 'Comment'), findsWidgets);
    expect(rpc.misc.reads, [_itemId]);
  });

  testWidgets('the article panel closes the comments when a reorg sends the story back to the mempool', (tester) async {
    readNews([confirmed]);
    await tester.pumpSailPage(
      SizedBox(
        width: 1000,
        height: 600,
        child: CoinNewsArticlePanel(news: confirmed, onClose: () {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(SailButton, 'Comment'), findsWidgets);

    readNews([pending]);
    await tester.pumpAndSettle();

    expect(find.text('US Weekly  ·  Pending'), findsOneWidget);
    expect(find.text('Comments open when the story is in a block.'), findsOneWidget);
    expect(find.widgetWithText(SailButton, 'Comment'), findsNothing);
  });
}
