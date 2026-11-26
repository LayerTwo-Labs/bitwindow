import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';

class MessageSigner extends StatelessWidget {
  const MessageSigner({super.key});

  @override
  Widget build(BuildContext context) {
    return SailCard(
      padding: false,
      child: InlineTabBar(
        tabs: const [
          TabItem(
            label: 'Sign Message',
            icon: SailSVGAsset.iconPen,
            child: SignMessageTab(),
          ),
          TabItem(
            label: 'Verify Message',
            icon: SailSVGAsset.iconCheck,
            child: VerifyMessageTab(),
          ),
        ],
        initialIndex: 0,
      ),
    );
  }
}

String _errorText(Object e) => e is WalletException ? e.message : e.toString();

class SignMessageTab extends StatefulWidget {
  const SignMessageTab({super.key});

  @override
  State<SignMessageTab> createState() => _SignMessageTabState();
}

class _SignMessageTabState extends State<SignMessageTab> {
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _signatureController = TextEditingController();
  final WalletAPI _wallet = GetIt.I.get<BitwindowRPC>().wallet;
  WalletReaderProvider get _walletReader => GetIt.I<WalletReaderProvider>();
  (String, String)? _signed;
  String? _error;

  @override
  void initState() {
    super.initState();
    _addressController.addListener(_dropSignature);
    _messageController.addListener(_dropSignature);
  }

  @override
  void dispose() {
    _addressController.dispose();
    _messageController.dispose();
    _signatureController.dispose();
    super.dispose();
  }

  // A signature covers one address and one message only.
  void _dropSignature() {
    final signed = _signed;
    if (signed != null && signed != (_addressController.text, _messageController.text)) {
      _signed = null;
      _signatureController.clear();
    }
  }

  Future<void> _signMessage() async {
    try {
      setState(() => _error = null);
      final walletId = _walletReader.activeWalletId;
      if (walletId == null) {
        throw WalletException('No active wallet');
      }

      final message = _messageController.text;
      final address = _addressController.text;
      final signed = await _wallet.signMessage(walletId, message, address);
      if (!mounted || message != _messageController.text || address != _addressController.text) {
        return;
      }
      setState(() {
        _signed = (address, message);
        _signatureController.text = signed.signature;
      });
    } catch (e) {
      setState(() {
        _error = _errorText(e);
        _signed = null;
        _signatureController.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SailCard(
      title: 'Sign Message',
      subtitle: 'You can sign messages/agreements with your addresses to prove you can receive Drivechain coins sent to them. Be careful not to sign anything vague or random, as phishing attacks may try to trick you into signing your identity over to them. Only sign fully-detailed statements you agree to.',
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SailTextField(
              controller: _addressController,
              label: 'Enter a Drivechain address (e.g. n2wxQmfexkjwEPgdD6iJA7T7RtzkrnHxhFc)',
              hintText: '',
            ),
            const SizedBox(height: 24),
            SailTextField(
              controller: _messageController,
              maxLines: 5,
              hintText: 'Message',
            ),
            const SizedBox(height: 24),
            SailTextField(
              controller: _signatureController,
              readOnly: true,
              hintText: 'Signature',
            ),
            const SizedBox(height: 24),
            SailButton(
              onPressed: _signMessage,
              label: 'Sign Message',
              icon: SailSVGAsset.iconPen,
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              SailInlineError(_error!),
            ],
          ],
        ),
      ),
    );
  }
}

class VerifyMessageTab extends StatefulWidget {
  const VerifyMessageTab({super.key});

  @override
  State<VerifyMessageTab> createState() => _VerifyMessageTabState();
}

class _VerifyMessageTabState extends State<VerifyMessageTab> {
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _signatureController = TextEditingController();
  final WalletAPI _wallet = GetIt.I.get<BitwindowRPC>().wallet;
  WalletReaderProvider get _walletReader => GetIt.I<WalletReaderProvider>();
  bool? _isValid;
  (String, String, String)? _checked;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final controller in [_addressController, _messageController, _signatureController]) {
      controller.addListener(_dropResult);
    }
  }

  // A result covers the text it checked only.
  void _dropResult() {
    final checked = _checked;
    if (checked != null && checked != (_addressController.text, _messageController.text, _signatureController.text)) {
      setState(() {
        _checked = null;
        _isValid = null;
      });
    }
  }

  @override
  void dispose() {
    _addressController.dispose();
    _messageController.dispose();
    _signatureController.dispose();
    super.dispose();
  }

  Future<void> _verifyMessage() async {
    try {
      setState(() => _error = null);
      final walletId = _walletReader.activeWalletId;
      if (walletId == null) {
        throw WalletException('No active wallet');
      }

      final message = _messageController.text;
      final signature = _signatureController.text;
      final address = _addressController.text;
      final isValid = await _wallet.verifyMessage(walletId, message, signature, address);
      if (!mounted ||
          message != _messageController.text ||
          signature != _signatureController.text ||
          address != _addressController.text) {
        return;
      }
      setState(() {
        _checked = (address, message, signature);
        _isValid = isValid;
      });
    } catch (e) {
      setState(() {
        _error = _errorText(e);
        _checked = null;
        _isValid = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.sailTheme;

    return SailCard(
      title: 'Verify Message',
      subtitle: "Enter the receiver's address, message (ensure you copy line breaks, spaces, tabs, etc. exactly) and signature below to verify the message. Be careful not to read more into the signature than what is in the signed message itself, to avoid being tricked by a man-in-the-middle attack. Note that this only proves the signing party receives with the address, it cannot prove sendership of any transaction!",
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: SailColumn(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: SailStyleValues.padding16,
            children: [
              SailTextField(
                controller: _addressController,
                label: 'Enter a Drivechain address (e.g. n2wxQmfexkjwEPgdD6iJA7T7RtzkrnHxhFc)',
                hintText: '',
              ),
              SailTextField(
                controller: _messageController,
                label: 'Message',
                maxLines: 5,
                hintText: '',
              ),
              SailTextField(
                controller: _signatureController,
                label: 'Signature',
                hintText: '',
              ),
              SailRow(
                spacing: SailStyleValues.padding16,
                children: [
                  SailButton(
                    label: 'Verify Message',
                    icon: SailSVGAsset.iconQuestion,
                    onPressed: _verifyMessage,
                  ),
                  if (_error != null)
                    Expanded(child: SailInlineError(_error!))
                  else if (_isValid case final valid?)
                    Expanded(
                      child: SailRow(
                        mainAxisAlignment: MainAxisAlignment.start,
                        spacing: SailStyleValues.padding08,
                        children: [
                          SailSVG.fromAsset(
                            valid ? SailSVGAsset.circleCheck : SailSVGAsset.circleAlert,
                            color: valid ? theme.colors.success : theme.colors.error,
                          ),
                          Flexible(
                            child: SailText.primary13(
                              valid ? 'Message verified' : 'Invalid signature',
                              color: valid ? theme.colors.success : theme.colors.error,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
