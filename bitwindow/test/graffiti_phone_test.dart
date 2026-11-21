import 'package:bitwindow/pages/overview_page.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';

import 'test_utils.dart';

void main() {
  setUpAll(loadBundledFonts);
  setUp(() async {
    await GetIt.I.reset();
    await registerTestDependencies();
  });
  tearDown(() async {
    SailStyleValues.phoneLayoutOverride = null;
    await GetIt.I.reset();
  });

  Future<void> pump(WidgetTester tester, {double width = 358}) async {
    await tester.pumpSailPage(SizedBox(width: width, height: 700, child: const GraffitiExplorerView()));
    await tester.pump();
  }

  testWidgets('on a phone the date filter sits under the search, icon first', (tester) async {
    SailStyleValues.phoneLayoutOverride = true;
    await pump(tester);

    final search = tester.getRect(find.text('Search by message or txid...'));
    final from = tester.getRect(find.text('From'));
    final to = tester.getRect(find.text('To'));
    expect(from.top, greaterThan(search.bottom));
    expect(to.top, from.top);
    final field = tester.getRect(find.ancestor(of: find.text('From'), matching: find.byType(SailTappable)).first);
    expect(from.left - field.left, greaterThan(24), reason: 'the calendar icon comes first');
    expect(tester.takeException(), isNull);
  });

  testWidgets('on the desktop the search and dates share one row', (tester) async {
    SailStyleValues.phoneLayoutOverride = false;
    await pump(tester, width: 900);

    final search = tester.getRect(find.text('Search by message or txid...'));
    final from = tester.getRect(find.text('From'));
    expect(from.left, greaterThan(search.right));
  });
}
