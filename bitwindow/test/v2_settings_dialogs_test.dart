import 'package:bitwindow/dialogs/change_password_dialog.dart';
import 'package:bitwindow/dialogs/merkle_tree_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sail_ui/sail_ui.dart';

import 'test_utils.dart';

Finder _button(String label) => find.byWidgetPredicate((w) => w is SailButton && w.label == label);

Future<void> _open(WidgetTester tester, Widget dialog) async {
  await tester.pumpSailPage(
    Builder(
      builder: (context) => Center(
        child: SailButton(
          label: 'open',
          onPressed: () async => showThemedDialog(context: context, builder: (_) => dialog),
        ),
      ),
    ),
  );
  await tester.tap(_button('open'));
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets('the change password dialog has one full-width action and a × in place of Cancel', (tester) async {
    await _open(tester, const ChangePasswordDialog());

    expect(_button('Cancel'), findsNothing);
    expect(find.byType(SailDialogActionButton), findsOneWidget);
    expect(_button('Change Password'), findsOneWidget);

    await tester.tap(find.byType(SailIconBoxButton));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(ChangePasswordDialog), findsNothing);
  });

  testWidgets('the merkle tree dialog keeps only the ×', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    await _open(tester, const MerkleTreeDialog());

    expect(_button('Close'), findsNothing);
    final close = find.byType(SailIconBoxButton);
    expect(close, findsOneWidget);

    await tester.tap(close);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(MerkleTreeDialog), findsNothing);
  });
}
