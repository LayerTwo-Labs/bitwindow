import 'package:bitwindow/pages/explorer/block_explorer_dialog.dart';
import 'package:bitwindow/providers/blockchain_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';

import 'test_utils.dart';

class _FixedBlocks extends BlockchainProvider {
  @override
  Future<void> fetch() async {}
}

class _Orchestrator implements OrchestratorRPC {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Block _block(int height) => Block(
  height: height,
  hash: 'a$height'.padRight(64, '0'),
  previousBlockHash: 'b$height'.padRight(64, '0'),
  merkleRoot: 'c$height'.padRight(64, '0'),
  bits: '207fffff',
);

void main() {
  setUp(() async {
    await GetIt.I.reset();
    GetIt.I.registerSingleton<OrchestratorRPC>(_Orchestrator());
    GetIt.I.registerLazySingleton<BlockchainProvider>(() => _FixedBlocks()..blocks = [_block(3), _block(2), _block(1)]);
  });

  tearDown(() => GetIt.I.reset());

  for (final height in [380.0, 300.0]) {
    testWidgets('the block cards fit a ${height.toInt()} px pane', (tester) async {
      await tester.pumpSailPage(SizedBox(height: height, child: const BlockExplorerDialog()));
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(find.text('3'), findsOneWidget);
    });
  }

  testWidgets('the desktop lists the blocks as table rows, and a row click opens Block Details', (tester) async {
    await tester.pumpSailPage(const SizedBox(height: 600, child: BlockExplorerDialog()));
    await tester.pump(const Duration(milliseconds: 300));

    final headers = tester.widgetList<SailTableHeaderCell>(find.byType(SailTableHeaderCell)).map((h) => h.name);
    expect(headers, ['Height', 'Hash', 'Prev Hash', 'Merkle Root', 'Bits']);
    expect(find.byType(SailSidePanel), findsNothing);

    await tester.tap(find.text('3'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    final panel = find.byType(SailSidePanel);
    expect(find.descendant(of: panel, matching: find.text('Block Details')), findsOneWidget);
    expect(find.descendant(of: panel, matching: find.text('a3'.padRight(64, '0'))), findsOneWidget);
    expect(find.descendant(of: panel, matching: find.widgetWithText(SailButton, 'View Merkle Tree')), findsOneWidget);
  });

  test('a long value keeps both ends', () {
    final hash = '${'1' * 20}${'0' * 24}${'2' * 20}';
    expect(middleEllipsis(hash), '${'1' * 20}…${'2' * 20}');
    expect(middleEllipsis('0x207fffff'), '0x207fffff');
  });
}
