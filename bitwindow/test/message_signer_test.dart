import 'dart:io';

import 'package:bitwindow/pages/message_signer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';

import 'mocks/api_mock.dart';
import 'test_utils.dart';

Future<void> _pumpSigner(WidgetTester tester, Size windowSize) async {
  await registerTestDependencies();
  if (!GetIt.I.isRegistered<WalletReaderProvider>()) {
    GetIt.I.registerSingleton<WalletReaderProvider>(WalletReaderProvider(Directory.systemTemp)..activeWalletId = 'w1');
  }
  await tester.pumpSailPage(const MessageSigner());
  await tester.binding.setSurfaceSize(windowSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the signer fills its window and has no dialog', (tester) async {
    await _pumpSigner(tester, const Size(800, 574));

    expect(tester.takeException(), isNull);
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(SailModal), findsNothing);
    expect(tester.getSize(find.byType(MessageSigner)), tester.getSize(find.byType(Scaffold)));
  });

  testWidgets('the signer has no close button to empty its window', (tester) async {
    await _pumpSigner(tester, const Size(800, 574));

    final closeButtons = find.byWidgetPredicate((w) => w is SailButton && w.icon == SailSVGAsset.iconClose);
    expect(closeButtons, findsNothing);
  });

  testWidgets('the sign tab signs in a small window', (tester) async {
    await _pumpSigner(tester, const Size(600, 374));

    expect(tester.takeException(), isNull);
    final signButton = find.widgetWithText(SailButton, 'Sign Message').last;
    await tester.ensureVisible(signButton);
    await tester.tap(signButton);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('mock_signature'), findsOneWidget);
  });

  for (final (name, valid, result) in [
    ('a valid', true, 'Message verified'),
    ('an invalid', false, 'Invalid signature'),
  ]) {
    testWidgets('$name result shows as a status pill under the verify button', (tester) async {
      await _pumpSigner(tester, const Size(800, 574));
      final api = GetIt.I.get<BitwindowRPC>().wallet as MockWalletAPI;
      api.verifyResult = valid;
      addTearDown(() => api.verifyResult = true);
      await tester.tap(find.text('Verify Message').first);
      await tester.pumpAndSettle();

      final button = find.widgetWithText(SailButton, 'Verify Message').last;
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();

      _expectUnder(tester, find.text(result), button);
      final pill = tester.widget<SailStatusPill>(find.byType(SailStatusPill));
      expect(pill.tone, valid ? SailStatusTone.success : SailStatusTone.error);
    });
  }

  testWidgets('a verify error shows under the verify button', (tester) async {
    await _pumpSigner(tester, const Size(800, 574));
    GetIt.I.get<WalletReaderProvider>().activeWalletId = null;
    addTearDown(() => GetIt.I.get<WalletReaderProvider>().activeWalletId = 'w1');
    await tester.tap(find.text('Verify Message').first);
    await tester.pumpAndSettle();

    final button = find.widgetWithText(SailButton, 'Verify Message').last;
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();

    _expectUnder(tester, find.textContaining('No active wallet'), button);
  });

  testWidgets('a changed message drops the verify result', (tester) async {
    await _pumpSigner(tester, const Size(800, 574));
    await tester.tap(find.text('Verify Message').first);
    await tester.pumpAndSettle();
    final button = find.widgetWithText(SailButton, 'Verify Message').last;
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('Message verified'), findsOneWidget);

    await tester.enterText(find.byType(EditableText).at(1), 'another message');
    await tester.pumpAndSettle();

    expect(find.text('Message verified'), findsNothing);
  });

  testWidgets('a moved caret keeps the signature and the verify result', (tester) async {
    await _pumpSigner(tester, const Size(800, 574));
    await tester.enterText(find.byType(EditableText).at(1), 'my message');
    final sign = find.widgetWithText(SailButton, 'Sign Message').last;
    await tester.ensureVisible(sign);
    await tester.tap(sign);
    await tester.pumpAndSettle();

    final message = tester.widget<EditableText>(find.byType(EditableText).at(1)).controller;
    message.selection = const TextSelection(baseOffset: 0, extentOffset: 2);
    await tester.pumpAndSettle();

    expect(find.text('mock_signature'), findsOneWidget);

    await tester.tap(find.text('Verify Message').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).at(1), 'my message');
    final verify = find.widgetWithText(SailButton, 'Verify Message').last;
    await tester.ensureVisible(verify);
    await tester.tap(verify);
    await tester.pumpAndSettle();

    final checked = tester.widget<EditableText>(find.byType(EditableText).at(1)).controller;
    checked.selection = const TextSelection(baseOffset: 0, extentOffset: 2);
    await tester.pumpAndSettle();

    expect(find.text('Message verified'), findsOneWidget);
  });

  testWidgets('a changed message drops the signature', (tester) async {
    await _pumpSigner(tester, const Size(800, 574));
    final button = find.widgetWithText(SailButton, 'Sign Message').last;
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('mock_signature'), findsOneWidget);

    await tester.enterText(find.byType(EditableText).at(1), 'another message');
    await tester.pumpAndSettle();

    expect(find.text('mock_signature'), findsNothing);
  });

  testWidgets('an error shows without the exception name', (tester) async {
    await _pumpSigner(tester, const Size(800, 574));
    GetIt.I.get<WalletReaderProvider>().activeWalletId = null;
    addTearDown(() => GetIt.I.get<WalletReaderProvider>().activeWalletId = 'w1');
    final button = find.widgetWithText(SailButton, 'Sign Message').last;
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(find.text('No active wallet'), findsOneWidget);
  });

  testWidgets('each tab has one full-width button and the tabs have no icons', (tester) async {
    await _pumpSigner(tester, const Size(800, 720));

    final card = tester.getRect(find.byType(SailCard));
    final sign = tester.getRect(find.widgetWithText(SailButton, 'Sign Message').last);
    expect(sign.width, closeTo(card.width - 2 * SailStyleValues.padding16, 2));
    expect(tester.widget<InlineTabBar>(find.byType(InlineTabBar)).tabs.map((t) => t.icon), everyElement(isNull));
  });

  testWidgets('the verify help text ends with a full sentence', (tester) async {
    await _pumpSigner(tester, const Size(800, 574));
    await tester.tap(find.text('Verify Message').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('cannot prove sendership of any transaction!'), findsOneWidget);
  });
}

void _expectUnder(WidgetTester tester, Finder finder, Finder button) {
  expect(finder, findsOneWidget);
  final rect = tester.getRect(finder);
  final buttonRect = tester.getRect(button);
  expect(rect.top, greaterThan(buttonRect.bottom));
  expect(rect.top, lessThan(buttonRect.bottom + 32));
  expect(rect.left, inInclusiveRange(buttonRect.left, buttonRect.left + 32));
}
