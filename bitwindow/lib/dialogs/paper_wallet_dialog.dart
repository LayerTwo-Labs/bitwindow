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

  Widget _phoneBody(BuildContext context) {
    final theme = SailTheme.of(context);
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
                Container(
                  padding: const EdgeInsets.all(SailStyleValues.padding12),
                  decoration: BoxDecoration(
                    color: theme.colors.orange.withValues(alpha: 0.12),
                    borderRadius: context.sailTheme.chrome.radiusSmall,
                  ),
                  child: SailText.secondary12(
                    'SECURITY: Generate paper wallets on an offline computer. '
                    'Never share your private key. Store printed wallet securely.',
                    color: theme.colors.text,
                  ),
                ),
                if (_isGenerating || keypair == null)
                  Padding(
                    padding: const EdgeInsets.all(48),
                    child: Center(child: SailCircularProgressIndicator(color: theme.colors.primary)),
                  )
                else ...[
                  _AddressPanel(
                    keypair: keypair,
                    showPrivateKey: false,
                    onCopy: () => _copyToClipboard(keypair.publicAddress, 'Address'),
                    phone: true,
                  ),
                  _PrivateKeyPanel(
                    keypair: keypair,
                    showPrivateKey: _showPrivateKey,
                    onToggleVisibility: () => setState(() => _showPrivateKey = !_showPrivateKey),
                    onCopy: () => _copyToClipboard(keypair.privateKeyWif, 'Private key', secret: true),
                    phone: true,
                  ),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: SailStyleValues.padding12),
          child: SailRow(
            spacing: SailStyleValues.padding08,
            children: [
              SailButton(
                label: 'Generate New',
                variant: ButtonVariant.secondary,
                onPressed: () async => _generateKeypair(),
                loading: _isGenerating,
              ),
              const Spacer(),
              SailButton(
                label: 'Save PDF',
                variant: ButtonVariant.outline,
                onPressed: () async => _printPaperWallet(),
                disabled: keypair == null || _isGenerating,
              ),
              SailButton(label: 'Close', onPressed: () async => Navigator.of(context).pop()),
            ],
          ),
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

    // Qt dialog size: 1847x931, but we'll use something more reasonable
    return SailModal(
      child: Container(
        width: 900, // Reasonable width for modern displays
        constraints: const BoxConstraints(maxHeight: 700),
        decoration: BoxDecoration(
          color: theme.colors.backgroundSecondary,
          borderRadius: context.sailTheme.chrome.radiusSmall,
          border: Border.all(color: theme.colors.border, width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header - matches Qt dialog title bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: theme.colors.border),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SailText.primary20('Paper Wallet'), // Qt windowTitle
                  SailTappable(
                    onTap: () async => Navigator.of(context).pop(),
                    borderRadius: context.sailTheme.chrome.radiusSmall,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: SailSVG.fromAsset(SailSVGAsset.x, color: theme.colors.text),
                    ),
                  ),
                ],
              ),
            ),

            // Content - Qt QVBoxLayout
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Security warning (not in Qt, but important)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colors.actionHeader,
                        borderRadius: context.sailTheme.chrome.radiusSmall,
                        border: Border.all(color: theme.colors.orangeLight),
                      ),
                      child: Row(
                        children: [
                          SailSVG.fromAsset(SailSVGAsset.triangleAlert, width: 20, color: theme.colors.orange),
                          const SizedBox(width: 12),
                          Expanded(
                            child: SailText.secondary12(
                              'SECURITY: Generate paper wallets on an offline computer. '
                              'Never share your private key. Store printed wallet securely.',
                              color: theme.colors.orange,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    if (_isGenerating || _keypair == null)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(48),
                          child: Column(
                            children: [
                              SailCircularProgressIndicator(color: theme.colors.primary),
                              const SizedBox(height: 16),
                              SailText.secondary13('Generating secure keypair...'),
                            ],
                          ),
                        ),
                      )
                    else
                      // Wallet Content
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Left side - Public Address (for receiving)
                          Expanded(
                            child: _AddressPanel(
                              keypair: _keypair!,
                              showPrivateKey: false,
                              onCopy: () => _copyToClipboard(_keypair!.publicAddress, 'Address'),
                            ),
                          ),
                          const SizedBox(width: 24),
                          // Right side - Private Key (for spending)
                          Expanded(
                            child: _PrivateKeyPanel(
                              keypair: _keypair!,
                              showPrivateKey: _showPrivateKey,
                              onToggleVisibility: () {
                                setState(() {
                                  _showPrivateKey = !_showPrivateKey;
                                });
                              },
                              onCopy: () => _copyToClipboard(_keypair!.privateKeyWif, 'Private key', secret: true),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),

            // Footer buttons - Qt pushButtonPrint equivalent
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: theme.colors.border),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SailButton(
                    label: 'Generate New',
                    variant: ButtonVariant.secondary,
                    onPressed: () async => _generateKeypair(),
                    loading: _isGenerating,
                  ),
                  Row(
                    children: [
                      SailButton(
                        label: 'Save PDF', // Qt pushButtonPrint
                        onPressed: () async => _printPaperWallet(),
                        disabled: _keypair == null || _isGenerating,
                      ),
                      const SizedBox(width: 12),
                      SailButton(
                        label: 'Close',
                        variant: ButtonVariant.secondary,
                        onPressed: () async => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Widget for displaying the public address panel
class _AddressPanel extends StatelessWidget {
  final GeneratePaperWalletResponse keypair;
  final bool showPrivateKey;
  final VoidCallback onCopy;
  final bool phone;

  const _AddressPanel({
    required this.keypair,
    required this.showPrivateKey,
    required this.onCopy,
    this.phone = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    if (phone) {
      return _PhoneKeyCard(
        title: SailText.primary15('LOAD & VERIFY', bold: true),
        subtitle: 'Public Bitcoin Address',
        children: [
          _PaperQr(data: keypair.publicAddress),
          SailSelectableText(
            keypair.publicAddress,
            style: TextStyle(fontSize: 12, color: theme.colors.text),
            textAlign: TextAlign.center,
          ),
          SailButton(
            label: 'Copy Address',
            variant: ButtonVariant.secondary,
            small: true,
            onPressed: () async => onCopy(),
          ),
          SailText.secondary12('Share this address to receive Bitcoin', textAlign: TextAlign.center),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colors.background,
        borderRadius: context.sailTheme.chrome.radiusSmall,
        border: Border.all(color: theme.colors.success, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SailSVG.fromAsset(SailSVGAsset.wallet, width: 24, color: theme.colors.success),
              const SizedBox(width: 8),
              SailText.primary15('LOAD & VERIFY', bold: true),
            ],
          ),
          const SizedBox(height: 8),
          SailText.secondary12(
            'Public Bitcoin Address',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),

          // QR Code
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colors.backgroundSecondary,
              borderRadius: context.sailTheme.chrome.radiusSmall,
            ),
            child: QrImageView(
              data: keypair.publicAddress,
              version: QrVersions.auto,
              size: 200,
              padding: EdgeInsets.zero,
              eyeStyle: QrEyeStyle(
                color: theme.colors.text,
                eyeShape: QrEyeShape.square,
              ),
              dataModuleStyle: QrDataModuleStyle(color: theme.colors.text),
              backgroundColor: theme.colors.backgroundSecondary,
            ),
          ),
          const SizedBox(height: 16),

          // Address text
          SailSelectableText(
            keypair.publicAddress,
            style: TextStyle(
              fontFamily: SailFonts.mono,
              fontSize: 11,
              color: theme.colors.text,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),

          // Copy button
          SailButton(
            label: 'Copy Address',
            variant: ButtonVariant.secondary,
            onPressed: () async => onCopy(),
          ),
          const SizedBox(height: 16),

          // Instructions
          SailText.secondary12(
            'Share this address to receive Bitcoin',
            textAlign: TextAlign.center,
            color: theme.colors.textSecondary,
          ),
        ],
      ),
    );
  }
}

/// Widget for displaying the private key panel
class _PrivateKeyPanel extends StatelessWidget {
  final GeneratePaperWalletResponse keypair;
  final bool showPrivateKey;
  final VoidCallback onToggleVisibility;
  final VoidCallback onCopy;
  final bool phone;

  const _PrivateKeyPanel({
    required this.keypair,
    required this.showPrivateKey,
    required this.onToggleVisibility,
    required this.onCopy,
    this.phone = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    if (phone) {
      return _PhoneKeyCard(
        title: SailRow(
          spacing: SailStyleValues.padding08,
          children: [
            SailText.primary15('SPEND', bold: true),
            SailTooltip(
              message: showPrivateKey ? 'Hide private key' : 'Show private key',
              child: SailTappable(
                onTap: () async => onToggleVisibility(),
                borderRadius: context.sailTheme.chrome.radiusSmall,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: SailSVG.fromAsset(
                    showPrivateKey ? SailSVGAsset.eyeOff : SailSVGAsset.eye,
                    width: 14,
                    color: theme.colors.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ),
        subtitle: 'Private Key (WIF)',
        children: [
          // The private QR waits for the reveal, like the key text.
          if (showPrivateKey)
            _PaperQr(data: keypair.privateKeyWif)
          else
            SizedBox.square(
              dimension: _PaperQr.phoneSize,
              child: Center(
                child: SailSVG.fromAsset(SailSVGAsset.eyeOff, width: 64, color: theme.colors.textTertiary),
              ),
            ),
          SailSelectableText(
            showPrivateKey ? keypair.privateKeyWif : '\u2022' * keypair.privateKeyWif.length,
            style: TextStyle(fontSize: 12, color: theme.colors.text),
            textAlign: TextAlign.center,
          ),
          SailButton(
            label: 'Copy Private Key',
            variant: ButtonVariant.secondary,
            small: true,
            onPressed: () async => onCopy(),
          ),
          if (!showPrivateKey)
            SailText.secondary12(
              'Click the eye icon to reveal',
              color: theme.colors.orange,
              textAlign: TextAlign.center,
            ),
          SailAlert(
            variant: SailAlertVariant.destructive,
            description: 'KEEP SECRET: Anyone with this private key can spend your Bitcoin',
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colors.background,
        borderRadius: context.sailTheme.chrome.radiusSmall,
        border: Border.all(color: theme.colors.error, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SailSVG.fromAsset(SailSVGAsset.key, width: 24, color: theme.colors.error),
              const SizedBox(width: 8),
              SailText.primary15('SPEND', bold: true),
              const Spacer(),
              SailTooltip(
                message: showPrivateKey ? 'Hide private key' : 'Show private key',
                child: SailTappable(
                  onTap: () async => onToggleVisibility(),
                  borderRadius: context.sailTheme.chrome.radiusSmall,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: SailSVG.fromAsset(
                      showPrivateKey ? SailSVGAsset.eyeOff : SailSVGAsset.eye,
                      width: 20,
                      color: theme.colors.text,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SailText.secondary12(
            'Private Key (WIF)',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),

          if (showPrivateKey) ...[
            // QR Code
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colors.backgroundSecondary,
                borderRadius: context.sailTheme.chrome.radiusSmall,
              ),
              child: QrImageView(
                data: keypair.privateKeyWif,
                version: QrVersions.auto,
                size: 200,
                padding: EdgeInsets.zero,
                eyeStyle: QrEyeStyle(
                  color: theme.colors.text,
                  eyeShape: QrEyeShape.square,
                ),
                dataModuleStyle: QrDataModuleStyle(color: theme.colors.text),
                backgroundColor: theme.colors.backgroundSecondary,
              ),
            ),
            const SizedBox(height: 16),

            // Private key text
            SailSelectableText(
              keypair.privateKeyWif,
              style: TextStyle(
                fontFamily: SailFonts.mono,
                fontSize: 11,
                color: theme.colors.text,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),

            // Copy button
            SailButton(
              label: 'Copy Private Key',
              variant: ButtonVariant.secondary,
              onPressed: () async => onCopy(),
            ),
          ] else
            Column(
              children: [
                const SizedBox(height: 40),
                SailSVG.fromAsset(SailSVGAsset.eyeOff, width: 80, color: theme.colors.textTertiary),
                const SizedBox(height: 16),
                SailText.secondary12(
                  'Click the eye icon to reveal',
                  color: theme.colors.textTertiary,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),
              ],
            ),

          const SizedBox(height: 16),

          // Warning
          SailAlert(
            variant: SailAlertVariant.destructive,
            description: 'KEEP SECRET: Anyone with this private key can spend your Bitcoin',
          ),
        ],
      ),
    );
  }
}

/// A key panel on a phone: a plain card with a centred title.
class _PhoneKeyCard extends StatelessWidget {
  final Widget title;
  final String subtitle;
  final List<Widget> children;

  const _PhoneKeyCard({required this.title, required this.subtitle, required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(SailStyleValues.padding16),
      decoration: BoxDecoration(
        color: theme.chrome.panel(theme.colors).color,
        borderRadius: context.sailTheme.chrome.radius,
      ),
      child: SailColumn(
        spacing: SailStyleValues.padding12,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          title,
          SailText.secondary12(subtitle, textAlign: TextAlign.center),
          ...children,
        ],
      ),
    );
  }
}

class _PaperQr extends StatelessWidget {
  static const phoneSize = 150.0;

  final String data;

  const _PaperQr({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    return QrImageView(
      data: data,
      version: QrVersions.auto,
      size: phoneSize,
      padding: EdgeInsets.zero,
      eyeStyle: QrEyeStyle(color: theme.colors.text, eyeShape: QrEyeShape.square),
      dataModuleStyle: QrDataModuleStyle(color: theme.colors.text),
      backgroundColor: theme.chrome.panel(theme.colors).color ?? theme.colors.background,
    );
  }
}
