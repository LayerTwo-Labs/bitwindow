import 'dart:ui';

import 'package:bitwindow/providers/blockchain_provider.dart';
import 'package:bitwindow/widgets/coinnews.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';
import 'package:sail_ui/sail_ui.dart';

import 'mocks/api_mock.dart';
import 'test_utils.dart';

const _story = '0123456789abcdef01234567';

class _MiscAPI extends MockMiscAPI {
  List<Comment> comments = [];
  bool failList = false;
  bool failPost = false;
  bool failEstimate = false;
  final List<String> estimated = [];

  @override
  Future<List<Comment>> listComments(String itemId) async {
    if (failList) {
      throw Exception('connection refused');
    }
    return [...comments];
  }

  @override
  Future<CommentNewsResponse> commentNews(
    String parentId,
    String body, {
    String? url,
    String? lang,
    String? replyQuote,
    int? feeSatPerVbyte,
    int? feeSats,
  }) async {
    if (failPost) {
      throw Exception('the node does not answer');
    }
    comments = [
      ...comments,
      Comment(
        itemId: 'mine',
        parentId: parentId,
        author: 'feedfeedfeedfeed',
        body: body,
        feeSats: Int64(700),
        pending: true,
      ),
    ];
    return CommentNewsResponse();
  }

  @override
  Future<NewsFeeEstimate> estimateNewsFee(
    NewsAction action, {
    String body = '',
    String headline = '',
    String url = '',
    int subtype = 0,
    bool nsfw = false,
    String topicName = '',
    int retentionDays = 0,
  }) async {
    estimated.add(body);
    if (failEstimate) {
      throw Exception('no estimate');
    }
    return NewsFeeEstimate(vsize: 100 + body.length, feeSatPerVbyte: 1, feeSats: 100 + body.length);
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
  final time = DateTime.utc(2026, 11, 16, 16, 32);

  Comment mined(String id, String body, {String parent = _story, int fee = 1200}) => Comment(
    itemId: id,
    parentId: parent,
    author: '3f9ac21e7b00ffff',
    body: body,
    feeSats: Int64(fee),
    createTime: Timestamp.fromDateTime(time),
  );

  setUp(() async {
    await GetIt.I.reset();
    rpc = _API();
    GetIt.I.registerSingleton<BitwindowRPC>(rpc);
    await registerTestDependencies();
    await GetIt.I.get<ClientSettings>().setValue(CommentWarningSeenSetting(newValue: true));
  });

  tearDown(() => GetIt.I.reset());

  Future<void> pumpPanel(WidgetTester tester) async {
    await tester.pumpSailPage(
      SizedBox(
        width: 1000,
        height: 600,
        child: CoinNewsArticlePanel(
          news: CoinNews(headline: 'Headline', topic: 'a1a1a1a1', itemId: _story),
          onClose: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final commentButton = find.widgetWithText(SailButton, 'Comment').first;

  Future<void> post(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.tap(commentButton);
    await tester.pumpAndSettle();
  }

  Future<void> hoverComment(WidgetTester tester) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(commentButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('a posted comment shows at once as pending', (tester) async {
    await pumpPanel(tester);
    expect(find.text('No comments yet. Be the first.'), findsOneWidget);

    await post(tester, 'My comment');

    expect(find.text('Comments (1)'), findsOneWidget);
    expect(find.text('My comment'), findsOneWidget);
    expect(find.textContaining('feedfeedfe…  ·  Pending  ·  '), findsOneWidget);
    expect(find.text('No comments yet. Be the first.'), findsNothing);
    expect(find.widgetWithText(SailButton, 'Reply'), findsNothing, reason: 'a reply waits for the block of its parent');

    rpc.misc.comments = [mined('mine', 'My comment')];
    GetIt.I.get<BlockchainProvider>().notifyListeners();
    await tester.pumpAndSettle();
    expect(find.widgetWithText(SailButton, 'Reply'), findsWidgets);
  });

  testWidgets('a comment shows its date and its fee', (tester) async {
    rpc.misc.comments = [mined('c1', 'First'), mined('c2', 'No fee known', fee: 0)];
    await pumpPanel(tester);

    final fee = GetIt.I.get<FormatterProvider>().formatSats(1200);
    expect(find.text('3f9ac21e7b…  ·  ${formatDate(time)}  ·  $fee'), findsOneWidget);
    expect(find.text('3f9ac21e7b…  ·  ${formatDate(time)}'), findsOneWidget);
  });

  testWidgets('a new block or mempool transaction reads the thread again', (tester) async {
    await pumpPanel(tester);
    final blockchain = GetIt.I.get<BlockchainProvider>();

    rpc.misc.comments = [mined('c1', 'From another node')];
    blockchain.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('From another node'), findsOneWidget);

    rpc.misc.comments = [mined('c1', 'From another node'), mined('c2', 'From the mempool')];
    (blockchain.recentChanged as ChangeNotifier).notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('From the mempool'), findsOneWidget);
    expect(find.text('Loading comments…'), findsNothing);
  });

  testWidgets('a failed post keeps the thread and the text, and shows the error', (tester) async {
    rpc.misc.comments = [mined('c1', 'First')];
    await pumpPanel(tester);
    rpc.misc.failPost = true;

    await post(tester, 'Does not go out');

    expect(find.text('First'), findsOneWidget);
    expect(find.textContaining('the node does not answer'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'Does not go out');

    rpc.misc.failPost = false;
    await tester.tap(commentButton);
    await tester.pumpAndSettle();
    expect(find.textContaining('the node does not answer'), findsNothing);
    expect(find.text('Does not go out'), findsOneWidget);
  });

  testWidgets('a failed read keeps the comments of the last read', (tester) async {
    rpc.misc.comments = [mined('c1', 'First')];
    await pumpPanel(tester);

    rpc.misc.failList = true;
    GetIt.I.get<BlockchainProvider>().notifyListeners();
    await tester.pumpAndSettle();

    expect(find.text('First'), findsOneWidget);
    expect(find.textContaining('connection refused'), findsOneWidget);
  });

  testWidgets('the fee tooltip prices the text in the field', (tester) async {
    await pumpPanel(tester);
    await tester.enterText(find.byType(TextField), 'hello');
    await hoverComment(tester);

    expect(rpc.misc.estimated, ['hello']);
    expect(find.textContaining('≈ 105 sats'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'hello again');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 200));
    expect(rpc.misc.estimated, ['hello', 'hello again']);
    expect(find.textContaining('≈ 111 sats'), findsOneWidget);
  });

  testWidgets('the fee tooltip does not wait for an estimate that failed', (tester) async {
    rpc.misc.failEstimate = true;
    await pumpPanel(tester);
    await tester.enterText(find.byType(TextField), 'hello');
    await hoverComment(tester);

    expect(rpc.misc.estimated, ['hello']);
    expect(find.text('Checking the fee…'), findsNothing);
  });

  testWidgets('the first comment warning prices the comment text', (tester) async {
    await GetIt.I.get<ClientSettings>().setValue(CommentWarningSeenSetting(newValue: false));
    await pumpPanel(tester);

    await tester.enterText(find.byType(TextField), 'A comment of 26 characters');
    await tester.tap(commentButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(rpc.misc.estimated, ['A comment of 26 characters']);
    expect(find.textContaining('≈ 126 sats'), findsOneWidget);
  });
}
