import 'package:bitwindow/widgets/proof_of_funds_modal.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';

import 'test_utils.dart';

void main() {
  tearDown(() => GetIt.I.reset());

  testWidgets('Proof of Funds is a kit dialog with one full-width button per tab', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpSailPage(const ProofOfFundsModal());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byWidgetPredicate((w) => w is SailIconBoxButton && w.icon == SailSVGAsset.x), findsOneWidget);
    expect(tester.widget<InlineTabBar>(find.byType(InlineTabBar)).tabs.map((t) => t.icon), everyElement(isNull));
    expect(find.byType(SailCheckbox), findsOneWidget);
    expect(tester.widget<SailButton>(find.widgetWithText(SailButton, 'Browse')).variant, ButtonVariant.secondary);

    final generate = find.widgetWithText(SailButton, 'Generate Proof of Funds Report');
    final generateButton = tester.widget<SailButton>(generate);
    expect(generateButton.variant, ButtonVariant.primary);
    expect(generateButton.icon, isNull);
    final field = tester.getRect(find.byType(SailTextField).last);
    final browse = tester.getRect(find.widgetWithText(SailButton, 'Browse'));
    expect(tester.getRect(generate).width, closeTo(browse.right - field.left, 2));
  });
}
