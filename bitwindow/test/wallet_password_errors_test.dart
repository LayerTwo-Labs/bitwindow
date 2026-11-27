import 'dart:io';

import 'package:bitwindow/dialogs/change_password_dialog.dart';
import 'package:bitwindow/dialogs/remove_encryption_dialog.dart';
import 'package:bitwindow/pages/remove_encryption_page.dart';
import 'package:connectrpc/connect.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';

import 'test_utils.dart';

class _RefusingWalletReader extends WalletReaderProvider {
  _RefusingWalletReader(this.failure) : super(Directory.systemTemp);

  final Object failure;

  @override
  Future<void> changePassword(String oldPassword, String newPassword) async => throw failure;

  @override
  Future<void> removeEncryption(String password) async => throw failure;
}

final _wrongPassword = ConnectException(Code.unauthenticated, 'incorrect password');
final _unreadable = ConnectException(Code.internal, 'read wallet file: permission denied');

void _useReader(Object failure) {
  GetIt.I.registerSingleton<WalletReaderProvider>(_RefusingWalletReader(failure));
  addTearDown(() => GetIt.I.unregister<WalletReaderProvider>());
}

Future<void> _press(WidgetTester tester, String label) async {
  final button = tester.widget<SailButton>(find.widgetWithText(SailButton, label).first);
  await tester.runAsync(() async => button.onPressed!());
  await tester.pump();
}

Future<void> _openDialog(WidgetTester tester, Future<bool?> Function(BuildContext) show) async {
  await tester.pumpSailPage(
    Builder(
      builder: (context) => TextButton(onPressed: () => show(context), child: const Text('open')),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _changePassword(WidgetTester tester) async {
  await _openDialog(tester, ChangePasswordDialog.show);
  final fields = find.descendant(of: find.byType(ChangePasswordDialog), matching: find.byType(TextField));
  await tester.enterText(fields.at(0), 'old-password');
  await tester.enterText(fields.at(1), 'new-password');
  await tester.enterText(fields.at(2), 'new-password');
  await _press(tester, 'Change Password');
}

Future<void> _removeEncryption(WidgetTester tester) async {
  await _openDialog(tester, RemoveEncryptionDialog.show);
  final field = find.descendant(of: find.byType(RemoveEncryptionDialog), matching: find.byType(TextField));
  await tester.enterText(field, 'old-password');
  await _press(tester, 'Remove Encryption');
}

Future<void> _removeEncryptionPage(WidgetTester tester) async {
  await tester.pumpSailPage(const RemoveEncryptionPage());
  await tester.enterText(find.byType(TextField), 'old-password');
  await _press(tester, 'REMOVE ENCRYPTION');
}

void main() {
  setUpAll(registerTestDependencies);

  group('Change password', () {
    testWidgets('a wrong current password says so', (tester) async {
      _useReader(_wrongPassword);
      await _changePassword(tester);

      expect(find.text('Incorrect current password'), findsOneWidget);
    });

    testWidgets('another failure shows its reason', (tester) async {
      _useReader(_unreadable);
      await _changePassword(tester);

      expect(find.text('Error changing password: read wallet file: permission denied'), findsOneWidget);
    });
  });

  group('Remove encryption dialog', () {
    testWidgets('a wrong password says so', (tester) async {
      _useReader(_wrongPassword);
      await _removeEncryption(tester);

      expect(find.text('Incorrect password'), findsOneWidget);
    });

    testWidgets('another failure shows its reason', (tester) async {
      _useReader(_unreadable);
      await _removeEncryption(tester);

      expect(find.text('Error removing encryption: read wallet file: permission denied'), findsOneWidget);
    });
  });

  group('Remove encryption page', () {
    testWidgets('a wrong password says so', (tester) async {
      _useReader(_wrongPassword);
      await _removeEncryptionPage(tester);

      expect(find.text('Incorrect password'), findsOneWidget);
    });

    testWidgets('another failure shows its reason', (tester) async {
      _useReader(_unreadable);
      await _removeEncryptionPage(tester);

      expect(find.text('Error removing encryption: read wallet file: permission denied'), findsOneWidget);
    });
  });
}
