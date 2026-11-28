import 'dart:async';

import 'package:bitwindow/providers/address_book_provider.dart';
import 'package:bitwindow/providers/fork_provider.dart';
import 'package:bitwindow/providers/psbt_draft_provider.dart';
import 'package:bitwindow/providers/transactions_provider.dart';
import 'package:bitwindow/utils/explorer_url.dart';
import 'package:bitwindow/pages/wallet/wallet_send.dart';
import 'package:bitwindow/widgets/grouped_address.dart';
import 'package:bitwindow/widgets/hardware_device_picker.dart';
import 'package:bitwindow/widgets/send_panel_parts.dart';
import 'package:bitwindow/widgets/tx_flow_diagram.dart';
import 'package:collection/collection.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:sidechain_core/gen/wallet/v1/wallet.pb.dart' as walletpb;
import 'package:sidechain_core/gen/walletmanager/v1/walletmanager.pb.dart' as wmpb;
import 'package:sidechain_core/gen/walletpsbt/v1/walletpsbt.pb.dart';
import 'package:sail_ui/sail_ui.dart';

/// The view of one saved transaction: the flow card, and the broadcast and
/// discard actions. A multisig wallet also gets the keys table.
class DraftPanel extends StatefulWidget {
  final String walletId;
  final String draftId;

  const DraftPanel({
    super.key,
    required this.walletId,
    required this.draftId,
  });

  @override
  State<DraftPanel> createState() => _DraftPanelState();
}

class _DraftPanelState extends State<DraftPanel> {
  OrchestratorWalletRPC get _wallet => GetIt.I.get<OrchestratorRPC>().wallet;
  PsbtDraftProvider get _drafts => GetIt.I.get<PsbtDraftProvider>();
  WalletReaderProvider get _walletReader => GetIt.I.get<WalletReaderProvider>();
  AddressBookProvider get _addressBook => GetIt.I.get<AddressBookProvider>();
  TransactionProvider get _transactions => GetIt.I.get<TransactionProvider>();

  DecodedTransaction? _decoded;
  Set<String> _changeAddresses = {};
  String? _busyKey;
  String? _error;
  bool _showDiagram = false;
  String _decodedForPsbt = '';
  final Map<int, DateTime> _signedAt = {};

  bool _isBusy(String key) => _busyKey == key;
  bool _blocked(String key) => _busyKey != null && _busyKey != key;

  PsbtDraft? get _draft {
    for (final d in _drafts.drafts) {
      if (d.id == widget.draftId) {
        return d;
      }
    }
    return null;
  }

  DraftSigningStatus? get _status => _drafts.statusFor(widget.draftId);
  wmpb.MultisigInfo? get _multisig => _walletReader.activeWallet?.multisig;
  String get _walletName => _walletReader.activeWallet?.name ?? 'this wallet';

  /// A one-key draft can go out once each input holds a signature.
  bool get _fullySigned {
    final decoded = _decoded;
    return decoded != null &&
        decoded.details.inputs.isNotEmpty &&
        decoded.signedInputs >= decoded.details.inputs.length;
  }

  @override
  void initState() {
    super.initState();
    _drafts.addListener(_onDraftsChanged);
    _addressBook.addListener(_onDraftsChanged);
    _loadChangeAddresses();
    _decode();
  }

  @override
  void dispose() {
    _drafts.removeListener(_onDraftsChanged);
    _addressBook.removeListener(_onDraftsChanged);
    super.dispose();
  }

  void _onDraftsChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
    _decode();
  }

  Future<void> _decode() async {
    final draft = _draft;
    if (draft == null || draft.psbtBase64 == _decodedForPsbt) {
      return;
    }
    final forPsbt = draft.psbtBase64;
    try {
      final decoded = await _wallet.decodeTransaction(input: forPsbt, walletId: widget.walletId);
      if (!mounted || _draft?.psbtBase64 != forPsbt) {
        return;
      }
      setState(() {
        _decoded = decoded;
        _decodedForPsbt = forPsbt;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Failed to decode the transaction: $e');
      }
    }
  }

  Future<void> _loadChangeAddresses() async {
    try {
      final resp = await _wallet.listReceiveAddresses(widget.walletId);
      if (!mounted) {
        return;
      }
      setState(() {
        _changeAddresses = resp.addresses
            .where((address) => address.isChange)
            .map((address) => address.address)
            .toSet();
      });
    } catch (e) {
      // The change badge degrades to "payment"; the amounts stay correct.
    }
  }

  Future<void> _run(String key, Future<void> Function() action) async {
    setState(() {
      _busyKey = key;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(() => _error = _plainError(e));
      }
    } finally {
      if (mounted) {
        setState(() => _busyKey = null);
      }
    }
  }

  /// A draft outlives its inputs: another spend can take the same coin.
  /// Name that cause plainly instead of surfacing a raw RPC error.
  String _plainError(Object e) {
    final msg = e.toString();
    final lower = msg.toLowerCase();
    if (lower.contains('missing inputs') || lower.contains('missingorspent') || lower.contains('bad-txns-inputs')) {
      return 'A coin this transaction spends is no longer available — '
          'another transaction spent it. Discard this transaction and create a new one.';
    }
    return msg;
  }

  Future<void> _signCosigner(int index) => _run('cosigner-$index', () async {
    final draft = _draft!;
    final signed = await _wallet.signPsbtWithCosigner(
      walletId: widget.walletId,
      psbtBase64: draft.psbtBase64,
      cosignerXpub: _multisig!.cosigners[index].xpub,
    );
    await _drafts.updatePsbt(draft.id, signed);
    _signedAt[index] = DateTime.now();
  });

  Future<void> _signWithDevice(int index) => _run('device-$index', () async {
    final draft = _draft!;
    final c = _multisig!.cosigners[index];
    final sel = wmpb.HardwareDeviceSelector(type: c.hardwareDeviceType, fingerprint: c.fingerprint);
    final signed = await _signOnDevice(sel, draft.psbtBase64);
    final combined = await _wallet.combinePsbt(psbtsBase64: [draft.psbtBase64, signed]);
    await _drafts.updatePsbt(draft.id, combined);
    _signedAt[index] = DateTime.now();
  });

  Future<void> _signOneKeyWithDevice(wmpb.HardwareDeviceSelector device) => _run('device', () async {
    final draft = _draft!;
    final signed = await _signOnDevice(device, draft.psbtBase64);
    await _drafts.updatePsbt(draft.id, signed);
  });

  Future<String> _signOnDevice(wmpb.HardwareDeviceSelector sel, String psbt) async {
    try {
      return await _wallet.signPsbtWithDevice(device: sel, psbtBase64: psbt);
    } catch (e) {
      final msg = e.toString().toLowerCase();
      final needsDevice =
          msg.contains('locked') ||
          msg.contains('promptpin') ||
          msg.contains('-12') ||
          msg.contains('not found') ||
          msg.contains('no device') ||
          msg.contains('libusb');
      if (!needsDevice || !mounted) {
        rethrow;
      }
      final unlocked = await showHardwareDevicePicker(context);
      if (unlocked == null) {
        rethrow;
      }
      // Sign the just-unlocked device by path: a re-locked device has no
      // fingerprint, and path skips the re-enumeration that races auto-lock.
      final byPath = wmpb.HardwareDeviceSelector(
        type: unlocked.type,
        path: unlocked.path,
        passphrase: hardwareDevicePassphrase(unlocked.path),
      );
      return await _wallet.signPsbtWithDevice(device: byPath, psbtBase64: psbt);
    }
  }

  Future<void> _importSignedPsbt() async {
    final imported = await showThemedDialog<String>(
      context: context,
      builder: (context) => const _ImportPsbtDialog(),
    );
    if (imported == null || imported.isEmpty) {
      return;
    }
    await _run('import', () async {
      final draft = _draft!;
      final combined = await _wallet.combinePsbt(psbtsBase64: [draft.psbtBase64, imported]);
      await _drafts.updatePsbt(draft.id, combined);
    });
  }

  Future<void> _copyPsbt() async {
    final draft = _draft;
    if (draft == null) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: draft.psbtBase64));
    if (mounted) {
      showSailToast(context, 'PSBT copied', variant: SailToastVariant.success);
    }
  }

  Future<void> _broadcast() => _run('broadcast', () async {
    final draft = _draft!;
    _drafts.setBroadcastPending(draft.id, true);
    try {
      final hex = await _wallet.finalizePsbt(psbtBase64: draft.psbtBase64);
      final txid = await _wallet.broadcastTransaction(walletId: widget.walletId, txHex: hex);
      final fork = GetIt.I.get<ForkProvider>();
      final decoded = _decoded;
      // An undecoded transaction can hold a coin from both chains, so it counts
      // as one until the decode says otherwise.
      final spendsRisk =
          decoded == null || decoded.details.inputs.any((i) => fork.isReplayRisk('${i.prevTxid}:${i.prevVout}'));
      final protected = decoded != null && fork.replayLockTime != 0 && decoded.details.locktime == fork.replayLockTime;
      if (spendsRisk && !protected) {
        fork.rememberUnprotectedSend(txid);
      }

      // The transaction is on the network from here on. A failure below is
      // bookkeeping only and must never read as a broadcast failure.
      final network = GetIt.I.get<BitcoinConfProvider>().network;
      GetIt.I.get<NotificationProvider>().add(
        title: 'Transaction broadcast',
        content: txid,
        dialogType: DialogType.success,
        links: [NotificationLink(text: 'View transaction', url: mempoolTxUrl(txid, network))],
      );
      try {
        await _drafts.setTxid(draft.id, txid);
        if (draft.label.isNotEmpty) {
          await _transactions.saveNote(txid, draft.label);
        }
        await _transactions.fetch();
      } catch (e) {
        if (mounted) {
          setState(() => _error = 'The broadcast succeeded ($txid), but the draft update failed: $e');
        }
      }
    } finally {
      _drafts.setBroadcastPending(draft.id, false);
    }
  });

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    if (draft == null) {
      return const SizedBox.shrink();
    }
    final main = SailColumn(
      spacing: SailStyleValues.padding12,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _flowCard(context, draft),
        if (_multisig != null) _keysCard(context, draft),
      ],
    );
    final decoded = _decoded;
    final broadcast = draft.txid.isNotEmpty;
    final multisig = _multisig != null;
    final error = multisig ? null : _error ?? _drafts.modelError;
    final unit = GetIt.I.get<SettingsProvider>().bitcoinUnit;
    final otherUnit = unit == BitcoinUnit.btc ? BitcoinUnit.sats : BitcoinUnit.btc;

    final status = _status;
    final threshold = status?.threshold ?? _multisig?.m ?? 0;
    final pill = broadcast
        ? const SailStatusPill(label: 'Broadcast')
        : multisig
        ? SailStatusPill(
            label: '${status?.signatures ?? 0} of $threshold collected',
            tone: (status?.finalizable ?? false) ? SailStatusTone.success : SailStatusTone.warning,
          )
        : null;

    final total = decoded == null ? null : _paymentSats(decoded) + decoded.details.feeSats.toInt();
    final panel = SailSidePanel(
      title: draftName(draft),
      menuItems: () => _menu(context, draft),
      child: SailColumn(
        spacing: SailStyleValues.padding12,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (total == null)
            SailText.secondary13('Decoding the transaction…')
          else
            SendAmountBlock(
              amount: formatBitcoinWithUnit(satoshiToBTC(total), unit),
              otherUnit: formatBitcoinWithUnit(satoshiToBTC(total), otherUnit),
            ),
          if (pill != null) Align(alignment: Alignment.centerLeft, child: pill),
          if (broadcast) SailText.secondary12(draft.txid, monospace: true, overflow: TextOverflow.visible),
          Builder(
            builder: (_) {
              final pending = _drafts.isBroadcastPending(draft.id);
              if (draft.txid.isNotEmpty) {
                final network = GetIt.I.get<BitcoinConfProvider>().network;
                return SailButton(
                  label: 'View transaction',
                  onPressed: () async => openUrl(Uri.parse(mempoolTxUrl(draft.txid, network))),
                );
              }
              final wallet = _walletReader.activeWallet;
              if (_multisig == null && !_fullySigned && wallet != null && wallet.isHardware) {
                return SailButton(
                  label: 'Sign with ${wallet.hardwareDeviceType}',
                  loading: _isBusy('device'),
                  disabled: _blocked('device') || pending,
                  onPressed: () async => _signOneKeyWithDevice(
                    wmpb.HardwareDeviceSelector(
                      type: wallet.hardwareDeviceType,
                      fingerprint: wallet.hardwareFingerprint,
                    ),
                  ),
                );
              }
              if (_importIsPrimary(draft)) {
                return SailButton(
                  label: 'Import a signature',
                  loading: _isBusy('import'),
                  disabled: _blocked('import') || pending,
                  onPressed: () async => _importSignedPsbt(),
                );
              }
              return SailButton(
                label: 'Broadcast',
                loadingLabel: 'Broadcasting',
                disabled: !_signedForBroadcast || _blocked('broadcast') || pending,
                loading: _isBusy('broadcast') || pending,
                onPressed: () async => _broadcast(),
              );
            },
          ),
          if (error != null) SailInlineError(error),
          if (decoded != null)
            multisig
                ? DraftDetailsGroup(decoded: decoded, isChange: _isChange)
                : DraftSummaryCard(decoded: decoded, isChange: _isChange),
        ],
      ),
    );

    return SingleChildScrollView(
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < sendWideLayoutMinWidth) {
            return SailColumn(
              spacing: SailStyleValues.padding12,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [main, panel, SailSpacing(SailStyleValues.padding64)],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: main),
              const SizedBox(width: SailStyleValues.padding12),
              SizedBox(width: sendSideColumnWidth, child: panel),
            ],
          );
        },
      ),
    );
  }

  int _paymentSats(DecodedTransaction decoded) =>
      decoded.details.outputs.where((o) => !_isChange(o)).fold<int>(0, (sum, o) => sum + o.valueSats.toInt());

  bool get _signedForBroadcast => _multisig != null ? (_status?.finalizable ?? false) : _fullySigned;

  /// True when the main button imports a signature, so the "…" menu does not offer it again.
  bool _importIsPrimary(PsbtDraft draft) {
    if (draft.txid.isNotEmpty || _signedForBroadcast) {
      return false;
    }
    if (_multisig != null) {
      return true;
    }
    final wallet = _walletReader.activeWallet;
    return !(wallet != null && wallet.isHardware) && _decoded != null;
  }

  bool _canImport(PsbtDraft draft) =>
      draft.txid.isEmpty && (_multisig != null || (!_fullySigned && _decoded != null)) && !_importIsPrimary(draft);

  List<SailMenuEntity> _menu(BuildContext context, PsbtDraft draft) {
    final pending = _drafts.isBroadcastPending(draft.id);
    final broadcast = draft.txid.isNotEmpty;
    return [
      if (!broadcast || _multisig != null) sendMenuItem(context, 'Copy PSBT', () => unawaited(_copyPsbt())),
      if (_canImport(draft))
        sendMenuItem(
          context,
          'Import a signature',
          _busyKey != null || pending ? null : () => unawaited(_importSignedPsbt()),
        ),
      sendMenuItem(
        context,
        _showDiagram ? 'Hide diagram' : 'Show diagram',
        () => setState(() => _showDiagram = !_showDiagram),
      ),
      const SailMenuItemDivider(),
      sendMenuItem(
        context,
        'Discard',
        _busyKey != null || pending ? null : () => unawaited(confirmDeleteDraft(context, draft, _decoded)),
      ),
    ];
  }

  // ─── Flow card ───────────────────────────────────────────────────

  Widget _flowCard(BuildContext context, PsbtDraft draft) {
    final decoded = _decoded;
    return SailCard(
      title: 'Flow',
      child: decoded == null
          ? SailText.secondary13('Decoding the transaction…')
          : SailColumn(
              spacing: SailStyleValues.padding16,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (decoded.details.warningMessage.trim().isNotEmpty)
                  SailAlert(variant: SailAlertVariant.warning, description: decoded.details.warningMessage),
                if (_showDiagram)
                  TxFlowDiagram(
                    inputs: [
                      for (final input in decoded.details.inputs)
                        FlowSlot(sats: input.valueSats.toInt(), kind: FlowKind.input),
                    ],
                    outputs: [
                      for (final output in decoded.details.outputs)
                        FlowSlot(
                          sats: output.valueSats.toInt(),
                          kind: _isChange(output) ? FlowKind.change : FlowKind.payment,
                        ),
                      if (decoded.hasFee) FlowSlot(sats: decoded.details.feeSats.toInt(), kind: FlowKind.fee),
                    ],
                  ),
                _flowLabels(context, decoded, locked: draft.txid.isEmpty),
              ],
            ),
    );
  }

  Widget _flowLabels(BuildContext context, DecodedTransaction decoded, {required bool locked}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final spends = _spendsColumn(context, decoded, locked: locked);
        final creates = _createsColumn(context, decoded);
        if (constraints.maxWidth > 600) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: spends),
              const SizedBox(width: SailStyleValues.padding20),
              Expanded(child: creates),
            ],
          );
        }
        return SailColumn(
          spacing: SailStyleValues.padding16,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [spends, creates],
        );
      },
    );
  }

  Widget _spendsColumn(BuildContext context, DecodedTransaction decoded, {required bool locked}) {
    final inputs = decoded.details.inputs;
    final total = decoded.details.totalInputSats.toInt();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SailText.secondary12(
          'SPENDS · ${inputs.length} ${inputs.length == 1 ? 'coin' : 'coins'} · ${_fmt(total)}${locked ? ' · locked' : ''}',
          bold: true,
        ),
        for (final input in inputs)
          _FlowLine(
            amount: SailText.primary13(_fmt(input.valueSats.toInt()), monospace: true),
            detail: SailText.secondary12(_inputLabel(input), monospace: true),
          ),
      ],
    );
  }

  String _inputLabel(walletpb.TransactionInput input) {
    final address = _shortAddress(input.address);
    final received = _receivedDate('${input.prevTxid}:${input.prevVout}');
    if (received == null) {
      return address;
    }
    return '$address · received $received';
  }

  String? _receivedDate(String outpoint) {
    for (final utxo in _transactions.utxos) {
      if (utxo.output == outpoint && utxo.hasReceivedAt()) {
        return formatDate(utxo.receivedAt.toDateTime(), long: false);
      }
    }
    return null;
  }

  Widget _createsColumn(BuildContext context, DecodedTransaction decoded) {
    final outputs = decoded.details.outputs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SailText.secondary12(
          'CREATES · ${outputs.length} ${outputs.length == 1 ? 'output' : 'outputs'}${decoded.hasFee ? ' + fee' : ''}',
          bold: true,
        ),
        for (final output in outputs) _outputRow(context, output),
        if (decoded.hasFee)
          _FlowLine(
            amount: SailText.primary13(_fmt(decoded.details.feeSats.toInt()), monospace: true),
            detail: SailText.secondary12('paid to the miner, not an output'),
          ),
      ],
    );
  }

  Widget _outputRow(BuildContext context, walletpb.TransactionOutput output) {
    final theme = context.sailTheme;
    final address = output.address;
    final isChange = _isChange(output);
    final bookName = _addressBookName(address);

    return _FlowLine(
      amount: SailText.primary13(_fmt(output.valueSats.toInt()), monospace: true),
      tag: isChange
          ? _StatusLabel('change · back to $_walletName', theme.colors.success)
          : _StatusLabel('payment', theme.colors.orange),
      detail: isChange
          ? SailText.secondary12(
              bookName == null ? _shortAddress(address) : '$bookName · ${_shortAddress(address)}',
              monospace: true,
            )
          : Wrap(
              spacing: SailStyleValues.padding08,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (bookName != null) SailText.secondary12(bookName),
                GroupedAddress(address),
              ],
            ),
    );
  }

  bool _isChange(walletpb.TransactionOutput output) =>
      (_decoded?.changeOutputIndexes.contains(output.index) ?? false) ||
      (output.address.isNotEmpty && _changeAddresses.contains(output.address));

  String? _addressBookName(String address) {
    for (final entry in _addressBook.entries) {
      if (entry.address == address) {
        return entry.label;
      }
    }
    return null;
  }

  // ─── Keys card ───────────────────────────────────────────────────

  Widget _keysCard(BuildContext context, PsbtDraft draft) {
    final theme = context.sailTheme;
    final multisig = _multisig!;
    final status = _status;
    final threshold = status?.threshold ?? multisig.m;
    final signatures = status?.signatures ?? 0;
    final phone = SailStyleValues.phoneLayout(context);

    return SailCard(
      title: 'Keys',
      subtitle: '$_walletName needs ${multisig.m} of its ${multisig.n} keys.',
      error: _error ?? _drafts.modelError,
      widgetHeaderEnd: SailText.primary13(
        '$signatures of $threshold collected',
        color: (status?.finalizable ?? false) ? theme.colors.success : theme.colors.orange,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: phone
            ? [
                const _PhoneKeysHeader(),
                for (var i = 0; i < multisig.cosigners.length; i++) _phoneKeyRow(i, multisig.cosigners[i]),
              ]
            : [
                const _KeysHeader(),
                for (var i = 0; i < multisig.cosigners.length; i++) _keyRow(context, i, multisig.cosigners[i]),
              ],
      ),
    );
  }

  bool _cosignerSigned(int i) {
    final status = _status;
    return status != null && i < status.cosignerSigned.length && status.cosignerSigned[i];
  }

  bool _canSign(int i, wmpb.MultisigCosignerInfo c) =>
      !_cosignerSigned(i) && (c.held || c.hardwareDeviceType.isNotEmpty) && _draft?.txid.isEmpty == true;

  Future<void> _sign(int i, wmpb.MultisigCosignerInfo c) => c.held ? _signCosigner(i) : _signWithDevice(i);

  Widget _keyRow(BuildContext context, int i, wmpb.MultisigCosignerInfo c) {
    final signed = _cosignerSigned(i);
    final busyKey = c.held ? 'cosigner-$i' : 'device-$i';
    final canSign = _canSign(i, c);

    return _KeyRow(
      index: i,
      heldBy: _heldBy(c),
      type: _keyType(c),
      fingerprint: c.fingerprint,
      signed: signed,
      signedAt: signed ? _signedLabel(i) : '-',
      busy: _isBusy(busyKey),
      menuItems: () => [
        if (canSign) sendMenuItem(context, 'Sign', _blocked(busyKey) ? null : () => unawaited(_sign(i, c))),
      ],
    );
  }

  _PhoneKeyRow _phoneKeyRow(int i, wmpb.MultisigCosignerInfo c) {
    final busyKey = c.held ? 'cosigner-$i' : 'device-$i';
    return _PhoneKeyRow(
      index: i,
      signed: _cosignerSigned(i),
      onSign: _canSign(i, c) ? () => _sign(i, c) : null,
      busy: _isBusy(busyKey),
      blocked: _blocked(busyKey),
    );
  }

  String _heldBy(wmpb.MultisigCosignerInfo c) {
    if (c.held) {
      return 'This computer';
    }
    if (c.hardwareDeviceType.isNotEmpty) {
      return _capitalize(c.hardwareDeviceType);
    }
    return 'Somewhere else';
  }

  String _keyType(wmpb.MultisigCosignerInfo c) {
    if (c.held) {
      return 'Software';
    }
    if (c.hardwareDeviceType.isNotEmpty) {
      return 'Hardware';
    }
    return 'Watch-only';
  }

  String _signedLabel(int i) {
    final at = _signedAt[i];
    if (at == null) {
      return '—';
    }
    return _relativeTime(at);
  }

  String _fmt(int sats) => formatBitcoin(satoshiToBTC(sats));

  static String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  static String _relativeTime(DateTime at) {
    final elapsed = DateTime.now().difference(at);
    if (elapsed.inMinutes < 1) {
      return 'a moment ago';
    }
    if (elapsed.inHours < 1) {
      return '${elapsed.inMinutes} min ago';
    }
    return formatDate(at, long: false);
  }
}

String _shortAddress(String address) {
  if (address.length <= 14) {
    return address;
  }
  return '${address.substring(0, 6)}…${address.substring(address.length - 4)}';
}

/// The name of a saved transaction in its tab and its panel.
String draftName(PsbtDraft draft) => draft.label.isNotEmpty ? draft.label : 'Transaction ${draftReference(draft)}';

/// One line of the flow card: the amount with an optional tag, the address under it, and a hairline below.
class _FlowLine extends StatelessWidget {
  final Widget amount;
  final Widget? tag;
  final Widget detail;

  const _FlowLine({required this.amount, this.tag, required this.detail});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.sailTheme.colors.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: SailStyleValues.padding08,
            runSpacing: SailStyleValues.padding04,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [amount, ?tag],
          ),
          const SizedBox(height: 2),
          detail,
        ],
      ),
    );
  }
}

const double _colType = 120;
const double _colFingerprint = 120;
const double _colStatus = 180;
const double _colSigned = 90;
const double _colMenu = 28;

class _KeysHeader extends StatelessWidget {
  const _KeysHeader();

  @override
  Widget build(BuildContext context) {
    final theme = context.sailTheme;
    Widget head(String label) => SailText.secondary12(label, color: theme.colors.textSecondary);
    return Container(
      padding: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.colors.divider)),
      ),
      child: Row(
        children: [
          Expanded(child: head('Key')),
          SizedBox(width: _colType, child: head('Type')),
          SizedBox(width: _colFingerprint, child: head('Fingerprint')),
          SizedBox(width: _colStatus, child: head('Status')),
          SizedBox(width: _colSigned, child: head('Signed')),
          const SizedBox(width: _colMenu),
        ],
      ),
    );
  }
}

/// One key of a multisig draft: who holds it, its status, and a "…" with Sign when this computer can sign with it.
class _KeyRow extends StatelessWidget {
  final int index;
  final String heldBy;
  final String type;
  final String fingerprint;
  final bool signed;
  final String signedAt;
  final bool busy;
  final List<SailMenuEntity> Function() menuItems;

  const _KeyRow({
    required this.index,
    required this.heldBy,
    required this.type,
    required this.fingerprint,
    required this.signed,
    required this.signedAt,
    required this.busy,
    required this.menuItems,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.sailTheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.colors.divider)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SailText.primary13('Key ${index + 1}', bold: true),
                SailText.secondary12(heldBy),
              ],
            ),
          ),
          SizedBox(width: _colType, child: SailText.primary13(type)),
          SizedBox(width: _colFingerprint, child: SailText.primary13(fingerprint, monospace: true)),
          SizedBox(
            width: _colStatus,
            child: Row(
              children: [
                SailStatusDot(tone: signed ? SailStatusTone.success : SailStatusTone.warning),
                const SizedBox(width: 6),
                Flexible(child: SailText.primary13(signed ? 'Signed' : 'Awaiting signature')),
              ],
            ),
          ),
          SizedBox(width: _colSigned, child: SailText.primary13(signedAt)),
          SizedBox(
            width: _colMenu,
            child: busy
                ? const Center(child: SizedBox(width: 14, height: 14, child: LoadingIndicator()))
                : SailRowMenuButton(key: Key('key_menu_$index'), items: menuItems, filled: false),
          ),
        ],
      ),
    );
  }
}

/// A status label: a chip on a desktop, plain colored text on a phone.
class _StatusLabel extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusLabel(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    if (SailStyleValues.phoneLayout(context)) {
      return SailText.secondary12(label, color: color);
    }
    return FlowChip(label: label, color: color);
  }
}

const _phoneKeyFlex = 9;
const _phoneStatusFlex = 5;

class _PhoneKeysHeader extends StatelessWidget {
  const _PhoneKeysHeader();

  @override
  Widget build(BuildContext context) {
    final theme = context.sailTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: SailStyleValues.padding08),
      child: Row(
        children: [
          Expanded(
            flex: _phoneKeyFlex,
            child: SailText.secondary12('KEY', color: theme.colors.textTertiary),
          ),
          Expanded(
            flex: _phoneStatusFlex,
            child: SailText.secondary12('STATUS', color: theme.colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

/// One 40 px key row on a phone. [onSign] is null when this phone cannot sign with the key.
class _PhoneKeyRow extends StatelessWidget {
  final int index;
  final bool signed;
  final Future<void> Function()? onSign;
  final bool busy;
  final bool blocked;

  const _PhoneKeyRow({
    required this.index,
    required this.signed,
    required this.onSign,
    required this.busy,
    required this.blocked,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.sailTheme;
    return Container(
      height: 40,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.colors.divider)),
      ),
      child: Row(
        children: [
          Expanded(flex: _phoneKeyFlex, child: SailText.primary13('Key ${index + 1}', bold: true)),
          Expanded(
            flex: _phoneStatusFlex,
            child: Row(
              children: [
                Expanded(
                  child: signed
                      ? SailText.secondary12('Signed', color: theme.colors.success)
                      : SailText.secondary12('Awaiting signature', color: theme.colors.orange),
                ),
                if (onSign != null)
                  SailButton(label: 'Sign', small: true, loading: busy, disabled: blocked, onPressed: onSign!),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Frame 14: the confirm names the transaction and what dies with it.
/// Deletes the draft when confirmed and returns true.
Future<bool> confirmDeleteDraft(BuildContext context, PsbtDraft draft, DecodedTransaction? decoded) async {
  // A delete between the broadcast RPC and its bookkeeping loses the txid.
  if (GetIt.I.get<PsbtDraftProvider>().isBroadcastPending(draft.id)) {
    showSailToast(context, 'A broadcast is in flight for this transaction. Wait for it to finish.');
    return false;
  }

  final name = draftName(draft);
  var summary = name;
  final payment = decoded?.details.outputs.firstOrNull;
  if (payment != null) {
    summary = '$name · ${formatBitcoin(satoshiToBTC(payment.valueSats.toInt()))}';
  }
  final subtitle = draft.txid.isNotEmpty
      ? '$summary. The transaction is already broadcast — the delete only removes this tab. The coins moved.'
      : '$summary. Nothing was broadcast, so no coins move. New transactions can spend its coins again.';

  final confirmed = await showThemedDialog<bool>(
    context: context,
    builder: (context) => SignDialog(
      title: 'Are you sure you want to delete this transaction?',
      subtitle: subtitle,
      maxWidth: 560,
      onClose: () async => Navigator.of(context).pop(false),
      button: SailButton(
        label: 'Delete transaction',
        variant: ButtonVariant.destructive,
        onPressed: () async => Navigator.of(context).pop(true),
      ),
    ),
  );

  if (confirmed != true) {
    return false;
  }
  await GetIt.I.get<PsbtDraftProvider>().delete(draft.id);
  return true;
}

/// The short reference shown in the tab: the first four characters of the
/// server-generated draft id.
String draftReference(PsbtDraft draft) {
  return draft.id.length <= 4 ? draft.id : draft.id.substring(0, 4);
}

/// Small dialog to paste a base64 PSBT that another cosigner signed.
class _ImportPsbtDialog extends StatefulWidget {
  const _ImportPsbtDialog();

  @override
  State<_ImportPsbtDialog> createState() => _ImportPsbtDialogState();
}

class _ImportPsbtDialogState extends State<_ImportPsbtDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SignDialog(
      title: 'Import a signature',
      subtitle: 'Paste the base64 PSBT a cosigner signed elsewhere',
      maxWidth: 560,
      button: SailButton(
        label: 'Import',
        onPressed: () async => Navigator.of(context).pop(_controller.text.trim()),
      ),
      child: SailTextField(
        controller: _controller,
        hintText: 'cHNidP8B...',
        size: TextFieldSize.small,
        minLines: 3,
        maxLines: 6,
        suffixWidget: SailButton(
          label: 'Paste',
          variant: ButtonVariant.ghost,
          small: true,
          onPressed: () async {
            final data = await Clipboard.getData(Clipboard.kTextPlain);
            if (data?.text != null) {
              _controller.text = data!.text!.trim();
            }
          },
        ),
      ),
    );
  }
}

/// What a saved transaction pays, in the lines of the send form summary.
class DraftSummaryCard extends StatelessWidget {
  final DecodedTransaction decoded;
  final bool Function(walletpb.TransactionOutput output) isChange;

  const DraftSummaryCard({super.key, required this.decoded, required this.isChange});

  @override
  Widget build(BuildContext context) {
    final unit = GetIt.I.get<SettingsProvider>().bitcoinUnit;
    String fmt(int sats) => formatBitcoinWithUnit(satoshiToBTC(sats), unit);
    final payments = decoded.details.outputs.where((o) => !isChange(o)).toList();
    final inputs = decoded.details.inputs;
    final amount = payments.fold<int>(0, (sum, o) => sum + o.valueSats.toInt());
    final fee = decoded.details.feeSats.toInt();

    return SailDetailGroup(
      fill: SailDetailFill.canvas,
      title: 'Summary',
      children: [
        SailDetailLine(label: 'Recipients', value: '${payments.length}'),
        SailDetailLine(
          label: 'Pay from',
          value:
              '${inputs.length} ${inputs.length == 1 ? 'UTXO' : 'UTXOs'} · ${fmt(decoded.details.totalInputSats.toInt())}',
        ),
        SailDetailLine(label: 'Amount', value: fmt(amount), monospace: true),
        SailDetailLine(label: 'Fee', value: fmt(fee), monospace: true),
        SailDetailLine(label: 'Total', value: fmt(amount + fee), monospace: true),
      ],
    );
  }
}

/// What a multisig transaction pays, changes and spends.
class DraftDetailsGroup extends StatelessWidget {
  final DecodedTransaction decoded;
  final bool Function(walletpb.TransactionOutput output) isChange;

  const DraftDetailsGroup({super.key, required this.decoded, required this.isChange});

  @override
  Widget build(BuildContext context) {
    final unit = GetIt.I.get<SettingsProvider>().bitcoinUnit;
    String fmt(int sats) => formatBitcoinWithUnit(satoshiToBTC(sats), unit);
    final outputs = decoded.details.outputs;
    final payments = outputs.where((o) => !isChange(o)).toList();
    final change = outputs.where(isChange).fold<int>(0, (sum, o) => sum + o.valueSats.toInt());
    final inputs = decoded.details.inputs;

    return SailDetailGroup(
      fill: SailDetailFill.canvas,
      title: 'Details',
      children: [
        for (final payment in payments)
          SailDetailLine(label: 'Pays', value: _shortAddress(payment.address), monospace: true),
        SailDetailLine(
          label: 'Amount',
          value: fmt(payments.fold<int>(0, (sum, o) => sum + o.valueSats.toInt())),
          monospace: true,
        ),
        SailDetailLine(label: 'Change', value: fmt(change), monospace: true),
        SailDetailLine(label: 'Fee', value: fmt(decoded.details.feeSats.toInt()), monospace: true),
        SailDetailLine(
          label: 'Spends',
          value:
              '${inputs.length} ${inputs.length == 1 ? 'coin' : 'coins'} · ${fmt(decoded.details.totalInputSats.toInt())}',
        ),
      ],
    );
  }
}
