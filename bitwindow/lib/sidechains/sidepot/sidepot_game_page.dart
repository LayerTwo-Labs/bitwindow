import 'dart:async';

import 'package:bitwindow/sidechains/sidepot/sidepot_pending.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';

/// The Sidepot key game, read from this machine's own Sidepot node.
///
/// The node keeps the game account (its key comes from the wallet the node was
/// started with) and signs each move. A move is a piece of data in an eCash
/// transaction, which the BitWindow wallet sends and pays the network fee for.
class SidepotGamePage extends StatefulWidget {
  const SidepotGamePage({super.key});

  @override
  State<SidepotGamePage> createState() => _SidepotGamePageState();
}

const _coin = 100000000;

String _ecx(num sats) {
  final negative = sats < 0;
  final whole = sats.abs() ~/ _coin;
  var part = (sats.abs() % _coin).toInt().toString().padLeft(8, '0');
  part = part.replaceFirst(RegExp(r'0+$'), '');
  return '${negative ? '-' : ''}$whole${part.isEmpty ? '' : '.$part'}';
}

/// A typed amount of ECX in sats, or null when it isn't one.
int? _sats(String text) {
  final match = RegExp(r'^(\d{0,8})(?:[.,](\d{0,8}))?$').firstMatch(text.trim());
  if (match == null || ((match.group(1) ?? '').isEmpty && (match.group(2) ?? '').isEmpty)) {
    return null;
  }
  final whole = int.parse((match.group(1) ?? '').isEmpty ? '0' : match.group(1)!);
  final part = int.parse((match.group(2) ?? '').padRight(8, '0'));
  return whole * _coin + part;
}

class _SidepotGamePageState extends State<SidepotGamePage> {
  SidepotRPC get _rpc => GetIt.I.get<SidepotRPC>();

  Timer? _timer;
  bool _reading = false;
  Map<String, dynamic>? _game;
  Map<String, dynamic>? _account;
  String? _readError;

  /// The moves this install sent whose outcome is not final yet, for every game account it has used.
  List<PendingMove> _pending = [];
  bool _pendingLoaded = false;

  /// This wallet's eCash transactions that are in a block, and the node's waiting Sidepot transactions.
  Set<String> _mined = {};
  Set<String>? _sidepotMempool;

  final _keys = TextEditingController(text: '1');
  final _move = TextEditingController();
  final _cashout = TextEditingController();

  String? _busy;
  String? _said;
  bool _saidBad = false;

  @override
  void initState() {
    super.initState();
    _keys.addListener(_redraw);
    unawaited(_loadPending().then((_) => _read()));
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => unawaited(_read()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _keys.dispose();
    _move.dispose();
    _cashout.dispose();
    super.dispose();
  }

  void _redraw() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _read() async {
    if (_reading) {
      return;
    }
    _reading = true;
    try {
      final game = await _rpc.callRAW('game_state');
      final account = await _rpc.callRAW('game_my_account');
      final mined = await _minedTxids();
      final mempool = await _waitingSidepotTxids();
      if (!mounted) {
        return;
      }
      setState(() {
        _game = game is Map ? Map<String, dynamic>.from(game) : null;
        _account = account is Map ? Map<String, dynamic>.from(account) : null;
        _mined = mined ?? _mined;
        _sidepotMempool = mempool;
        _readError = null;
      });
      _settlePending();
    } catch (error) {
      if (mounted) {
        setState(() {
          _readError = '$error';
          _game = null;
          _account = null;
        });
      }
    } finally {
      _reading = false;
    }
  }

  /// The game as of the newest eCash block the node has read, when it gives one.
  Map<String, dynamic>? get _now {
    final game = _game;
    if (game == null) {
      return null;
    }
    final preview = game['preview'];
    return preview is Map ? Map<String, dynamic>.from(preview) : game;
  }

  Map<String, dynamic>? get _mine {
    final account = _account;
    if (account == null) {
      return null;
    }
    final preview = account['preview'];
    return preview is Map ? Map<String, dynamic>.from(preview) : account;
  }

  int _int(Map<String, dynamic>? from, String name) => (from?[name] as num?)?.toInt() ?? 0;

  String get _address => '${_account?['address'] ?? ''}';

  /// This game account's moves among the pending ones.
  List<PendingMove> get _myPending => _pending.where((m) => m.account == _address).toList();

  PendingFacts get _facts => PendingFacts(
    confirmedNonce: _int(_account, 'nonce'),
    previewNonce: _int(_mine, 'nonce'),
    clock: _int(_now, 'clock'),
    height: _int(_now, 'l1_height'),
    minedTxids: _mined,
    sidepotMempool: _sidepotMempool,
  );

  ClientSettings get _settings => GetIt.I.get<ClientSettings>();

  Future<void> _loadPending() async {
    try {
      final saved = await _settings.getValue(SidepotPendingSetting());
      _pending = [...SidepotPendingSetting.decode(saved.value), ..._pending];
    } catch (_) {
      // Without the saved list the moves sent from now on are still shown.
    }
    _pendingLoaded = true;
  }

  void _savePending() {
    if (!_pendingLoaded) {
      return;
    }
    unawaited(
      _settings
          .setValue(SidepotPendingSetting(newValue: SidepotPendingSetting.encode(_pending)))
          .then<void>((_) {}, onError: (_) {}),
    );
  }

  void _addPending(PendingMove move) {
    setState(() => _pending = [..._pending, move]);
    _savePending();
  }

  void _dismiss(PendingMove move) {
    setState(() => _pending = _pending.where((m) => m.txid != move.txid).toList());
    _savePending();
  }

  /// Drops this account's moves that are final, and notes the ones newly seen in an eCash block.
  void _settlePending() {
    if (_account == null || _address.isEmpty || _myPending.isEmpty) {
      return;
    }
    final others = _pending.where((m) => m.account != _address).toList();
    final mine = settled(_myPending, _facts);
    final next = [...others, ...mine];
    if (SidepotPendingSetting.encode(next) == SidepotPendingSetting.encode(_pending)) {
      return;
    }
    setState(() => _pending = next);
    _savePending();
  }

  /// This wallet's eCash transactions that are in a block, or null when there is nothing to look for or the
  /// wallet could not be read.
  Future<Set<String>?> _minedTxids() async {
    final walletId = _walletId;
    if (walletId == null || !_pending.any((m) => m.kind != PendingKind.fund && m.minedSeenAt == 0)) {
      return null;
    }
    try {
      final listed = await GetIt.I.get<OrchestratorRPC>().wallet.listTransactions(walletId: walletId);
      return {
        for (final tx in listed.transactions)
          if (tx.confirmations > 0) tx.txid,
      };
    } catch (_) {
      return null;
    }
  }

  /// The Sidepot transactions the node holds for the next Sidepot block, or null when it could not say.
  Future<Set<String>?> _waitingSidepotTxids() async {
    if (!_pending.any((m) => m.kind == PendingKind.fund)) {
      return null;
    }
    try {
      final listed = await _rpc.callRAW('list_mempool');
      if (listed is! List) {
        return null;
      }
      return {
        for (final tx in listed)
          if (tx is Map && tx['txid'] is String) tx['txid'] as String,
      };
    } catch (_) {
      return null;
    }
  }

  /// A signed move's field, as the node returned it.
  int _field(dynamic signed, String name) => signed is Map ? (signed[name] as num?)?.toInt() ?? 0 : 0;

  String? get _walletId => GetIt.I.get<WalletReaderProvider>().activeWalletId;

  Future<void> _run(String what, Future<String> Function() action) async {
    if (_busy != null) {
      return;
    }
    setState(() {
      _busy = what;
      _said = null;
    });
    try {
      final said = await action();
      if (mounted) {
        setState(() {
          _said = said;
          _saidBad = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _said = '$error'.replaceFirst('Exception: ', '');
          _saidBad = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = null);
      }
      unawaited(_read());
    }
  }

  /// Sends one signed move as the data of an eCash transaction from the BitWindow wallet.
  Future<String> _carry(dynamic signed) async {
    final entry = signed is Map ? signed['entry'] : null;
    if (entry is! String || entry.isEmpty) {
      throw Exception('The node did not sign the move.');
    }
    final walletId = _walletId;
    if (walletId == null) {
      throw Exception('No BitWindow wallet is open to pay the eCash network fee.');
    }
    final wallet = GetIt.I.get<OrchestratorRPC>().wallet;
    final sent = await wallet.sendTransaction(walletId: walletId, destinations: {}, opReturnHex: entry);
    return sent.txid;
  }

  Future<void> _buy() => _run('buy', () async {
    final count = int.tryParse(_keys.text.trim());
    if (count == null || count < 1 || count > 1000) {
      throw Exception('Give a number of keys from 1 to 1000.');
    }
    final signed = await _rpc.callRAW('game_sign_buy', [count, null]);
    final txid = await _carry(signed);
    _addPending(
      PendingMove(
        kind: PendingKind.buy,
        account: _address,
        txid: txid,
        nonce: _field(signed, 'nonce'),
        expires: _field(signed, 'expires'),
        keys: count,
        maxPriceSats: _field(signed, 'max_price_sats'),
      ),
    );
    return 'Buy sent in eCash transaction $txid. It counts once that transaction is in a block.';
  });

  Future<void> _cashOut() => _run('cashout', () async {
    final typed = _cashout.text.trim();
    final amount = typed.isEmpty ? 0 : _sats(typed);
    if (amount == null) {
      throw Exception('Give the amount in ECX, or leave it empty for everything.');
    }
    final signed = await _rpc.callRAW('game_sign_cashout', [amount, null]);
    final txid = await _carry(signed);
    _addPending(
      PendingMove(
        kind: PendingKind.cashout,
        account: _address,
        txid: txid,
        nonce: _field(signed, 'nonce'),
        expires: _field(signed, 'expires'),
        amountSats: amount,
      ),
    );
    return 'Cash-out sent in eCash transaction $txid. The coins arrive in the Sidepot balance of this wallet.';
  });

  Future<void> _moveToGame() => _run('move', () async {
    final amount = _sats(_move.text);
    if (amount == null || amount <= 0) {
      throw Exception('Give the amount in ECX.');
    }
    final txid = await _rpc.callRAW('game_fund', [amount, null, null]);
    if (txid is String && txid.isNotEmpty) {
      _addPending(PendingMove(kind: PendingKind.fund, account: _address, txid: txid, amountSats: amount));
    }
    return 'Moved in Sidepot transaction $txid. The game account is credited with the next Sidepot block.';
  });

  /// What a pending move is, in words.
  String _moveTitle(PendingMove move, int price) => switch (move.kind) {
    PendingKind.buy =>
      'Buy ${move.keys} ${move.keys == 1 ? 'key' : 'keys'}: about ${_ecx(move.keys * price)} ECX, at most ${_ecx(move.keys * move.maxPriceSats)}',
    PendingKind.cashout => move.amountSats == 0 ? 'Cash out everything' : 'Cash out ${_ecx(move.amountSats)} ECX',
    PendingKind.fund => 'Move ${_ecx(move.amountSats)} ECX into the game',
  };

  /// How far a pending move has got, in words.
  String _stageText(PendingMove move, PendingStage stage) => switch (stage) {
    PendingStage.waiting =>
      move.kind == PendingKind.fund ? 'Waiting for the next Sidepot block.' : 'Waiting for an eCash block.',
    PendingStage.mined => 'In an eCash block. Waiting for the node to count it.',
    PendingStage.counted => 'Counted. The next Sidepot block makes it final.',
    PendingStage.passed => 'Settled: a later move of yours has counted, so this one can no longer change anything.',
    PendingStage.rejected => 'Did not count. It is in an eCash block, and the game refused it: the balance or the price limit did not cover it, or a later move counted first.',
    PendingStage.expired => 'Did not count. Its time ran out before it reached a block the game takes it in.',
    PendingStage.done => 'Final.',
  };

  @override
  Widget build(BuildContext context) {
    final game = _now;
    final mine = _mine;
    final price = _int(game, 'price_sats');
    final left = _int(game, 'left');
    final step = _int(game, 'next_step_ppm');
    final pot = _int(game, 'pot_sats');
    final fork = _int(_game, 'fork_height');
    final height = _int(game, 'l1_height');
    final count = int.tryParse(_keys.text.trim()) ?? 0;
    final balance = _int(mine, 'balance_sats');
    final beforeFork = fork > 0 && height < fork;
    final facts = _facts;
    final pending = _myPending;
    final open = pending.where((m) => isOpen(stageOf(m, facts))).toList();
    final after = balanceAfter(balance, price, pending, facts);
    final finalBalance = _int(_account, 'balance_sats');

    if (game == null) {
      final error = _readError;
      return QtPage(
        child: SailCard(
          title: error == null ? 'Waiting for the Sidepot node' : 'The Sidepot node is not answering',
          child: SailColumn(
            spacing: SailStyleValues.padding08,
            children: [
              SailText.secondary13(
                error == null
                    ? 'The first start takes about 15 minutes while it reads the eCash headers.'
                    : 'Stop Sidepot and start it again. If Stop does nothing, close BitWindow, end sidepot-node in the '
                          'task manager, and open BitWindow again.',
              ),
              if (error != null) SailText.secondary12(error),
            ],
          ),
        ),
      );
    }

    return QtPage(
      child: SingleChildScrollView(
        child: SailColumn(
          spacing: SailStyleValues.padding16,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SailCard(
                    title: 'Pot',
                    subtitle: 'Round ${_int(game, 'round')}',
                    child: SailColumn(
                      spacing: SailStyleValues.padding04,
                      children: [
                        SailText.primary24('${_ecx(pot)} ECX', bold: true),
                        SailText.secondary13('The last buyer wins ${_ecx(pot * 3 ~/ 4)} ECX when the clock runs out.'),
                        SailText.secondary13('${_int(game, 'keys')} keys bought this round.'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: SailStyleValues.padding16),
                Expanded(
                  child: SailCard(
                    title: 'Clock',
                    subtitle: 'eCash block $height',
                    child: SailColumn(
                      spacing: SailStyleValues.padding04,
                      children: [
                        SailText.primary24('$left ${left == 1 ? 'block' : 'blocks'} left', bold: true),
                        SailText.secondary13(
                          'Only eCash blocks that carry transactions count. Each buy puts at least 6 back.',
                        ),
                        if (beforeFork)
                          SailText.secondary13('The rules change at eCash block $fork, in ${fork - height} blocks.'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: SailStyleValues.padding16),
                Expanded(
                  child: SailCard(
                    title: 'Key price',
                    child: SailColumn(
                      spacing: SailStyleValues.padding04,
                      children: [
                        SailText.primary24('${_ecx(price)} ECX', bold: true),
                        SailText.secondary13(
                          'Rises ${(step / 10000).toStringAsFixed(step % 10000 == 0 ? 0 : 1)}% with the next block that holds a buy.',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SailCard(
                    title: 'Buy keys',
                    child: SailColumn(
                      spacing: SailStyleValues.padding12,
                      children: [
                        SailTextField(
                          controller: _keys,
                          label: 'Keys',
                          hintText: '1',
                          textFieldType: TextFieldType.number,
                        ),
                        SailText.secondary13(
                          count > 0
                              ? 'Costs ${_ecx(price * count)} ECX from the game account at the present price, and a little more if the price rises first.'
                              : 'Each key costs the present key price.',
                        ),
                        SailButton(
                          label: 'Buy',
                          loading: _busy == 'buy',
                          disabled: _busy != null || count < 1 || balance < price * count,
                          onPressed: _buy,
                        ),
                        if (count > 0 && balance < price * count)
                          SailText.secondary13('The game account holds ${_ecx(balance)} ECX. Put ECX in it first.'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: SailStyleValues.padding16),
                Expanded(
                  child: SailCard(
                    title: 'Your game account',
                    child: SailColumn(
                      spacing: SailStyleValues.padding12,
                      children: [
                        SailText.primary24('${_ecx(balance)} ECX', bold: true),
                        if (open.isNotEmpty)
                          SailText.secondary13(
                            'About ${_ecx(after)} ECX once your ${open.length == 1 ? 'pending move has' : '${open.length} pending moves have'} counted.',
                          ),
                        if (finalBalance != balance)
                          SailText.secondary13(
                            '${_ecx(finalBalance)} ECX as of the last Sidepot block. The next one makes the newer figure final.',
                          ),
                        SailText.secondary13(
                          '${_int(mine, 'keys')} keys this round. Dividends are paid into this balance.',
                        ),
                        SailTextField(
                          controller: TextEditingController(text: '${_account?['address'] ?? ''}'),
                          label: 'Account',
                          hintText: 'Waiting for the node...',
                          readOnly: true,
                          suffixWidget: CopyButton(text: '${_account?['address'] ?? ''}'),
                        ),
                        SailTextField(
                          controller: _cashout,
                          label: 'Cash out (ECX)',
                          hintText: 'All of it',
                        ),
                        SailButton(
                          label: 'Cash out to this wallet',
                          variant: ButtonVariant.secondary,
                          loading: _busy == 'cashout',
                          disabled: _busy != null || balance <= 0,
                          onPressed: _cashOut,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SailCard(
                    title: 'Move Sidepot coins into the game',
                    subtitle: 'From the Sidepot balance of this wallet',
                    child: SailColumn(
                      spacing: SailStyleValues.padding12,
                      children: [
                        SailTextField(controller: _move, label: 'Amount (ECX)', hintText: '0.1', enabled: !beforeFork),
                        SailText.secondary13(
                          beforeFork
                              ? 'Opens at eCash block $fork, when the rules change.'
                              : 'Credited with the next Sidepot block.',
                        ),
                        SailButton(
                          label: 'Move to game',
                          loading: _busy == 'move',
                          disabled: _busy != null || beforeFork,
                          onPressed: _moveToGame,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: SailStyleValues.padding16),
                Expanded(
                  child: SailCard(
                    title: 'Getting ECX into the game',
                    child: SailColumn(
                      spacing: SailStyleValues.padding08,
                      children: [
                        SailText.secondary13(
                          '1. Deposit: the Deposit button above puts eCash into the Sidepot balance of this wallet.',
                        ),
                        SailText.secondary13('2. Move to game: moves it from that balance into the game account.'),
                        SailText.secondary13('Cash out returns ECX from the game account to the Sidepot balance.'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (pending.isNotEmpty)
              SailCard(
                title: 'Your pending moves',
                subtitle: 'Sent from this BitWindow',
                child: SailColumn(
                  spacing: SailStyleValues.padding12,
                  children: [
                    for (final move in pending)
                      _PendingRow(
                        title: _moveTitle(move, price),
                        stage: stageOf(move, facts),
                        stageText: _stageText(move, stageOf(move, facts)),
                        transaction: '${move.kind == PendingKind.fund ? 'Sidepot' : 'eCash'} transaction ${move.txid}',
                        onDismiss: () async => _dismiss(move),
                      ),
                  ],
                ),
              ),
            if (_said != null)
              SailCard(
                title: _saidBad ? 'That did not go through' : 'Sent',
                child: SailText.primary13(_said!),
              ),
            const SizedBox(height: SailStyleValues.padding16),
          ],
        ),
      ),
    );
  }
}

class _PendingRow extends StatelessWidget {
  final String title;
  final PendingStage stage;
  final String stageText;
  final String transaction;
  final Future<void> Function() onDismiss;

  const _PendingRow({
    required this.title,
    required this.stage,
    required this.stageText,
    required this.transaction,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final settled = stage == PendingStage.rejected || stage == PendingStage.expired || stage == PendingStage.passed;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SailColumn(
            spacing: SailStyleValues.padding04,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SailText.primary13(title, bold: true),
              SailText.secondary13(stageText),
              SailText.secondary12(transaction),
            ],
          ),
        ),
        if (settled) SailButton(label: 'Dismiss', variant: ButtonVariant.secondary, onPressed: onDismiss),
      ],
    );
  }
}
