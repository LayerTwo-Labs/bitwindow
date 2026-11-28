import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';

/// Asks for the wallet password and unlocks the wallet. Returns true when the wallet unlocked.
Future<bool> showUnlockWalletDialog(
  BuildContext context, {
  String title = 'Unlock Wallet',
  required String message,
  String wrongPasswordText = 'Incorrect password',
}) async {
  final unlocked = await showThemedDialog<bool>(
    context: context,
    builder: (context) => UnlockWalletDialog(
      title: title,
      message: message,
      wrongPasswordText: wrongPasswordText,
    ),
  );
  return unlocked ?? false;
}

class UnlockWalletDialog extends StatefulWidget {
  final String title;
  final String message;
  final String wrongPasswordText;

  const UnlockWalletDialog({
    super.key,
    required this.title,
    required this.message,
    required this.wrongPasswordText,
  });

  @override
  State<UnlockWalletDialog> createState() => _UnlockWalletDialogState();
}

class _UnlockWalletDialogState extends State<UnlockWalletDialog> {
  final _passwordController = TextEditingController();
  bool _unlocking = false;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    setState(() => _unlocking = true);
    try {
      final unlocked = await GetIt.I.get<WalletReaderProvider>().unlockWallet(_passwordController.text);
      if (!mounted) {
        return;
      }
      if (unlocked) {
        Navigator.of(context).pop(true);
        return;
      }
      setState(() => _unlocking = false);
      showSailToast(context, widget.wrongPasswordText);
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _unlocking = false);
      showSailToast(
        context,
        'Error unlocking wallet: ${extractConnectException(e)}',
        variant: SailToastVariant.destructive,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SailDialog(
      title: widget.title,
      withCloseButton: true,
      action: SailDialogAction(
        label: 'Unlock',
        loadingLabel: _unlocking ? 'Unlock' : null,
        onPressed: _unlock,
      ),
      child: SizedBox(
        width: 400,
        child: SailColumn(
          spacing: SailStyleValues.padding12,
          mainAxisSize: MainAxisSize.min,
          children: [
            SailText.secondary13(widget.message),
            SailTextField(
              controller: _passwordController,
              hintText: 'Password',
              obscureText: true,
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }
}
