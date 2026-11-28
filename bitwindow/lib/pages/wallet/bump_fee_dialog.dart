import 'dart:async';

import 'package:bitwindow/pages/wallet/bump_fee_choices.dart';
import 'package:bitwindow/providers/transactions_provider.dart';
import 'package:bitwindow/utils/fee_estimation.dart';
import 'package:bitwindow/widgets/send_panel_parts.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/gen/walletmanager/v1/walletmanager.pb.dart' as wmpb;

/// Replaces an unconfirmed transaction with one that pays a higher fee. The
/// preview comes from the backend, so the fee, the size and the output that
/// pays are the wallet's own numbers.
class BumpFeeDialog extends StatefulWidget {
  final String txid;

  const BumpFeeDialog({super.key, required this.txid});

  @override
  State<BumpFeeDialog> createState() => _BumpFeeDialogState();
}

class _BumpFeeDialogState extends State<BumpFeeDialog> {
  OrchestratorWalletRPC get _wallet => GetIt.I.get<OrchestratorRPC>().wallet;
  TransactionProvider get _transactions => GetIt.I.get<TransactionProvider>();
  WalletReaderProvider get _walletReader => GetIt.I.get<WalletReaderProvider>();

  final TextEditingController _rateController = TextEditingController();
  DateTime _rateChangedAt = DateTime.now();

  wmpb.PreviewBumpFeeResponse? _preview;
  int? _feeFromVout;
  // Counts the previews asked for. A slower answer to an older question must
  // not overwrite the newer one the user reads.
  int _requestId = 0;
  bool _loading = true;
  bool _replacing = false;
  bool _confirmCancel = false;
  // Set when a preview fails: the plan on screen answers an older question.
  bool _stale = false;
  bool _pickOutput = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPreview());
  }

  @override
  void dispose() {
    _rateController.dispose();
    super.dispose();
  }

  String _feeError(Object error) {
    if (isExpectedBootError(error)) {
      return 'Could not read the mempool. Check Daemon Status, then try again.';
    }
    return extractConnectException(error);
  }

  int? get _rate {
    final rate = int.tryParse(_rateController.text.trim());
    if (rate == null || rate <= 0) {
      return null;
    }
    return rate;
  }

  /// A failure of a preview for a typed rate shows when the rate stayed the
  /// same for [feePreviewErrorDelay].
  Future<void> _loadPreview({bool typed = false}) async {
    final requestId = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final walletId = _walletReader.activeWalletId;
      if (walletId == null) {
        throw Exception('No active wallet');
      }
      final preview = await _wallet.previewBumpFee(
        walletId: walletId,
        txid: widget.txid,
        newFeeRate: _rate,
        feeFromVout: _feeFromVout,
      );
      if (!mounted || requestId != _requestId) {
        return;
      }
      final first = _preview == null;
      setState(() {
        _preview = preview;
        _stale = false;
        _loading = false;
        if (first && _rateController.text.isEmpty) {
          _rateController.text = preview.suggestedFeeRate.toString();
        }
      });
    } catch (e) {
      if (!mounted || requestId != _requestId) {
        return;
      }
      void showError() => setState(() {
        _error = _feeError(e);
        // The plan on screen belongs to a question this one failed to answer.
        // It stays visible, but it cannot broadcast anything.
        _stale = true;
        _loading = false;
      });
      final wait = feePreviewErrorWait(_rateChangedAt);
      if (!typed || wait <= Duration.zero) {
        showError();
        return;
      }
      Timer(wait, () {
        if (mounted && requestId == _requestId) {
          showError();
        }
      });
    }
  }

  void _onRateChanged(String _) {
    _rateChangedAt = DateTime.now();
    // The plan on screen belongs to the rate before this keystroke, and so does
    // any answer still in flight. Both go stale here, or a fast press
    // broadcasts a fee the user never read.
    setState(() {
      _requestId++;
      _loading = true;
      _stale = false;
      _error = null;
    });
    unawaited(_loadPreview(typed: true));
  }

  Future<void> _selectOutput(int vout) async {
    setState(() => _feeFromVout = vout);
    await _loadPreview();
  }

  Future<void> _replace() async {
    setState(() {
      _replacing = true;
      _error = null;
    });
    try {
      final walletId = _walletReader.activeWalletId;
      if (walletId == null) {
        throw Exception('No active wallet');
      }
      final result = await _wallet.bumpFee(
        walletId: walletId,
        txid: widget.txid,
        newFeeRate: _rate,
        feeFromVout: _feeFromVout,
      );
      if (!mounted) {
        GetIt.I<Logger>().i('replaced ${widget.txid} with ${result.newTxid}');
        return;
      }
      showSailToast(context, 'Replaced. New txid: ${result.newTxid}', variant: SailToastVariant.success);
      Navigator.of(context).pop();
      // The network holds the replacement already. A refresh that fails changes
      // nothing about that, so it never reports the send as failed.
      unawaited(_transactions.fetch());
    } catch (e) {
      if (!mounted) {
        GetIt.I<Logger>().e('failed to replace ${widget.txid}: $e');
        return;
      }
      setState(() {
        _error = _feeError(e);
        _replacing = false;
      });
    }
  }

  Future<void> _cancel(wmpb.CancelPlan cancel) async {
    setState(() {
      _replacing = true;
      _error = null;
    });
    try {
      final walletId = _walletReader.activeWalletId;
      if (walletId == null) {
        throw Exception('No active wallet');
      }
      final result = await _wallet.cancelTransaction(
        walletId: walletId,
        txid: widget.txid,
        maxFeeSats: cancel.feeSats.toInt(),
      );
      if (!mounted) {
        GetIt.I<Logger>().i('cancelled ${widget.txid} with ${result.replacementTxid}');
        return;
      }
      showSailToast(context, 'Cancelled. New txid: ${result.replacementTxid}', variant: SailToastVariant.success);
      Navigator.of(context).pop();
      // The network holds the cancel already. A refresh that fails changes
      // nothing about that.
      unawaited(_transactions.fetch());
    } catch (e) {
      if (!mounted) {
        GetIt.I<Logger>().e('failed to cancel ${widget.txid}: $e');
        return;
      }
      setState(() {
        _error = _feeError(e);
        _replacing = false;
      });
    }
  }

  Future<void> _accelerate() async {
    Navigator.of(context).pop(BumpFeeOutcome.accelerate);
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final plan = preview != null && preview.hasPlan() ? preview.plan : null;
    final choices = preview == null ? null : BumpFeeChoices.of(preview, pickOutput: _pickOutput);
    // Core adds a coin when the change cannot pay, so it replaces the
    // transaction even with no plan to show.
    final hasWay = plan != null || (choices?.replaceWithoutPlan ?? false);
    final canReplace = hasWay && !_loading && !_replacing && !_stale;

    if (_confirmCancel && preview != null && preview.hasCancel()) {
      return _cancelConfirmation(preview.cancel);
    }

    final replace = choices != null && choices.showReplace
        ? SailButton(
            label: _replacing ? 'Replacing...' : 'Replace transaction',
            onPressed: _replace,
            disabled: !canReplace,
          )
        : null;
    final accelerate = choices != null && choices.showAccelerate && replace == null
        ? SailButton(label: 'Accelerate (CPFP)', onPressed: _accelerate, disabled: _replacing)
        : null;

    List<SailMenuEntity> menu() => [
      if (choices != null && choices.showCancel)
        sendMenuItem(
          context,
          'Cancel transaction',
          _replacing || _loading || _stale ? null : () => setState(() => _confirmCancel = true),
        ),
      if (choices != null && choices.showOverride)
        sendMenuItem(context, 'I want to RBF it', _replacing ? null : () => setState(() => _pickOutput = true)),
      if (choices != null && choices.showAccelerate && replace != null)
        sendMenuItem(context, 'Accelerate (CPFP)', _replacing ? null : () => unawaited(_accelerate())),
    ];
    final hasMenu =
        choices != null && (choices.showCancel || choices.showOverride || (choices.showAccelerate && replace != null));
    final failed = preview == null && !_loading && _error != null;

    return PopScope(
      canPop: !_replacing,
      child: SignDialog(
        title: 'Bump the fee',
        maxWidth: 520,
        busy: _replacing,
        menuItems: hasMenu ? menu : null,
        // A failed first preview still shows the action it blocks.
        button: failed
            ? const SailButton(label: 'Replace transaction', onPressed: null, disabled: true)
            : replace ?? accelerate,
        child: failed
            ? SailInlineError(_error!)
            : _loading && preview == null
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(child: LoadingIndicator()),
                  ),
                  if (_error != null) SailInlineError(_error!),
                ],
              )
            : SailColumn(
                spacing: SailStyleValues.padding12,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (preview != null) ..._transactionDetails(preview),
                  if (preview != null) ..._newFee(preview),
                  if (_loading && preview != null && !_replacing)
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox.square(dimension: 16, child: LoadingIndicator()),
                    ),
                  if (_error != null) SailInlineError(_error!),
                ],
              ),
      ),
    );
  }

  Widget _cancelConfirmation(wmpb.CancelPlan cancel) {
    final formatter = GetIt.I<FormatterProvider>();
    return PopScope(
      canPop: !_replacing,
      child: SignDialog(
        title: 'Cancel the transaction',
        maxWidth: 520,
        busy: _replacing,
        onBack: () async => setState(() => _confirmCancel = false),
        button: SailButton(
          label: _replacing ? 'Cancelling...' : 'Cancel transaction',
          onPressed: () => _cancel(cancel),
          variant: ButtonVariant.destructive,
          disabled: _replacing,
        ),
        child: SailColumn(
          spacing: SailStyleValues.padding12,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SailDetailGroup(
              fill: SailDetailFill.canvas,
              children: [SailStackedDetail(label: 'Transaction ID', value: widget.txid)],
            ),
            SailDetailGroup(
              fill: SailDetailFill.canvas,
              children: [
                SailDetailLine(
                  label: 'Returns to this wallet',
                  value: formatter.formatSats(cancel.recoveredSats.toInt()),
                ),
                SailDetailLine(label: 'Fee', value: formatter.formatSats(cancel.feeSats.toInt())),
              ],
            ),
            if (_error != null) SailInlineError(_error!),
          ],
        ),
      ),
    );
  }

  List<Widget> _transactionDetails(wmpb.PreviewBumpFeeResponse preview) {
    final formatter = GetIt.I<FormatterProvider>();
    return [
      SailText.primary13('This transaction', bold: true),
      SailDetailGroup(
        fill: SailDetailFill.canvas,
        children: [SailStackedDetail(label: 'Transaction ID', value: widget.txid)],
      ),
      SailDetailGroup(
        fill: SailDetailFill.canvas,
        children: [
          SailDetailLine(label: 'Inputs', value: '${preview.inputCount} coins · ${preview.vsizeVbytes} vB'),
          SailDetailLine(
            label: 'Fee now',
            value:
                '${formatter.formatSats(preview.oldFeeSats.toInt())} · '
                '${preview.oldFeeRateSatVb.toStringAsFixed(1)} ${activeTicker.feeRate}',
          ),
        ],
      ),
    ];
  }

  List<Widget> _newFee(wmpb.PreviewBumpFeeResponse preview) {
    final formatter = GetIt.I<FormatterProvider>();
    final plan = preview.hasPlan() ? preview.plan : null;
    final theme = SailTheme.of(context);

    return [
      SailText.primary13('New fee', bold: true),
      SailRow(
        spacing: SailStyleValues.padding08,
        children: [
          Expanded(
            child: SailTextField(
              controller: _rateController,
              textFieldType: TextFieldType.number,
              hintText: preview.suggestedFeeRate.toString(),
              enabled: !_replacing,
              onChanged: _onRateChanged,
              suffixWidget: SailText.secondary13(activeTicker.feeRate),
            ),
          ),
          SailDropdownButton<int>(
            value: null,
            hint: 'Estimate',
            items: [
              SailDropdownItem(value: 1, label: 'Fast · 1 block'),
              SailDropdownItem(value: 3, label: 'Medium · 3 blocks'),
              SailDropdownItem(value: 6, label: 'Slow · 6 blocks'),
            ],
            onChanged: (confTarget) => unawaited(_applyEstimate(confTarget)),
          ),
        ],
      ),
      if (plan != null)
        SailDetailGroup(
          fill: SailDetailFill.canvas,
          children: [
            SailDetailLine(
              label: 'New fee',
              value:
                  '${formatter.formatSats(plan.newFeeSats.toInt())} · '
                  '${plan.newFeeRateSatVb.toStringAsFixed(1)} ${activeTicker.feeRate}',
            ),
            SailDetailLine(label: 'You pay more', value: formatter.formatSats(plan.extraFeeSats.toInt())),
            SailDetailLine(
              label: 'Output ${plan.feeFromVout} · ${plan.reducesPayment ? 'payment' : 'change'}',
              value: plan.outputRemoved
                  ? '${formatter.formatSats(plan.amountBeforeSats.toInt())} → goes away'
                  : '${formatter.formatSats(plan.amountBeforeSats.toInt())} → '
                        '${formatter.formatSats(plan.amountAfterSats.toInt())}',
            ),
          ],
        ),
      if (plan != null && plan.reducesPayment)
        SailText.primary13(
          'The recipient of output ${plan.feeFromVout} gets '
          '${formatter.formatSats(plan.extraFeeSats.toInt())} less.',
          color: theme.colors.orange,
          overflow: TextOverflow.visible,
        ),
      if (preview.reason.isNotEmpty) SailInlineError(BumpFeeChoices.of(preview, pickOutput: _pickOutput).reason),
      if (_pickOutput) ..._outputPicker(preview),
    ];
  }

  List<Widget> _outputPicker(wmpb.PreviewBumpFeeResponse preview) {
    final formatter = GetIt.I<FormatterProvider>();
    final theme = SailTheme.of(context);
    return [
      SailText.primary13('Take the fee from', bold: true),
      SailDetailGroup(
        fill: SailDetailFill.canvas,
        children: [
          for (final output in preview.outputs.where((o) => o.address.isNotEmpty))
            SailRow(
              spacing: SailStyleValues.padding08,
              children: [
                SailRadioButton<int>(
                  value: output.vout,
                  groupValue: _feeFromVout ?? (preview.hasPlan() ? preview.plan.feeFromVout : -1),
                  onChanged: _replacing ? null : (vout) => unawaited(_selectOutput(vout)),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SailText.primary13(
                        'Output ${output.vout} · ${output.isChange ? 'change' : 'payment'}',
                        bold: true,
                      ),
                      SailText.primary12(output.address, color: theme.colors.textSecondary, monospace: true),
                    ],
                  ),
                ),
                SailText.primary13(formatter.formatSats(output.amountSats.toInt())),
              ],
            ),
        ],
      ),
    ];
  }

  Future<void> _applyEstimate(int? confTarget) async {
    if (confTarget == null || _replacing) {
      return;
    }
    setState(() {
      _requestId++;
      _loading = true;
      _stale = false;
      _error = null;
    });
    double? rate;
    try {
      rate = await feeRateForTarget(confTarget);
    } catch (e) {
      rate = null;
    }
    if (!mounted) {
      return;
    }
    if (rate == null) {
      setState(() {
        _error = 'No fee estimate for $confTarget blocks. Type a rate instead.';
        _loading = false;
        _stale = true;
      });
      return;
    }
    _rateController.text = rate.ceil().toString();
    await _loadPreview();
  }
}

/// What the user chose when the dialog cannot build a replacement.
enum BumpFeeOutcome { accelerate }
