import 'package:bitwindow/dialogs/merkle_tree_dialog.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';

import 'mocks/api_mock.dart';
import 'test_utils.dart';

final _txid = 'ab' * 32;
final _root = 'cd' * 32;

class _Utils extends MockUtilsAPI {
  @override
  Future<CalculateMerkleTreeResponse> calculateMerkleTree(List<String> txids, {bool showRCB = true}) async {
    return CalculateMerkleTreeResponse(
      merkleRoot: _root,
      formattedText: 'tree of ${txids.length}',
      levels: [
        MerkleTreeLevel(level: 0, hashes: txids),
        MerkleTreeLevel(level: 1, hashes: [_root]),
      ],
    );
  }
}

class _Bitwindow extends MockAPI {
  _Bitwindow() : super(binaryType: BinaryType.BINARY_TYPE_BITWINDOWD);

  final _utils = _Utils();

  @override
  _Utils get utils => _utils;
}

void main() {
  setUp(() async {
    await GetIt.I.reset();
    GetIt.I.registerSingleton<BitwindowRPC>(_Bitwindow());
    await registerTestDependencies();
  });

  tearDown(() => GetIt.I.reset());

  Future<void> pump(WidgetTester tester, {String? expectedRoot}) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpSailPage(MerkleTreeDialog(initialTxids: [_txid], expectedRoot: expectedRoot));
    await tester.pumpAndSettle();
  }

  testWidgets('the dialog has a × in the head and Display RCB at the foot', (tester) async {
    await pump(tester);

    expect(tester.takeException(), isNull);
    expect(find.byWidgetPredicate((w) => w is SailIconBoxButton && w.icon == SailSVGAsset.x), findsOneWidget);
    expect(find.text('Close'), findsNothing);
    expect(find.text('Display RCB'), findsOneWidget);
    expect(find.byType(SailButton), findsOneWidget);
  });

  testWidgets('the tree heading has a copy icon, and the root sits under the tree', (tester) async {
    await pump(tester);

    final heading = tester.getRect(find.text('Merkle Tree').last);
    final copy = tester.getRect(find.byType(SailDetailCopyIcon));
    expect(copy.center.dy, closeTo(heading.center.dy, 4));
    expect(copy.left, greaterThan(heading.right));
    expect(tester.getRect(find.text(_root)).top, greaterThan(tester.getRect(find.text('tree of 1')).bottom));
  });

  testWidgets('a matching root shows a green line and the two roots in a grey group', (tester) async {
    await pump(tester, expectedRoot: _root);

    final theme = SailTheme.of(tester.element(find.text('Display RCB')));
    expect(tester.widget<Text>(find.text('Merkle root matches block header ✓')).style?.color, theme.colors.success);
    expect(find.descendant(of: find.byType(SailDetailGroup), matching: find.text('Expected:')), findsOneWidget);
    expect(find.descendant(of: find.byType(SailDetailGroup), matching: find.text('Calculated:')), findsOneWidget);
  });

  testWidgets('a different root shows a red mismatch line', (tester) async {
    await pump(tester, expectedRoot: 'ef' * 32);

    final theme = SailTheme.of(tester.element(find.text('Display RCB')));
    expect(tester.widget<Text>(find.text('Merkle root MISMATCH ✗')).style?.color, theme.colors.error);
  });
}
