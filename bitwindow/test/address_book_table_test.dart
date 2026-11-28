import 'package:bitwindow/providers/address_book_provider.dart';
import 'package:bitwindow/widgets/address_list.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';

import 'test_utils.dart';

class _Book extends ChangeNotifier implements AddressBookProvider {
  @override
  List<AddressBookEntry> get sendEntries => [
    AddressBookEntry(
      id: Int64(1),
      label: 'Landlord',
      address: 'bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh',
      direction: Direction.DIRECTION_SEND,
    ),
  ];

  @override
  List<AddressBookEntry> get receiveEntries => [
    AddressBookEntry(
      id: Int64(2),
      label: 'Salary',
      address: 'bc1q9h7garjqc5wf4gq7r4r6a0p7d2hz9ytm5ze6qd',
      direction: Direction.DIRECTION_RECEIVE,
    ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Finder _headMenu() => find.byWidgetPredicate((w) => w is SailRowMenuButton && w.filled);
Finder _rowMenu() => find.byWidgetPredicate((w) => w is SailRowMenuButton && !w.filled);

void main() {
  setUp(() async {
    await GetIt.I.reset();
    GetIt.I.registerSingleton<AddressBookProvider>(_Book());
  });

  tearDown(() => GetIt.I.reset());

  testWidgets('the table has Label and Address columns and one "…" per row', (tester) async {
    await tester.pumpSailPage(const AddressBookTable());
    await tester.pumpAndSettle();

    expect(find.text('Label'), findsOneWidget);
    expect(find.text('Address'), findsOneWidget);
    expect(find.text('Actions'), findsNothing);
    expect(_rowMenu(), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is SailButton && w.icon == SailSVGAsset.iconDelete), findsNothing);
  });

  testWidgets('the row "…" holds Edit Label and Delete', (tester) async {
    await tester.pumpSailPage(const AddressBookTable());
    await tester.pumpAndSettle();

    await tester.tap(_rowMenu());
    await tester.pumpAndSettle();

    expect(find.text('Edit Label'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('the head "…" holds Import and Export, and Add Address is the one button', (tester) async {
    await tester.pumpSailPage(const AddressBookTable());
    await tester.pumpAndSettle();

    expect(find.widgetWithText(SailButton, 'Add Address'), findsOneWidget);
    expect(find.text('Import'), findsNothing);

    await tester.tap(_headMenu());
    await tester.pumpAndSettle();

    expect(find.text('Import'), findsOneWidget);
    expect(find.text('Export'), findsOneWidget);
  });

  testWidgets('Receive has no Add Address but keeps the head "…"', (tester) async {
    await tester.pumpSailPage(const AddressBookTable());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Receive').hitTestable().first);
    await tester.pumpAndSettle();

    expect(find.text('Receiving Addresses'), findsOneWidget);
    expect(find.text('Add Address'), findsNothing);
    expect(_headMenu(), findsOneWidget);
  });

  testWidgets('the delete dialog has a × and one Delete button, and no Cancel', (tester) async {
    await tester.pumpSailPage(const AddressBookTable());
    await tester.pumpAndSettle();

    await tester.tap(_rowMenu());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').hitTestable().last);
    await tester.pumpAndSettle();

    final modal = find.byType(SailModal);
    expect(
      find.descendant(
        of: modal,
        matching: find.byWidgetPredicate((w) => w is SailIconBoxButton && w.icon == SailSVGAsset.x),
      ),
      findsOneWidget,
    );
    expect(find.descendant(of: modal, matching: find.text('Cancel')), findsNothing);
    final delete = tester.widget<SailButton>(
      find.descendant(of: modal, matching: find.widgetWithText(SailButton, 'Delete')),
    );
    expect(delete.variant, ButtonVariant.destructive);
  });
}
