import 'package:sidechain_core/providers/network_scoped.dart';

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:sidechain_core/classes/rpc_connection.dart';
import 'package:sidechain_core/gen/wallet/v1/wallet.pb.dart';
import 'package:sidechain_core/providers/sync_provider.dart';
import 'package:sidechain_core/providers/wallet_reader_provider.dart';
import 'package:sidechain_core/rpcs/bitwindow_api.dart';

/// Whether the chain holds other coins for [check] than the app shows.
bool fundingChanged(Cheque check, CheckChequeFundingResponse chain) {
  final swept = check.sweptTxid.isNotEmpty;
  if (chain.fundedTxids.isEmpty) {
    return !swept && check.fundedTxids.isNotEmpty;
  }
  return swept ||
      check.funded != chain.funded ||
      check.actualAmountSats != chain.actualAmountSats ||
      !setEquals(check.fundedTxids.toSet(), chain.fundedTxids.toSet());
}

class CheckProvider extends ChangeNotifier implements NetworkScoped {
  @override
  Future<void> onNetworkChanged() async {
    clear();
  }

  final Logger log = Logger(level: Level.debug);
  final BitwindowRPC _bitwindowRPC = GetIt.I.get<BitwindowRPC>();
  final WalletReaderProvider _walletReader = GetIt.I.get<WalletReaderProvider>();
  SyncProvider get _syncProvider => GetIt.I.get<SyncProvider>();

  List<Cheque> _checks = [];
  bool _isLoading = false;
  String? modelError;
  (List<Cheque>, String?) _shown = (const [], null);

  List<Cheque> get checks => _checks;
  bool get isLoading => _isLoading;

  Timer? _unfundedPollTimer;
  final SyncedTipWatch _tip = SyncedTipWatch();

  CheckProvider() {
    _syncProvider.addListener(_onNewBlock);
    _walletReader.addListener(_onWalletChanged);
    _init();
  }

  Future<void> _init() async {
    await fetch();
    _startUnfundedPolling();
  }

  void _startUnfundedPolling() {
    _unfundedPollTimer?.cancel();
    _unfundedPollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (_checks.isEmpty) {
        if (modelError != null) {
          await fetch();
        }
        return;
      }
      final unfunded = _checks.where((c) => !c.funded && c.sweptTxid.isEmpty).toList();
      if (unfunded.isEmpty) {
        return;
      }
      await _read((walletId) => _readFunding(walletId, unfunded));
    });
  }

  /// Reads the coins of each check in [checks] from the chain. The server
  /// stores what it finds, so one new list holds each change.
  Future<void> _readFunding(String walletId, List<Cheque> checks) async {
    final chain = await Future.wait(
      checks.map((check) => _bitwindowRPC.wallet.checkChequeFunding(walletId, check.id.toInt())),
    );
    for (var i = 0; i < checks.length; i++) {
      if (fundingChanged(checks[i], chain[i])) {
        _checks = await _bitwindowRPC.wallet.listCheques(walletId);
        return;
      }
    }
  }

  Future<void> _read(Future<void> Function(String walletId) read) async {
    final walletId = _walletReader.activeWalletId;
    if (walletId == null) {
      return;
    }

    _isLoading = true;
    try {
      await read(walletId);
      modelError = null;
    } catch (e) {
      if (e.toString() != modelError && !isExpectedBootError(e)) {
        log.e('Failed to read checks: $e');
      }
      modelError = e.toString();
    } finally {
      _isLoading = false;
      _show();
    }
  }

  void _show() {
    final (checks, error) = _shown;
    if (error == modelError && listEquals(checks, _checks)) {
      return;
    }
    _shown = (_checks, modelError);
    notifyListeners();
  }

  void _onNewBlock() {
    if (_tip.moved(_syncProvider, synced: _syncProvider.isSynced)) {
      fetch();
    }
  }

  void _onWalletChanged() {
    clear();
    fetch();
  }

  void clear() {
    _checks = [];
    _show();
  }

  Future<void> fetch() => _read((walletId) async {
    _checks = await _bitwindowRPC.wallet.listCheques(walletId);
    _show();
    await _readFunding(walletId, _checks);
  });

  Future<Cheque> createCheck(int expectedAmountSats) async {
    final walletId = _walletReader.activeWalletId;
    if (walletId == null) {
      throw Exception('No active wallet');
    }
    final resp = await _bitwindowRPC.wallet.createCheque(walletId, expectedAmountSats);
    final check = await _bitwindowRPC.wallet.getCheque(walletId, resp.id.toInt());

    _checks = [check, ..._checks];
    _show();
    return check;
  }

  Future<Cheque> getCheck(int id) async {
    final walletId = _walletReader.activeWalletId;
    if (walletId == null) {
      throw Exception('No active wallet');
    }
    return _bitwindowRPC.wallet.getCheque(walletId, id);
  }

  Future<String> sweepCheck(String privateKeyWif, String destinationAddress, int feeSatPerVbyte) async {
    final walletId = _walletReader.activeWalletId;
    if (walletId == null) {
      throw Exception('No active wallet');
    }
    final result = await _bitwindowRPC.wallet.sweepCheque(
      walletId,
      privateKeyWif,
      destinationAddress,
      feeSatPerVbyte,
    );
    await fetch();
    return result.txid;
  }

  Future<bool> deleteCheck(int id) async {
    try {
      final walletId = _walletReader.activeWalletId;
      if (walletId == null) {
        throw Exception('No active wallet');
      }
      await _bitwindowRPC.wallet.deleteCheque(walletId, id);
      _checks = _checks.where((c) => c.id != id).toList();
      _show();
      return true;
    } catch (e) {
      log.e('Failed to delete check: $e');
      modelError = e.toString();
      _show();
      return false;
    }
  }

  @override
  void dispose() {
    _syncProvider.removeListener(_onNewBlock);
    _walletReader.removeListener(_onWalletChanged);
    _unfundedPollTimer?.cancel();
    super.dispose();
  }
}
