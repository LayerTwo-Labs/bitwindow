import 'package:bitwindow/utils/paper_pdf.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sail_ui/sail_ui.dart';

/// Opens the paper wallet: a page on a phone, a dialog on the desktop.
Future<void> showPaperWallet(BuildContext context) async {
  if (SailStyleValues.phoneLayout(context)) {
    await Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        pageBuilder: (_, _, _) => const SailPhonePage(title: 'Paper Wallet', child: PaperWalletDialog()),
      ),
    );
    return;
  }
  await showThemedDialog(context: context, builder: (context) => const PaperWalletDialog());
}

/// Paper Wallet Dialog - Generate offline Bitcoin addresses with QR codes
///
/// Qt equivalent: paperwalletdialog.ui (very minimal in mainchain-deprecated)
/// Size from Qt: 1847x931 (but we'll make it more reasonable)
class PaperWalletDialog extends StatefulWidget {
  const PaperWalletDialog({super.key});

  @override
  State<PaperWalletDialog> createState() => _PaperWalletDialogState();
}

class _PaperWalletDialogState extends State<PaperWalletDialog> {
  GeneratePaperWalletResponse? _keypair;
  bool _isGenerating = false;
  bool _showPrivateKey = false;

  @override
  void initState() {
    super.initState();
    _generateKeypair();
  }

  Future<void> _generateKeypair() async {
    setState(() {
      _isGenerating = true;
      _showPrivateKey = false;
      _keypair = null;
    });

    try {
      final keypair = await GetIt.I.get<BitwindowRPC>().utils.generatePaperWallet();
      if (!mounted) {
        return;
      }
      setState(() => _keypair = keypair);
    } catch (e) {
      if (mounted) {
        showSailToast(context, 'Could not generate a key: ${extractConnectException(e)}');
      }
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }

  void _copyToClipboard(String text, String label, {bool secret = false}) {
    if (secret) {
      copySecretToClipboard(text);
    } else {
      Clipboard.setData(ClipboardData(text: text));
    }
    showSailToast(context, '$label copied to clipboard');
  }

  Future<void> _printPaperWallet() async {
    final keypair = _keypair;
    if (keypair == null) {
      return;
    }

    try {
      final pdf = await GetIt.I.get<BitwindowRPC>().utils.createPaperWalletPdf(
        CreatePaperWalletPdfRequest(
          publicAddress: keypair.publicAddress,
          privateKeyWif: keypair.privateKeyWif,
          addressQr: paperQrMatrix(keypair.publicAddress),
          privateKeyQr: paperQrMatrix(keypair.privateKeyWif),
        ),
      );
      await savePdfAndOpen(pdf, 'paper-wallet.pdf');
    } catch (e) {
      if (mounted) {
        showSailToast(context, 'Could not print the paper wallet: ${extractConnectException(e)}');
      }
    }
  }

  void _toggleKey() => setState(() => _showPrivateKey = !_showPrivateKey);

  List<Widget> _cards(GeneratePaperWalletResponse keypair) => [
    _AddressCard(
      keypair: keypair,
      onCopy: () => _copyToClipboard(keypair.publicAddress, 'Address'),
    ),
    _PrivateKeyCard(
      keypair: keypair,
      showPrivateKey: _showPrivateKey,
      onToggleVisibility: _toggleKey,
      onCopy: () => _copyToClipboard(keypair.privateKeyWif, 'Private key', secret: true),
    ),
  ];

  Widget _phoneBody(BuildContext context) {
    final keypair = _keypair;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: SailColumn(
              spacing: SailStyleValues.padding12,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(child: _SecurityNote()),
                    const SizedBox(width: SailStyleValues.padding08),
                    _PaperWalletMenu(onGenerate: _isGenerating ? null : _generateKeypair),
                  ],
                ),
                if (_isGenerating || keypair == null) const _GeneratingKeypair() else ..._cards(keypair),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: SailStyleValues.padding12),
          child: _SavePdfButton(disabled: _keypair == null || _isGenerating, onSave: _printPaperWallet),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    if (SailStyleValues.phoneLayout(context)) {
      return _phoneBody(context);
    }

    final keypair = _keypair;
    return SailModal(
      child: Container(
        width: 900,
        constraints: const BoxConstraints(maxHeight: 700),
        decoration: BoxDecoration(
          color: theme.colors.backgroundSecondary,
          borderRadius: theme.chrome.radiusLarge,
          border: Border.all(color: theme.colors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(SailStyleValues.padding16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: SailText.primary15('Paper Wallet', bold: true)),
                  _PaperWalletMenu(onGenerate: _isGenerating ? null : _generateKeypair),
                  const SizedBox(width: SailStyleValues.padding08),
                  SailIconBoxButton(
                    icon: SailSVGAsset.x,
                    tooltip: 'Close',
                    onPressed: () async => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: SailStyleValues.padding12),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _SecurityNote(),
                      const SizedBox(height: SailStyleValues.padding12),
                      if (_isGenerating || keypair == null)
                        const _GeneratingKeypair()
                      else
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _cards(keypair)[0]),
                            const SizedBox(width: SailStyleValues.padding12),
                            Expanded(child: _cards(keypair)[1]),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: SailStyleValues.padding16),
              _SavePdfButton(disabled: _keypair == null || _isGenerating, onSave: _printPaperWallet),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaperWalletMenu extends StatelessWidget {
  final VoidCallback? onGenerate;

  const _PaperWalletMenu({required this.onGenerate});

  @override
  Widget build(BuildContext context) => SailRowMenuButton(
    items: () => [
      SailMenuItem(
        onSelected: onGenerate,
        child: SailText.primary12('Generate New'),
      ),
    ],
  );
}

class _SavePdfButton extends StatelessWidget {
  final bool disabled;
  final Future<void> Function() onSave;

  const _SavePdfButton({required this.disabled, required this.onSave});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: SailButton(
      label: 'Save PDF',
      onPressed: () async => onSave(),
      disabled: disabled,
    ),
  );
}

class _GeneratingKeypair extends StatelessWidget {
  const _GeneratingKeypair();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(48),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SailCircularProgressIndicator(color: SailTheme.of(context).colors.primary),
          const SizedBox(height: 16),
          SailText.secondary13('Generating secure keypair...'),
        ],
      ),
    ),
  );
}

class _SecurityNote extends StatelessWidget {
  const _SecurityNote();

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(SailStyleValues.padding12),
      decoration: BoxDecoration(
        color: theme.colors.orange.withValues(alpha: 0.12),
        borderRadius: theme.chrome.radius,
      ),
      child: SailText.primary12(
        'SECURITY: Generate paper wallets on an offline computer. '
        'Never share your private key. Store printed wallet securely.',
      ),
    );
  }
}

/// A bordered card with a colored caption, a QR code, a key field and a line under it.
class _KeyCard extends StatelessWidget {
  final String caption;
  final Color captionColor;
  final Widget qr;
  final String fieldLabel;
  final Widget field;
  final Widget note;

  const _KeyCard({
    required this.caption,
    required this.captionColor,
    required this.qr,
    required this.fieldLabel,
    required this.field,
    required this.note,
  });

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(SailStyleValues.padding16),
      decoration: BoxDecoration(
        color: theme.colors.backgroundSecondary,
        borderRadius: theme.chrome.radiusLarge,
        border: Border.all(color: theme.colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SailText.primary12(caption, bold: true, color: captionColor),
          const SizedBox(height: SailStyleValues.padding12),
          Center(child: qr),
          const SizedBox(height: SailStyleValues.padding16),
          SailText.primary12(fieldLabel),
          const SizedBox(height: SailStyleValues.padding08),
          field,
          const SizedBox(height: SailStyleValues.padding08),
          note,
        ],
      ),
    );
  }
}

/// A read-only value on the field fill with a copy icon at its right end.
class _CopyField extends StatelessWidget {
  final String text;
  final String copyTooltip;
  final VoidCallback onCopy;

  const _CopyField({required this.text, required this.copyTooltip, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    return Container(
      height: 40,
      padding: const EdgeInsets.only(left: SailStyleValues.padding16, right: SailStyleValues.padding08),
      decoration: BoxDecoration(color: theme.colors.formField, borderRadius: theme.chrome.radius),
      child: Row(
        children: [
          Expanded(child: SailText.primary13(text, maxLines: 1, overflow: TextOverflow.ellipsis)),
          SailTooltip(
            message: copyTooltip,
            child: SailTappable(
              onTap: () async => onCopy(),
              borderRadius: theme.chrome.radius,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: SailSVG.fromAsset(SailSVGAsset.iconCopy, width: 16, height: 16, color: theme.colors.text),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddressCard extends StatelessWidget {
  final GeneratePaperWalletResponse keypair;
  final VoidCallback onCopy;

  const _AddressCard({required this.keypair, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    return _KeyCard(
      caption: 'LOAD & VERIFY',
      captionColor: theme.colors.success,
      qr: _PaperQr(data: keypair.publicAddress),
      fieldLabel: 'Public Bitcoin Address',
      field: _CopyField(text: keypair.publicAddress, copyTooltip: 'Copy Address', onCopy: onCopy),
      note: SailText.secondary12('Share this address to receive Bitcoin'),
    );
  }
}

class _PrivateKeyCard extends StatelessWidget {
  final GeneratePaperWalletResponse keypair;
  final bool showPrivateKey;
  final VoidCallback onToggleVisibility;
  final VoidCallback onCopy;

  const _PrivateKeyCard({
    required this.keypair,
    required this.showPrivateKey,
    required this.onToggleVisibility,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    return _KeyCard(
      caption: 'SPEND',
      captionColor: theme.colors.error,
      // The private QR waits for the reveal, like the key text.
      qr: showPrivateKey
          ? _PaperQr(data: keypair.privateKeyWif)
          : SizedBox.square(
              dimension: _PaperQr.size,
              child: Center(
                child: SailSVG.fromAsset(SailSVGAsset.eyeOff, width: 64, color: theme.colors.textTertiary),
              ),
            ),
      fieldLabel: 'Private Key (WIF)',
      field: Row(
        children: [
          Expanded(
            child: _CopyField(
              text: showPrivateKey ? keypair.privateKeyWif : '\u2022' * keypair.privateKeyWif.length,
              copyTooltip: 'Copy Private Key',
              onCopy: onCopy,
            ),
          ),
          const SizedBox(width: SailStyleValues.padding08),
          SailIconBoxButton(
            icon: showPrivateKey ? SailSVGAsset.eyeOff : SailSVGAsset.eye,
            tooltip: showPrivateKey ? 'Hide private key' : 'Show private key',
            size: 40,
            onPressed: () async => onToggleVisibility(),
          ),
        ],
      ),
      note: showPrivateKey
          ? SailText.primary12(
              'KEEP SECRET: Anyone with this private key can spend your Bitcoin',
              color: theme.colors.error,
            )
          : SailText.secondary12('Click the eye icon to reveal'),
    );
  }
}

class _PaperQr extends StatelessWidget {
  static const size = 148.0;

  final String data;

  const _PaperQr({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    return QrImageView(
      data: data,
      version: QrVersions.auto,
      size: size,
      padding: EdgeInsets.zero,
      eyeStyle: QrEyeStyle(color: theme.colors.text, eyeShape: QrEyeShape.square),
      dataModuleStyle: QrDataModuleStyle(color: theme.colors.text),
      backgroundColor: theme.colors.backgroundSecondary,
    );
  }
}
