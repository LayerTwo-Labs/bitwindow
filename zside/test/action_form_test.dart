import 'package:flutter_test/flutter_test.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:zside/widgets/containers/dashboard_action_modal.dart';
import 'package:zside/widgets/v2_parts.dart';

import 'test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('an action dialog has a ×, no Cancel, the values in one grey group and a full-width action', (
    tester,
  ) async {
    await tester.pumpSailPage(
      DashboardActionModal(
        'Melt UTXOs',
        endActionButton: SailButton(label: 'Execute melt', onPressed: () async {}),
        children: const [
          StaticActionField(label: 'Melt to', value: 'Your Z-address'),
          StaticActionField(label: 'Melt fee', value: '0.0001 BTC'),
          StaticActionInfo(text: 'This sends all coins.'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Melt UTXOs'), findsOneWidget);
    expect(find.byType(SailIconBoxButton), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
    expect(find.byType(SailDetailGroup), findsOneWidget);
    expect(find.descendant(of: find.byType(SailDetailGroup), matching: find.text('Melt fee')), findsOneWidget);
    expect(find.byType(DetailNote), findsOneWidget);

    final form = tester.getRect(find.byType(ActionForm));
    final button = tester.getRect(find.byType(SailButton));
    expect(button.width, closeTo(form.width, 1));
    expect(button.top, greaterThan(tester.getRect(find.byType(DetailNote)).bottom));
  });
}
