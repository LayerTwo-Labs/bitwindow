import 'dart:io';

import 'package:connectrpc/connect.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:sail_ui/pages/unlock_wallet_page.dart';
import 'package:sail_ui/sail_ui.dart';

class _FakeWalletReader extends WalletReaderProvider {
  _FakeWalletReader(this.result) : super(Directory.systemTemp);

  final Object result;

  @override
  Future<bool> unlockWallet(String password) async {
    final r = result;
    if (r is bool) {
      return r;
    }
    throw r;
  }
}

Widget _app(Widget Function(BuildContext) builder) {
  return MaterialApp(
    home: SailTheme(
      data: SailThemeData.lightTheme(SailColorScheme.orange, true, SailFontValues.inter),
      child: Builder(builder: (context) => Scaffold(body: builder(context))),
    ),
  );
}

Future<void> _press(WidgetTester tester, String label) async {
  final button = tester.widget<SailButton>(find.widgetWithText(SailButton, label).first);
  await tester.runAsync(() async => button.onPressed!());
  await tester.pump();
}

void _useReader(Object result) {
  GetIt.I.registerSingleton<WalletReaderProvider>(_FakeWalletReader(result));
  addTearDown(() => GetIt.I.unregister<WalletReaderProvider>());
}

final _unreadable = ConnectException(Code.internal, 'read wallet file: permission denied');

void main() {
  setUpAll(() {
    if (!GetIt.I.isRegistered<Logger>()) {
      GetIt.I.registerSingleton<Logger>(Logger(level: Level.warning));
    }
  });

  group('showUnlockWalletDialog', () {
    Future<bool?> open(WidgetTester tester) async {
      bool? unlocked;
      await tester.pumpWidget(
        _app(
          (context) => TextButton(
            onPressed: () async => unlocked = await showUnlockWalletDialog(context, message: 'Enter your password'),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'hunter2');
      await _press(tester, 'Unlock');
      await tester.pump(const Duration(milliseconds: 100));
      return unlocked;
    }

    testWidgets('a wrong password shows the wrong password text', (tester) async {
      _useReader(false);
      await open(tester);

      expect(find.text('Incorrect password'), findsOneWidget);
      expect(find.text('Unlock Wallet'), findsOneWidget, reason: 'the dialog stays open for another try');
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a failure that is not a wrong password shows its reason', (tester) async {
      _useReader(_unreadable);
      await open(tester);

      expect(find.text('Error unlocking wallet: read wallet file: permission denied'), findsOneWidget);
      expect(find.text('Incorrect password'), findsNothing);
      final unlock = tester.widget<SailButton>(find.widgetWithText(SailButton, 'Unlock').first);
      expect(unlock.loading, isFalse, reason: 'the button must not spin after a failure');
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a right password closes the dialog and returns true', (tester) async {
      _useReader(true);
      final unlocked = await open(tester);
      await tester.pumpAndSettle();

      expect(find.text('Unlock Wallet'), findsNothing);
      expect(unlocked, isTrue);
    });
  });

  group('UnlockWalletPage', () {
    Future<void> submit(WidgetTester tester) async {
      await tester.pumpWidget(_app((_) => const UnlockWalletPage()));
      await tester.enterText(find.byType(TextField), 'hunter2');
      await tester.pump();
      await _press(tester, 'Decrypt Wallet');
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('a failure that is not a wrong password shows its reason', (tester) async {
      _useReader(_unreadable);
      await submit(tester);

      expect(find.text('Error unlocking wallet: read wallet file: permission denied'), findsOneWidget);
      expect(find.text('Incorrect password. Please try again.'), findsNothing);
    });

    testWidgets('a wrong password asks again', (tester) async {
      _useReader(false);
      await submit(tester);

      expect(find.text('Incorrect password. Please try again.'), findsOneWidget);
    });
  });
}
