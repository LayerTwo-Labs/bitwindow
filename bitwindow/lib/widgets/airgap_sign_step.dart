import 'dart:convert';
import 'dart:io';

import 'package:bitwindow/signing/psbt_text.dart';
import 'package:bitwindow/widgets/animated_ur_qr.dart';
import 'package:bitwindow/widgets/ur_qr_scanner.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:sail_ui/sail_ui.dart';

enum _Stage { export, import }

/// Airgap round-trip: export an unsigned PSBT, then ingest the signed PSBT and
/// hand it back via [onSigned].
class AirgapSignStep extends StatefulWidget {
  final String unsignedPsbtBase64;
  final void Function(String signedPsbtBase64) onSigned;
  final void Function() onCancel;

  /// Why the owner refused the last signed PSBT.
  final String? error;

  /// The owner works on the signed PSBT.
  final bool busy;

  const AirgapSignStep({
    super.key,
    required this.unsignedPsbtBase64,
    required this.onSigned,
    required this.onCancel,
    this.error,
    this.busy = false,
  });

  @override
  State<AirgapSignStep> createState() => _AirgapSignStepState();
}

class _AirgapSignStepState extends State<AirgapSignStep> {
  _Stage _stage = _Stage.export;
  final TextEditingController _signedController = TextEditingController();
  bool _scanning = false;
  String? _error;

  @override
  void dispose() {
    _signedController.dispose();
    super.dispose();
  }

  Uint8List get _unsignedBytes => base64.decode(widget.unsignedPsbtBase64);

  Future<void> _copyUnsigned() async {
    await Clipboard.setData(ClipboardData(text: widget.unsignedPsbtBase64));
    if (mounted) {
      showSailToast(context, 'Unsigned PSBT copied', variant: SailToastVariant.success);
    }
  }

  Future<void> _saveUnsigned() async {
    final path = await FilePicker.saveFile(
      dialogTitle: 'Save Unsigned PSBT',
      fileName: 'unsigned_${DateTime.now().millisecondsSinceEpoch}.psbt',
      bytes: _unsignedBytes,
    );
    if (path == null) {
      return;
    }
    if (mounted) {
      showSailToast(context, 'Saved unsigned PSBT', variant: SailToastVariant.success);
    }
  }

  Future<void> _loadSignedFile() async {
    setState(() => _error = null);
    try {
      final result = await FilePicker.pickFile(
        dialogTitle: 'Select Signed PSBT',
        type: FileType.any,
      );
      if (result?.path == null) {
        return;
      }
      final file = File(result!.path!);
      final bytes = await file.readAsBytes();
      // A .psbt is raw binary (magic 0x70736274ff); text exports are base64.
      final isBinary =
          bytes.length >= 5 &&
          bytes[0] == 0x70 &&
          bytes[1] == 0x73 &&
          bytes[2] == 0x62 &&
          bytes[3] == 0x74 &&
          bytes[4] == 0xff;
      final text = isBinary ? base64.encode(bytes) : utf8.decode(bytes).trim();
      setState(() => _signedController.text = text);
    } catch (e) {
      setState(() => _error = 'Could not read file: $e');
    }
  }

  void _onScanned(String psbtBase64) {
    setState(() {
      _signedController.text = psbtBase64;
      _scanning = false;
      _error = null;
    });
    widget.onSigned(psbtBase64);
  }

  void _confirmSigned() {
    final signed = _signedController.text.replaceAll(RegExp(r'\s'), '');
    if (signed.isEmpty) {
      setState(() => _error = 'Provide the signed PSBT first');
      return;
    }
    if (!isBase64Psbt(signed)) {
      setState(() => _error = 'Not a valid base64 PSBT');
      return;
    }
    setState(() => _error = null);
    widget.onSigned(signed);
  }

  @override
  Widget build(BuildContext context) {
    return SailCard(
      title: 'External signer (airgap)',
      subtitle: _stage == _Stage.export ? 'Show this unsigned PSBT to your signer' : 'Import the signed PSBT',
      error: _error ?? (_stage == _Stage.import ? widget.error : null),
      child: _stage == _Stage.export
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: SingleChildScrollView(child: AnimatedURQR(psbt: _unsignedBytes)),
                ),
                const SailSpacing(SailStyleValues.padding08),
                _exportFileActions(),
                const SailSpacing(SailStyleValues.padding08),
                Divider(height: 1, color: context.sailTheme.colors.divider),
                const SailSpacing(SailStyleValues.padding08),
                _exportActions(),
              ],
            )
          : SingleChildScrollView(child: _importBody()),
    );
  }

  Widget _exportFileActions() {
    return SailRow(
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: SailStyleValues.padding08,
      children: [
        SailButton(label: 'Copy base64', variant: ButtonVariant.secondary, onPressed: _copyUnsigned),
        SailButton(label: 'Save .psbt', variant: ButtonVariant.secondary, onPressed: _saveUnsigned),
      ],
    );
  }

  Widget _exportActions() {
    return SailRow(
      mainAxisAlignment: MainAxisAlignment.end,
      spacing: SailStyleValues.padding08,
      children: [
        SailButton(
          label: 'Cancel',
          variant: ButtonVariant.ghost,
          onPressed: () async => widget.onCancel(),
        ),
        SailButton(
          label: 'Next: import signed',
          onPressed: () async => setState(() => _stage = _Stage.import),
        ),
      ],
    );
  }

  Widget _importBody() {
    return SailColumn(
      spacing: SailStyleValues.padding16,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_scanning)
          Center(
            child: URQrScanner(onComplete: _onScanned),
          )
        else ...[
          if (urCameraScanSupported)
            SailButton(
              label: 'Scan signed QR',
              onPressed: () async => setState(() => _scanning = true),
            ),
          SailButton(
            label: 'Load from file',
            variant: ButtonVariant.secondary,
            onPressed: _loadSignedFile,
          ),
          SailTextField(
            controller: _signedController,
            label: 'Or paste signed PSBT (base64)',
            hintText: 'cHNidP8B...',
            minLines: 3,
            maxLines: 6,
            monospace: true,
          ),
          SailRow(
            mainAxisAlignment: MainAxisAlignment.end,
            spacing: SailStyleValues.padding08,
            children: [
              SailButton(
                label: 'Back',
                variant: ButtonVariant.ghost,
                disabled: widget.busy,
                onPressed: () async => setState(() => _stage = _Stage.export),
              ),
              SailButton(
                label: 'Confirm signed',
                loading: widget.busy,
                onPressed: () async => _confirmSigned(),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
