import 'package:bitwindow/signing/sign_and_broadcast.dart';
import 'package:bitwindow/widgets/airgap_sign_step.dart';
import 'package:flutter/widgets.dart';
import 'package:sail_ui/sail_ui.dart';

/// Single-sig external-signer (airgap) flow: produce the signed PSBT via
/// [AirgapSignStep], then combine, finalize and broadcast it.
class AirgapPsbtDialog extends StatefulWidget {
  /// The wallet whose chain broadcasts the transaction.
  final String walletId;
  final String unsignedPsbtBase64;

  /// Called with the broadcast txid on success.
  final void Function(String txid)? onBroadcast;

  const AirgapPsbtDialog({
    super.key,
    required this.walletId,
    required this.unsignedPsbtBase64,
    this.onBroadcast,
  });

  @override
  State<AirgapPsbtDialog> createState() => _AirgapPsbtDialogState();
}

class _AirgapPsbtDialogState extends State<AirgapPsbtDialog> {
  bool _broadcasting = false;
  String? _error;

  Future<void> _finalizeAndBroadcast(String signedPsbtBase64) async {
    if (_broadcasting) {
      return;
    }
    setState(() {
      _broadcasting = true;
      _error = null;
    });
    try {
      final txid = await broadcastSignedPsbt(
        walletId: widget.walletId,
        unsignedPsbtBase64: widget.unsignedPsbtBase64,
        signedPsbtBase64: signedPsbtBase64,
      );

      widget.onBroadcast?.call(txid);

      if (mounted) {
        showSailToast(context, 'Transaction broadcast', variant: SailToastVariant.success);
        Navigator.of(context).pop(true);
      }
    } on SignedPsbtException catch (e) {
      _fail(e.message);
    } catch (e) {
      _fail('Failed to broadcast: ${extractConnectException(e)}');
    }
  }

  void _fail(String error) {
    if (!mounted) {
      return;
    }
    setState(() {
      _broadcasting = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SailModal(
      constraints: const BoxConstraints(maxWidth: 560, maxHeight: 760),
      child: AirgapSignStep(
        unsignedPsbtBase64: widget.unsignedPsbtBase64,
        onSigned: _finalizeAndBroadcast,
        onCancel: () => Navigator.of(context).pop(false),
        error: _error,
        busy: _broadcasting,
      ),
    );
  }
}
