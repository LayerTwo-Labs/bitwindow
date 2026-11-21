import 'dart:async';

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
const _slot = 88;

/// What a deposit or a move pays the eCash network, in sats.
const _depositFeeSats = 1000;

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

  final _keys = TextEditingController(text: '1');
  final _deposit = TextEditingController();
  final _move = TextEditingController();
  final _cashout = TextEditingController();

  String? _busy;
  String? _said;
  bool _saidBad = false;

  @override
  void initState() {
    super.initState();
    _keys.addListener(_redraw);
    unawaited(_read());
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => unawaited(_read()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _keys.dispose();
    _deposit.dispose();
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
      if (!mounted) {
        return;
      }
      setState(() {
        _game = game is Map ? Map<String, dynamic>.from(game) : null;
        _account = account is Map ? Map<String, dynamic>.from(account) : null;
        _readError = null;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _readError = 'The Sidepot node is not answering. Start it from the Sidechains tab. ($error)');
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
    final txid = await _carry(await _rpc.callRAW('game_sign_buy', [count, null]));
    return 'Buy sent in eCash transaction $txid. It counts once that transaction is in a block.';
  });

  Future<void> _cashOut() => _run('cashout', () async {
    final typed = _cashout.text.trim();
    final amount = typed.isEmpty ? 0 : _sats(typed);
    if (amount == null) {
      throw Exception('Give the amount in ECX, or leave it empty for everything.');
    }
    final txid = await _carry(await _rpc.callRAW('game_sign_cashout', [amount, null]));
    return 'Cash-out sent in eCash transaction $txid. The coins arrive in the Sidepot balance of this wallet.';
  });

  Future<void> _depositToGame() => _run('deposit', () async {
    final amount = _sats(_deposit.text);
    final address = _account?['address'];
    final walletId = _walletId;
    if (amount == null || amount <= 0) {
      throw Exception('Give the amount in ECX.');
    }
    if (address is! String || !address.startsWith('spot:')) {
      throw Exception('The node has not given its game account yet.');
    }
    if (walletId == null) {
      throw Exception('No BitWindow wallet is open to deposit from.');
    }
    final txid = await GetIt.I.get<BitwindowRPC>().wallet.createSidechainDeposit(
      walletId,
      _slot,
      address,
      amount / _coin,
      _depositFeeSats / _coin,
    );
    return 'Deposit sent in eCash transaction $txid. The game account is credited once it is in a block.';
  });

  Future<void> _moveToGame() => _run('move', () async {
    final amount = _sats(_move.text);
    if (amount == null || amount <= 0) {
      throw Exception('Give the amount in ECX.');
    }
    final txid = await _rpc.callRAW('game_fund', [amount, null, null]);
    return 'Moved in Sidepot transaction $txid. The game account is credited with the next Sidepot block.';
  });

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

    return QtPage(
      child: SingleChildScrollView(
        child: SailColumn(
          spacing: SailStyleValues.padding16,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_readError != null) SailText.secondary13(_readError!),
            if (game == null && _readError == null)
              SailText.secondary13('Waiting for the Sidepot node. The first start takes about 15 minutes.'),
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
                          disabled: _busy != null || game == null || count < 1 || balance < price * count,
                          onPressed: _buy,
                        ),
                        if (game != null && count > 0 && balance < price * count)
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
                    title: 'Deposit eCash into the game',
                    subtitle: 'From the BitWindow wallet, straight to the game account',
                    child: SailColumn(
                      spacing: SailStyleValues.padding12,
                      children: [
                        SailTextField(controller: _deposit, label: 'Amount (ECX)', hintText: '0.1'),
                        SailText.secondary13(
                          'Credited once the deposit is in an eCash block. The network fee is ${_ecx(_depositFeeSats)} ECX.',
                        ),
                        SailButton(
                          label: 'Deposit',
                          loading: _busy == 'deposit',
                          disabled: _busy != null || _account == null,
                          onPressed: _depositToGame,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: SailStyleValues.padding16),
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
                          disabled: _busy != null || beforeFork || game == null,
                          onPressed: _moveToGame,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
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
