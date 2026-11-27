import 'package:bitwindow/widgets/coinnews.dart';
import 'package:bitwindow/widgets/fee_coinnews.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';
import 'package:sail_ui/sail_ui.dart';

import 'test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => SailStyleValues.phoneLayoutOverride = null);

  final story = CoinNews(
    topic: 'a1a1a1a1',
    headline: 'A story the user opens two times',
    feeSats: Int64(3000),
    createTime: Timestamp.fromDateTime(DateTime.utc(2026, 11, 27, 13)),
  );

  Future<void> tapTwice(WidgetTester tester) async {
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text(story.headline));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('Fee Coin News opens the same story on each tap', (tester) async {
    SailStyleValues.phoneLayoutOverride = false;
    final opened = <CoinNews>[];
    await tester.pumpSailPage(
      SizedBox(
        width: 700,
        child: FeeCoinNewsTable(entries: [story], loading: false, onArticleSelected: opened.add),
      ),
    );
    await tester.pumpAndSettle();

    await tapTwice(tester);

    expect(opened, [story, story]);
  });

  testWidgets('Hacker Coin News opens the same story on each tap', (tester) async {
    SailStyleValues.phoneLayoutOverride = false;
    final opened = <CoinNews>[];
    await tester.pumpSailPage(
      SizedBox(
        width: 700,
        child: CoinNewsTable(entries: [story], onSort: (_) {}, loading: false, onArticleSelected: opened.add),
      ),
    );
    await tester.pumpAndSettle();

    await tapTwice(tester);

    expect(opened, [story, story]);
  });
}
