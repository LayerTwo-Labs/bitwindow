import 'package:bitwindow/pages/learn_page.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';

import 'test_utils.dart';

void main() {
  tearDown(() => GetIt.I.reset());

  testWidgets('the right arrow hides at the end of the list', (tester) async {
    final group = ArticleGroup(
      title: 'Getting Started',
      subtitle: '',
      articles: [
        for (var i = 0; i < 10; i++) Article(title: 'Article $i', markdown: 'word', filename: '$i.mdx'),
      ],
    );
    await tester.pumpSailPage(SingleChildScrollView(child: ArticleGroupCard(group: group)));
    await tester.pumpAndSettle();

    final arrows = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_ScrollButton');
    final carousel = find.byType(ListView);
    SailSVGAsset iconOf(Finder arrow) =>
        tester.widget<SailIconBoxButton>(find.descendant(of: arrow, matching: find.byType(SailIconBoxButton))).icon;

    expect(arrows, findsOneWidget);
    expect(iconOf(arrows), SailSVGAsset.chevronRight);
    expect(tester.getCenter(arrows).dy, lessThan(tester.getTopLeft(carousel).dy));

    final controller = tester.widget<ListView>(carousel).controller!;
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();

    expect(arrows, findsOneWidget);
    expect(iconOf(arrows), SailSVGAsset.chevronLeft);

    controller.jumpTo(controller.position.maxScrollExtent / 2);
    await tester.pumpAndSettle();

    expect(arrows, findsNWidgets(2));
    expect(iconOf(arrows.first), SailSVGAsset.chevronLeft);
    expect(tester.getCenter(arrows.first).dx, lessThan(tester.getCenter(arrows.last).dx));
  });
}
