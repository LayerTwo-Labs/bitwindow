import 'package:bitwindow/models/multisig_group.dart';
import 'package:bitwindow/models/multisig_transaction.dart';
import 'package:bitwindow/widgets/create_multisig_modal.dart';
import 'package:bitwindow/widgets/send_panel_parts.dart';
import 'package:flutter/widgets.dart';
import 'package:sail_ui/sail_ui.dart';

class SignPreviewModal extends StatefulWidget {
  final MultisigTransaction transaction;
  final MultisigGroup group;
  final Future<void> Function() onSignConfirm;

  const SignPreviewModal({
    super.key,
    required this.transaction,
    required this.group,
    required this.onSignConfirm,
  });

  @override
  State<SignPreviewModal> createState() => _SignPreviewModalState();
}

class _SignPreviewModalState extends State<SignPreviewModal> {
  bool _isSigning = false;

  Future<void> _handleSign() async {
    setState(() => _isSigning = true);

    try {
      await widget.onSignConfirm();
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() => _isSigning = false);
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tx = widget.transaction;
    final group = widget.group;

    final unsignedWalletKeys = group.keys
        .where((key) => key.isWallet)
        .where((key) => !tx.keyPSBTs.any((kp) => kp.keyId == key.xpub && kp.isSigned))
        .toList();

    return SignDialog(
      title: 'Sign Transaction Preview',
      subtitle: 'Review transaction details before signing',
      maxWidth: 600,
      busy: _isSigning,
      button: SailButton(
        label: 'Sign Transaction',
        onPressed: _isSigning || unsignedWalletKeys.isEmpty ? null : _handleSign,
        loading: _isSigning,
      ),
      child: SailColumn(
        mainAxisSize: MainAxisSize.min,
        spacing: SailStyleValues.padding16,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SailDetailGroup(
            fill: SailDetailFill.canvas,
            title: 'Transaction Details',
            children: [
              SailDetailLine(label: 'Transaction ID', value: tx.shortId),
              SailDetailLine(label: 'Group', value: group.name),
              SailDetailLine(label: 'Amount', value: '${tx.amount.toStringAsFixed(8)} ${activeTicker.symbol}'),
              SailDetailLine(label: 'Fee', value: '${tx.fee.toStringAsFixed(8)} ${activeTicker.symbol}'),
              _StackedRow(label: 'Destination', value: tx.destination),
            ],
          ),
          SailDetailGroup(
            fill: SailDetailFill.canvas,
            title: 'Signing Information',
            children: [
              SailDetailLine(label: 'Current Signatures', value: '${tx.signatureCount}/${group.m}'),
              SailDetailLine(label: 'Wallet Keys Available', value: '${unsignedWalletKeys.length}'),
              if (unsignedWalletKeys.isNotEmpty)
                SailDetailLine(
                  label: 'Keys to be signed',
                  value: unsignedWalletKeys.map((k) => k.owner).join(', '),
                ),
            ],
          ),
          SailDetailGroup(
            fill: SailDetailFill.canvas,
            title: 'Key Status',
            children: [for (final key in group.keys) _KeyStatusRow(transaction: tx, signer: key)],
          ),
        ],
      ),
    );
  }
}

class _StackedRow extends StatelessWidget {
  final String label;
  final String value;

  const _StackedRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SailText.primary13(label, color: SailTheme.of(context).colors.textSecondary),
        const SizedBox(height: 2),
        SailText.primary13(value, monospace: true, overflow: TextOverflow.visible),
      ],
    );
  }
}

/// What a key did with the transaction, and the tone of its status dot.
({String label, SailStatusTone tone}) keyStatus(MultisigTransaction transaction, MultisigKey key) {
  final keyPSBT = transaction.keyPSBTs.where((kp) => kp.keyId == key.xpub).firstOrNull;
  if (keyPSBT?.isSigned ?? false) {
    return (label: 'Signed', tone: SailStatusTone.success);
  }
  if (keyPSBT?.psbt == null) {
    return (label: 'No PSBT available', tone: SailStatusTone.neutral);
  }
  if (key.isWallet) {
    return (label: 'Ready to sign', tone: SailStatusTone.warning);
  }
  return (label: 'Awaiting external signature', tone: SailStatusTone.neutral);
}

class _KeyStatusRow extends StatelessWidget {
  final MultisigTransaction transaction;
  final MultisigKey signer;

  const _KeyStatusRow({required this.transaction, required this.signer});

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    final status = keyStatus(transaction, signer);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SailText.primary13(signer.owner, bold: true),
              if (signer.isWallet) SailText.secondary12('Wallet Key'),
            ],
          ),
        ),
        SailStatusDot(tone: status.tone),
        const SizedBox(width: 6),
        SailText.primary13(status.label, color: theme.colors.text),
      ],
    );
  }
}
