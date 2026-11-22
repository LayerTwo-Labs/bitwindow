import 'package:bitwindow/providers/address_book_provider.dart';
import 'package:bitwindow/widgets/address_list.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';

import 'test_utils.dart';

const _unlabeled = 'bcrt1q5828lcyynemg02h5vm4x8jwngkq82nw8cfew7e';

class _Book extends ChangeNotifier implements AddressBookProvider {
  @override
  List<AddressBookEntry> get sendEntries => [
    AddressBookEntry(id: Int64(1), label: 'Landlord', address: 'bcrt1qa', direction: Direction.DIRECTION_SEND),
  ];

  @override
  List<AddressBookEntry> get receiveEntries => [
    AddressBookEntry(id: Int64(2), label: '', address: _unlabeled, direction: Direction.DIRECTION_RECEIVE),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Finder _deleteButton() =>
    find.byWidgetPredicate((w) => w is SailButton && w.icon == SailSVGAsset.iconDelete).hitTestable().first;

Finder _dialogText(String text) => find.descendant(of: find.byType(SailModal), matching: find.text(text));

void main() {
  setUp(() async {
    await GetIt.I.reset();
    GetIt.I.registerSingleton<AddressBookProvider>(_Book());
  });

  tearDown(() => GetIt.I.reset());

  testWidgets('the delete dialog names the label of a labeled entry', (tester) async {
    await tester.pumpSailPage(const AddressBookTable());
    await tester.pumpAndSettle();

    await tester.tap(_deleteButton());
    await tester.pumpAndSettle();

    expect(_dialogText('Are you sure you want to delete "Landlord"?'), findsOneWidget);
  });

  testWidgets('the delete dialog names the address of an entry with no label', (tester) async {
    await tester.pumpSailPage(const AddressBookTable());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Receive').hitTestable().first);
    await tester.pumpAndSettle();
    await tester.tap(_deleteButton());
    await tester.pumpAndSettle();

    expect(_dialogText('Are you sure you want to delete "$_unlabeled"?'), findsOneWidget);
    expect(find.textContaining('delete ""'), findsNothing);
  });
}
