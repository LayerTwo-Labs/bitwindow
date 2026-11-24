import 'package:bitwindow/pages/overview_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';

import 'mocks/api_mock.dart';
import 'test_utils.dart';

class _Misc extends MockMiscAPI {
  final requests = <ListOPReturnRequest>[];

  @override
  Future<List<OPReturn>> listOPReturns(ListOPReturnRequest request) async {
    requests.add(request);
    return [];
  }
}

class _API extends MockAPI {
  _API(this._misc) : super(binaryType: BinaryType.BINARY_TYPE_BITWINDOWD);

  final _Misc _misc;

  @override
  _Misc get misc => _misc;
}

void main() {
  setUpAll(loadBundledFonts);

  late _Misc misc;
  late DateTime yesterday;

  setUp(() async {
    await GetIt.I.reset();
    misc = _Misc();
    final today = DateTime.now();
    yesterday = DateTime(today.year, today.month, today.day - 1);
    GetIt.I.registerLazySingleton<BitwindowRPC>(() => _API(misc));
    await registerTestDependencies();
  });

  tearDown(() async {
    SailStyleValues.phoneLayoutOverride = null;
    await GetIt.I.reset();
  });

  Future<void> pump(WidgetTester tester) async {
    SailStyleValues.phoneLayoutOverride = false;
    await tester.pumpSailPage(const SizedBox(width: 1200, height: 700, child: GraffitiExplorerView()));
    await tester.pumpAndSettle();
  }

  Future<void> selectYesterday(WidgetTester tester, String field) async {
    await tester.tap(find.text(field));
    await tester.pumpAndSettle();
    final calendar = tester.widget<CalendarDatePicker>(find.byType(CalendarDatePicker));
    if (calendar.initialDate!.month != yesterday.month) {
      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.descendant(of: find.byType(CalendarDatePicker), matching: find.text('${yesterday.day}')));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text(formatDate(yesterday)), findsOneWidget);
  }

  testWidgets('an empty From picker opens after To selects yesterday', (tester) async {
    await pump(tester);
    await selectYesterday(tester, 'To');

    await tester.tap(find.text('From'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(DatePickerDialog), findsOneWidget);
    final calendar = tester.widget<CalendarDatePicker>(find.byType(CalendarDatePicker));
    expect(calendar.initialDate, yesterday);
    expect(calendar.lastDate, yesterday);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  for (final field in ['From', 'To']) {
    for (final cancel in [true, false]) {
      testWidgets('${cancel ? 'Cancel' : 'Dismiss'} keeps the $field date and query', (tester) async {
        await pump(tester);
        await tester.enterText(find.byType(EditableText).first, 'old graffiti');
        await tester.pump(GraffitiExplorerViewModel.searchDelay);
        await tester.pumpAndSettle();
        await selectYesterday(tester, field);
        final query = misc.requests.last;
        final reads = misc.requests.length;

        await tester.tap(find.text(formatDate(yesterday)));
        await tester.pumpAndSettle();
        if (cancel) {
          await tester.tap(find.text('Cancel'));
        } else {
          await tester.tapAt(const Offset(10, 10));
        }
        await tester.pumpAndSettle();

        expect(find.byType(DatePickerDialog), findsNothing);
        expect(find.text(formatDate(yesterday)), findsOneWidget);
        expect(misc.requests.length, reads);
        expect(misc.requests.last, query);
      });
    }
  }

  testWidgets('Clear removes both dates and the search', (tester) async {
    await pump(tester);
    await selectYesterday(tester, 'From');
    await tester.tap(find.text('To'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).first, 'old graffiti');
    await tester.pump(GraffitiExplorerViewModel.searchDelay);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();

    expect(find.text('From'), findsOneWidget);
    expect(find.text('To'), findsOneWidget);
    expect(find.text('Clear'), findsNothing);
    expect(misc.requests.last.hasFrom(), isFalse);
    expect(misc.requests.last.hasTo(), isFalse);
    expect(misc.requests.last.search, isEmpty);
  });
}
