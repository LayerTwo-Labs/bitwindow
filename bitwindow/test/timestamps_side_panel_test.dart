import 'package:bitwindow/pages/wallet/wallet_timestamps.dart';
import 'package:bitwindow/providers/timestamp_provider.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';
import 'package:sail_ui/sail_ui.dart';

import 'test_utils.dart';

const _hash = 'f3a1c09e5b7d2468ace013579bdf2468ace013579bdf2468ace013579bdf2468';
const _txid = '9c2e7b14d0a85f36e1b4c7d2a09f8e6b5c3d1a2f4e6b8c0d2f4a6c8e0b2d4f61';

class _FakeTimestampProvider extends ChangeNotifier implements TimestampProvider {
  @override
  List<FileTimestamp> timestamps = [
    FileTimestamp(
      id: Int64(7),
      filename: 'contract.pdf',
      fileHash: _hash,
      txid: _txid,
      blockHeight: Int64(214882),
      status: 'confirmed',
      confirmations: 12,
      confirmedAt: Timestamp.fromDateTime(DateTime(2026, 11, 20, 9, 14)),
    ),
  ];

  @override
  bool get isLoading => false;

  @override
  String? modelError;

  @override
  Future<void> fetch() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(WidgetTester tester) async {
  GetIt.I.registerSingleton<TimestampProvider>(_FakeTimestampProvider());
  final theme = SailThemeData.lightTheme(
    SailColorScheme.orange,
    false,
    SailFontValues.inter,
    SailThemeStyle.bitwindowV2,
  );
  await tester.pumpSailPage(SailTheme(data: theme, child: const TimestampsTab()));
  await tester.binding.setSurfaceSize(const Size(1440, 900));
  await tester.pump();
}

void main() {
  setUpAll(loadBundledFonts);

  setUp(() async {
    await GetIt.I.reset();
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  testWidgets('a row click opens Timestamp Details in the side panel', (tester) async {
    await _pump(tester);
    expect(find.text('Actions'), findsNothing);
    expect(find.widgetWithText(SailButton, 'View Details'), findsNothing);

    await tester.tap(find.text('contract.pdf'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    final panel = find.byType(SailSidePanel);
    expect(find.descendant(of: panel, matching: find.text('Timestamp Details')), findsOneWidget);
    expect(find.descendant(of: panel, matching: find.widgetWithText(SailStatusPill, 'CONFIRMED')), findsOneWidget);
    expect(find.descendant(of: panel, matching: find.text(_hash)), findsOneWidget);
    expect(find.descendant(of: panel, matching: find.text(_txid)), findsOneWidget);
    expect(find.descendant(of: panel, matching: find.byType(SailButton)), findsNothing);
  });

  testWidgets('the row "…" holds View Details and Copy hash', (tester) async {
    await _pump(tester);

    await tester.tap(find.byType(SailRowMenuButton));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('View Details'), findsOneWidget);
    expect(find.text('Copy hash'), findsOneWidget);

    await tester.tap(find.text('View Details'));
    await tester.pumpAndSettle();
    expect(find.byType(SailSidePanel), findsOneWidget);
  });
}
