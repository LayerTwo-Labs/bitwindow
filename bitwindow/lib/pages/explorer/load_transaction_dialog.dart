import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:sidechain_core/gen/walletmanager/v1/walletmanager.pb.dart' as wmpb;
import 'package:sail_ui/sail_ui.dart';

/// With [txid], opens on that transaction, wallet-owned or not. [blockHash]
/// names its block, when the caller knows it.
Future<void> showLoadTransactionDialog(BuildContext context, {String? txid, String blockHash = ''}) async {
  await showThemedDialog<void>(
    context: context,
    builder: (_) => SailModal(
      constraints: const BoxConstraints(maxWidth: 900, maxHeight: 760),
      child: LoadTransactionDialog(txid: txid, blockHash: blockHash),
    ),
  );
}

class LoadTransactionDialog extends StatefulWidget {
  final String? txid;
  final String blockHash;

  const LoadTransactionDialog({super.key, this.txid, this.blockHash = ''});

  @override
  State<LoadTransactionDialog> createState() => _LoadTransactionDialogState();
}

class _LoadTransactionDialogState extends State<LoadTransactionDialog> {
  OrchestratorWalletRPC get _wallet => GetIt.I.get<OrchestratorRPC>().wallet;
  WalletReaderProvider get _walletReader => GetIt.I.get<WalletReaderProvider>();
  Logger get _log => GetIt.I.get<Logger>();

  late final _controller = TextEditingController(text: widget.txid);
  DecodedTransaction? _decoded;
  String? _error;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.txid != null) {
      unawaited(_decode());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _decode() async {
    final input = _controller.text.trim();
    if (input.isEmpty) {
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final decoded = await _wallet.decodeTransaction(
        input: input,
        walletId: _walletReader.activeWalletId ?? '',
        blockHash: widget.blockHash,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _decoded = decoded;
        _error = null;
        _isLoading = false;
      });
    } catch (e) {
      _log.e('failed to decode transaction: $e');
      if (!mounted) {
        return;
      }
      setState(() {
        _decoded = null;
        _error = _humanize(e);
        _isLoading = false;
      });
    }
  }

  String _humanize(Object e) {
    final raw = e.toString().toLowerCase();
    if (raw.contains('not a valid')) {
      return 'Not a valid txid, transaction hex, or PSBT.';
    }
    if (raw.contains('no txindex')) {
      return 'This node keeps no transaction index, so it finds only wallet and mempool txids. '
          'Paste the raw transaction hex instead.';
    }
    if (raw.contains('not found')) {
      return 'That txid was not found in the active wallet or on chain.';
    }
    if (raw.contains('connection') || raw.contains('unavailable') || raw.contains('refused')) {
      return 'Could not reach the orchestrator. Make sure your daemon is running and try again.';
    }
    return 'Could not decode this transaction. Check the input and try again.';
  }

  @override
  Widget build(BuildContext context) {
    final fixed = widget.txid != null;
    if (!fixed && !SailStyleValues.phoneLayout(context)) {
      final decoded = _decoded;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SailStrip(
            lead: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SailText.primary13('Load Transaction', bold: true),
                SailText.secondary12('Paste a txid, raw transaction hex, or base64 PSBT'),
              ],
            ),
            stats: [
              SailTextField(
                controller: _controller,
                hintText: 'txid / transaction hex / base64 PSBT',
                maxLines: 1,
              ),
            ],
            actions: [
              SailButton(
                onPressed: _isLoading ? null : _decode,
                label: 'Decode',
                variant: ButtonVariant.primary,
                loading: _isLoading,
              ),
            ],
          ),
          if (_error != null) ...[const SizedBox(height: SailStyleValues.padding08), SailInlineError(_error!)],
          if (decoded != null) ...[
            const SizedBox(height: SailStyleValues.padding12),
            Expanded(
              child: SailCard(
                bottomPadding: false,
                child: _DecodedView(decoded: decoded),
              ),
            ),
          ],
        ],
      );
    }
    return SailCard(
      title: fixed ? 'Transaction' : 'Load Transaction',
      subtitle: fixed ? widget.txid! : 'Paste a txid, raw transaction hex, or base64 PSBT',
      error: _error,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!fixed) ...[
            SailTextField(
              controller: _controller,
              hintText: 'txid / transaction hex / base64 PSBT',
              minLines: 3,
              maxLines: 6,
            ),
            const SailSpacing(SailStyleValues.padding08),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                SailButton(
                  onPressed: _isLoading ? null : _decode,
                  label: 'Decode',
                  variant: ButtonVariant.primary,
                  loading: _isLoading,
                ),
              ],
            ),
            const SailSpacing(SailStyleValues.padding16),
          ],
          if (fixed && _isLoading) const Center(child: SailCircularProgressIndicator()),
          if (_decoded != null) Expanded(child: _DecodedView(decoded: _decoded!)),
        ],
      ),
    );
  }
}

/// The fee rate of [decoded], or 'Unknown' when its fee or size is unknown.
String feeRateText(DecodedTransaction decoded) {
  if (!decoded.hasFee || decoded.details.vsizeVbytes <= 0) {
    return 'Unknown';
  }
  return '${decoded.details.feeRateSatVb.toStringAsFixed(2)} ${activeTicker.feeRate}';
}

class _DecodedView extends StatelessWidget {
  final DecodedTransaction decoded;

  const _DecodedView({required this.decoded});

  String get _formLabel {
    switch (decoded.form) {
      case wmpb.DecodedForm.DECODED_FORM_PSBT:
        return 'PSBT';
      case wmpb.DecodedForm.DECODED_FORM_RAW_TX:
        return 'Raw transaction';
      case wmpb.DecodedForm.DECODED_FORM_TXID:
        return 'Transaction (by id)';
      default:
        return 'Transaction';
    }
  }

  @override
  Widget build(BuildContext context) {
    final details = decoded.details;
    final head = Row(
      children: [
        Flexible(child: SailText.primary15(_formLabel, bold: true)),
        const SizedBox(width: SailStyleValues.padding08),
        if (decoded.isPsbt)
          SailStatusPill(
            label: '${decoded.signedInputs}/${details.inputs.length} inputs signed',
            tone: decoded.signedInputs >= details.inputs.length ? SailStatusTone.success : SailStatusTone.warning,
          ),
      ],
    );
    final warning = details.warningMessage.trim().isEmpty
        ? null
        : SailAlert(variant: SailAlertVariant.warning, description: details.warningMessage);
    // With the tabs in the head, the warning heads each tab instead.
    final tabsInHead = !SailStyleValues.phoneLayout(context);
    Widget tab(Widget child) => !tabsInHead || warning == null
        ? child
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              warning,
              const SailSpacing(SailStyleValues.padding08),
              Expanded(child: child),
            ],
          );

    final tabs = InlineTabBar(
      leading: tabsInHead ? head : null,
      tabs: [
        TabItem(
          label: 'Overview',
          child: tab(_Overview(decoded: decoded)),
        ),
        TabItem(
          label: 'Inputs (${details.inputs.length})',
          child: tab(_InputsTable(decoded: decoded)),
        ),
        TabItem(
          label: 'Outputs (${details.outputs.length})',
          child: tab(_OutputsTable(decoded: decoded)),
        ),
        TabItem(
          label: 'Bytes',
          child: tab(TransactionByteView(rawHex: details.hex)),
        ),
      ],
      initialIndex: 0,
    );
    if (tabsInHead) {
      return tabs;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        head,
        const SailSpacing(SailStyleValues.padding08),
        if (warning != null) ...[warning, const SailSpacing(SailStyleValues.padding08)],
        Expanded(child: tabs),
      ],
    );
  }
}

class _Overview extends StatelessWidget {
  final DecodedTransaction decoded;

  const _Overview({required this.decoded});

  @override
  Widget build(BuildContext context) {
    final details = decoded.details;
    final formatter = GetIt.I<FormatterProvider>();
    final sized = details.vsizeVbytes > 0;

    final info = [
      const SailDetailHeading('Transaction Info'),
      SailDetailGroup(
        fill: SailDetailFill.canvas,
        children: [
          SailDetailLine(wrap: true, label: 'TXID', value: details.txid),
          SailDetailLine(wrap: true, label: 'Version', value: '${details.version}'),
          SailDetailLine(wrap: true, label: 'Lock Time', value: '${details.locktime}'),
        ],
      ),
      const SailDetailHeading('Size'),
      SailDetailGroup(
        fill: SailDetailFill.canvas,
        children: [
          SailDetailLine(wrap: true, label: 'Size', value: sized ? '${details.sizeBytes} bytes' : 'Unknown'),
          SailDetailLine(wrap: true, label: 'Virtual Size', value: sized ? '${details.vsizeVbytes} vbytes' : 'Unknown'),
          SailDetailLine(wrap: true, label: 'Weight', value: sized ? '${details.weightWu} WU' : 'Unknown'),
        ],
      ),
    ];
    final money = [
      const SailDetailHeading('Fee'),
      SailDetailGroup(
        fill: SailDetailFill.canvas,
        children: [
          SailDetailLine(
            wrap: true,
            label: 'Fee',
            value: decoded.hasFee ? formatter.formatSats(details.feeSats.toInt()) : 'Unknown',
          ),
          SailDetailLine(wrap: true, label: 'Fee Rate', value: feeRateText(decoded)),
        ],
      ),
      const SailDetailHeading('Totals'),
      SailDetailGroup(
        fill: SailDetailFill.canvas,
        children: [
          SailDetailLine(
            wrap: true,
            label: 'Total Input',
            value: decoded.hasTotalInput ? formatter.formatSats(details.totalInputSats.toInt()) : 'Unknown',
          ),
          SailDetailLine(
            wrap: true,
            label: 'Total Output',
            value: formatter.formatSats(details.totalOutputSats.toInt()),
          ),
        ],
      ),
    ];
    Widget column(List<Widget> children) => SailColumn(
      spacing: SailStyleValues.padding08,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: SailStyleValues.padding12),
      child: SailStyleValues.phoneLayout(context)
          ? column([...info, ...money])
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: column(info)),
                const SizedBox(width: SailStyleValues.padding12),
                Expanded(child: column(money)),
              ],
            ),
    );
  }
}

class _InputsTable extends StatelessWidget {
  final DecodedTransaction decoded;

  const _InputsTable({required this.decoded});

  @override
  Widget build(BuildContext context) {
    final formatter = GetIt.I<FormatterProvider>();
    final inputs = decoded.details.inputs;

    return SailTable(
      getRowId: (i) => '${inputs[i].prevTxid}:${inputs[i].prevVout}:$i',
      headerBuilder: (_) => [
        SailTableHeaderCell(name: '#'),
        SailTableHeaderCell(name: 'Amount'),
        SailTableHeaderCell(name: 'Address'),
        SailTableHeaderCell(name: 'Previous Output'),
        SailTableHeaderCell(name: 'Sequence'),
      ],
      rowBuilder: (_, i, _) {
        final input = inputs[i];
        final prevOutput = input.isCoinbase
            ? 'Coinbase'
            : '${input.prevTxid.length >= 8 ? input.prevTxid.substring(0, 8) : input.prevTxid}...:${input.prevVout}';
        final hasValue = !input.isCoinbase && (input.valueSats.toInt() != 0 || input.address.isNotEmpty);

        return [
          SailTableCell(value: '${input.index}'),
          SailTableCell(
            value: input.isCoinbase ? 'N/A' : (hasValue ? formatter.formatSats(input.valueSats.toInt()) : 'Unknown'),
            monospace: true,
          ),
          SailTableCell(
            value: input.isCoinbase ? 'Coinbase' : (input.address.isEmpty ? 'Unknown' : input.address),
            monospace: true,
            copyValue: input.address.isNotEmpty ? input.address : null,
          ),
          SailTableCell(
            value: prevOutput,
            monospace: true,
            copyValue: input.isCoinbase ? null : '${input.prevTxid}:${input.prevVout}',
          ),
          SailTableCell(value: '${input.sequence}', monospace: true),
        ];
      },
      rowCount: inputs.length,
      emptyPlaceholder: 'No inputs',
    );
  }
}

class _OutputsTable extends StatelessWidget {
  final DecodedTransaction decoded;

  const _OutputsTable({required this.decoded});

  @override
  Widget build(BuildContext context) {
    final formatter = GetIt.I<FormatterProvider>();
    final outputs = decoded.details.outputs;

    return SailTable(
      getRowId: (i) => '${outputs[i].index}',
      headerBuilder: (_) => [
        SailTableHeaderCell(name: '#'),
        SailTableHeaderCell(name: 'Amount'),
        SailTableHeaderCell(name: 'Address'),
        SailTableHeaderCell(name: 'Type'),
      ],
      rowBuilder: (_, i, _) {
        final output = outputs[i];
        return [
          SailTableCell(value: '${output.index}'),
          SailTableCell(value: formatter.formatSats(output.valueSats.toInt()), monospace: true),
          SailTableCell(
            value: output.address.isEmpty ? 'Unknown' : output.address,
            monospace: true,
            copyValue: output.address.isNotEmpty ? output.address : null,
          ),
          SailTableCell(value: output.scriptType),
        ];
      },
      rowCount: outputs.length,
      emptyPlaceholder: 'No outputs',
    );
  }
}
