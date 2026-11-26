import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:sail_ui/pages/router.gr.dart' show UnlockWalletRoute;
import 'package:sidechain_core/providers/wallet_reader_provider.dart';

final _openUnlockPages = Expando<Future<void>>();

/// Opens the unlock page on [router]. A call while the page is open waits for that page.
Future<void> openUnlockPage(StackRouter router) => _openUnlockPages[router] ??= router
    .push<void>(UnlockWalletRoute())
    .whenComplete(() => _openUnlockPages[router] = null);

/// Opens the unlock page each time the backend reports a locked wallet.
class UnlockPrompt {
  final WalletReaderProvider walletReader;
  final StackRouter router;

  UnlockPrompt({required this.walletReader, required this.router});

  void start() {
    walletReader.addListener(_onChange);
    _onChange();
  }

  void dispose() {
    walletReader.removeListener(_onChange);
  }

  void _onChange() {
    if (walletReader.needsPassword) {
      unawaited(openUnlockPage(router));
    }
  }
}
