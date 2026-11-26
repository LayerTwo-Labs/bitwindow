import 'dart:async';

import 'package:bitwindow/signing/psbt_text.dart';
import 'package:bitwindow/widgets/airgap_psbt_dialog.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';

/// Standalone PSBT signing tool: paste an unsigned PSBT, review what it pays,
/// and run it through the airgap (external signer) flow — export it, collect
/// the signed PSBT back, and broadcast — without going through the send screen
/// first.
class PsbtSignerTab extends StatefulWidget {
  const PsbtSignerTab({super.key});

  @override
  State<PsbtSignerTab> createState() => _PsbtSignerTabState();
}

class _PsbtSignerTabState extends State<PsbtSignerTab> {
  final TextEditingController _controller = TextEditingController();
  OrchestratorWalletRPC get _wallet => GetIt.I.get<OrchestratorRPC>().wallet;
  WalletReaderProvider get _walletReader => GetIt.I.get<WalletReaderProvider>();

  String _psbt = '';
  String? _walletId;
  DecodedTransaction? _decoded;
  String? _broadcastTxid;
  String? _error;

  @override
  void initState() {
    super.initState();
    _walletId = _walletReader.activeWalletId;
    _controller.addListener(_onChanged);
    _walletReader.addListener(_onWalletChanged);
  }

  @override
  void dispose() {
    _walletReader.removeListener(_onWalletChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    final psbt = _controller.text.replaceAll(RegExp(r'\s'), '');
    if (psbt == _psbt) {
      return;
    }
    setState(() {
      _psbt = psbt;
      _decoded = null;
      _error = null;
      if (psbt.isNotEmpty) {
        _broadcastTxid = null;
      }
    });
    if (isBase64Psbt(psbt)) {
      unawaited(_decode(psbt));
    }
  }

  // The change rows of a review belong to one wallet.
  void _onWalletChanged() {
    final walletId = _walletReader.activeWalletId;
    if (walletId == _walletId) {
      return;
    }
    setState(() {
      _walletId = walletId;
      _decoded = null;
      _error = null;
    });
    if (isBase64Psbt(_psbt)) {
      unawaited(_decode(_psbt));
    }
  }

  Future<DecodedTransaction?> _decode(String psbt) async {
    final walletId = _walletId;
    bool current() => mounted && psbt == _psbt && walletId == _walletId;
    try {
      final decoded = await _wallet.decodeTransaction(
        input: psbt,
        walletId: walletId ?? '',
        checkOwnership: true,
      );
      if (!current()) {
        return null;
      }
      setState(() => _decoded = decoded);
      return decoded;
    } catch (e) {
      if (current()) {
        setState(() => _error = 'Could not read the PSBT: ${extractConnectException(e)}');
      }
      return null;
    }
  }

  Future<void> _start(BuildContext context) async {
    final psbt = _psbt;
    if (psbt.isEmpty) {
      setState(() => _error = 'Paste an unsigned PSBT first');
      return;
    }
    if (!isBase64Psbt(psbt)) {
      setState(() => _error = 'Not a valid base64 PSBT');
      return;
    }
    final walletId = _walletId;
    if (walletId == null) {
      setState(() => _error = 'No active wallet');
      return;
    }
    // Never start the signer flow for a PSBT that the card does not show.
    if (_decoded == null && await _decode(psbt) == null) {
      return;
    }
    if (!context.mounted || psbt != _psbt || walletId != _walletId) {
      return;
    }
    setState(() => _error = null);
    String? txid;
    await showThemedDialog<bool>(
      context: context,
      builder: (context) => AirgapPsbtDialog(
        walletId: walletId,
        unsignedPsbtBase64: psbt,
        onBroadcast: (id) => txid = id,
      ),
    );
    if (txid != null && mounted) {
      _controller.clear();
      setState(() => _broadcastTxid = txid);
    }
  }

  @override
  Widget build(BuildContext context) {
    final decoded = _decoded;
    final txid = _broadcastTxid;
    return SailCard(
      title: 'PSBT Signer',
      subtitle: 'Paste an unsigned PSBT to sign it with an external (airgap) signer',
      error: _error,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SailTextField(
              controller: _controller,
              hintText: 'base64 PSBT',
              minLines: 3,
              maxLines: 6,
            ),
            if (decoded != null) ...[
              const SailSpacing(SailStyleValues.padding16),
              PsbtReview(decoded: decoded),
            ],
            if (txid != null) ...[
              const SailSpacing(SailStyleValues.padding16),
              SailText.primary13('Broadcast'),
              const SailSpacing(SailStyleValues.padding04),
              _ReviewRow(label: 'TXID', value: txid),
            ],
            const SailSpacing(SailStyleValues.padding08),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                SailButton(
                  onPressed: () => _start(context),
                  label: 'Sign with external signer',
                  variant: ButtonVariant.primary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// What a PSBT pays, where its change goes, and what it costs.
class PsbtReview extends StatelessWidget {
  final DecodedTransaction decoded;

  const PsbtReview({super.key, required this.decoded});

  @override
  Widget build(BuildContext context) {
    final formatter = GetIt.I<FormatterProvider>();
    final details = decoded.details;
    String output(int sats, String address) =>
        '${formatter.formatSats(sats)} to ${address.isEmpty ? 'an unknown script' : address}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SailText.primary13('Transaction'),
        const SailSpacing(SailStyleValues.padding04),
        if (details.warningMessage.trim().isNotEmpty) ...[
          SailAlert(variant: SailAlertVariant.warning, description: details.warningMessage),
          const SailSpacing(SailStyleValues.padding04),
        ],
        for (final o in details.outputs.where((o) => !decoded.changeOutputIndexes.contains(o.index)))
          _ReviewRow(label: 'Pays', value: output(o.valueSats.toInt(), o.address)),
        for (final o in details.outputs.where((o) => decoded.changeOutputIndexes.contains(o.index)))
          _ReviewRow(label: 'Change', value: output(o.valueSats.toInt(), o.address)),
        _ReviewRow(
          label: 'Fee',
          value: decoded.hasFee ? formatter.formatSats(details.feeSats.toInt()) : 'Unknown',
        ),
        _ReviewRow(label: 'Signed inputs', value: '${decoded.signedInputs} of ${details.inputs.length}'),
      ],
    );
  }
}

class _ReviewRow extends StatelessWidget {
  final String label;
  final String value;

  const _ReviewRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SailStyleValues.padding04),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 160, child: SailText.secondary13(label)),
          Expanded(child: SailText.secondary13(value)),
        ],
      ),
    );
  }
}
