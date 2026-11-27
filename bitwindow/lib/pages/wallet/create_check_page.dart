import 'package:auto_route/auto_route.dart';
import 'package:bitwindow/providers/check_provider.dart';
import 'package:bitwindow/routing/router.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';

// The smallest amount the wallet sends to one address.
const _minSats = 546;
const _maxSats = 21000000 * 100000000;

@RoutePage()
class CreateCheckPage extends StatefulWidget {
  const CreateCheckPage({super.key});

  @override
  State<CreateCheckPage> createState() => _CreateCheckPageState();
}

class _CreateCheckPageState extends State<CreateCheckPage> {
  final CheckProvider _checkProvider = GetIt.I.get<CheckProvider>();
  final WalletReaderProvider _walletReader = GetIt.I.get<WalletReaderProvider>();
  final TextEditingController _amountController = TextEditingController();
  bool _isCreating = false;
  String? _error;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final phone = SailStyleValues.phoneLayout(context);
    return SailScaffold(
      backgroundColor: SailTheme.of(context).colors.background,
      appBar: SailAppBar.build(context, title: SailText.primary20('Create Check')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 600),
              padding: EdgeInsets.all(phone ? SailStyleValues.padding16 : SailStyleValues.padding20),
              child: _PhonePanel(
                phone: phone,
                child: SailColumn(
                  spacing: phone ? SailStyleValues.padding16 : SailStyleValues.padding32,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    phone
                        ? SailText.primary15('How much should the check be for?', bold: true)
                        : SailText.primary24('How much should the check be for?'),
                    SailTextField(
                      controller: _amountController,
                      hintText: '0.00000000',
                      suffix: activeTicker.symbol,
                      textFieldType: TextFieldType.bitcoin,
                      onChanged: (_) {
                        if (_error != null) {
                          setState(() => _error = null);
                        }
                      },
                    ),
                    SailRow(
                      spacing: SailStyleValues.padding08,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        SailButton(
                          label: 'Cancel',
                          variant: ButtonVariant.ghost,
                          onPressed: () async => context.router.maybePop(),
                        ),
                        SailButton(
                          label: 'Create',
                          loading: _isCreating,
                          onPressed: () async => _createCheck(),
                        ),
                      ],
                    ),
                    if (_error != null) SailInlineError(_error!),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _createCheck() async {
    final amountText = _amountController.text.trim();
    if (amountText.isEmpty) {
      setState(() => _error = 'Please enter an amount');
      return;
    }

    final btcAmount = double.tryParse(amountText);
    if (btcAmount == null || btcAmount <= 0) {
      setState(() => _error = 'Please enter a valid amount');
      return;
    }

    final sats = btcToSatoshi(btcAmount);
    if (sats < _minSats || sats > _maxSats) {
      setState(() => _error = 'Please enter a valid amount');
      return;
    }

    setState(() {
      _isCreating = true;
      _error = null;
    });

    try {
      final check = await _checkProvider.createCheck(sats);
      if (!mounted) {
        return;
      }
      await context.router.replace(CheckDetailRoute(checkId: check.id.toInt()));
    } catch (e) {
      if (!mounted) {
        return;
      }

      if (e.toString().toLowerCase().contains('wallet is locked')) {
        final isEncrypted = await _walletReader.isWalletEncrypted();
        if (!mounted) {
          return;
        }
        if (isEncrypted) {
          await showUnlockWalletDialog(context, message: 'Enter your wallet password to create checks');
          if (!mounted) {
            return;
          }
          if (_walletReader.isWalletUnlocked) {
            await _createCheck();
          }
        } else {
          setState(() => _error = 'Backend wallet not initialized. Please restart the app.');
        }
      } else {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCreating = false;
        });
      }
    }
  }
}

/// The phone form puts the page content in one panel.
class _PhonePanel extends StatelessWidget {
  final bool phone;
  final Widget child;

  const _PhonePanel({required this.phone, required this.child});

  @override
  Widget build(BuildContext context) => phone ? SailCard(child: child) : child;
}
