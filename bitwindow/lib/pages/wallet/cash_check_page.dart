import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:bitwindow/routing/router.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';

const _checkDebounce = Duration(milliseconds: 400);

@RoutePage()
class CashCheckPage extends StatelessWidget {
  const CashCheckPage({super.key});

  @override
  Widget build(BuildContext context) {
    final phone = SailStyleValues.phoneLayout(context);
    return SailScaffold(
      backgroundColor: SailTheme.of(context).colors.background,
      appBar: SailAppBar.build(context, title: SailText.primary20('Cash Check')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 600),
              padding: EdgeInsets.all(phone ? SailStyleValues.padding16 : SailStyleValues.padding20),
              child: _PhonePanel(phone: phone, child: const _CashCheckForm()),
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens Cash Check as a dialog, then "Your Check was Cashed" after the sweep.
Future<void> showCashCheckDialog(BuildContext context) async {
  final cashed = await showThemedDialog<(String, int)>(
    context: context,
    builder: (context) => SailDialog(
      title: 'Cash Check',
      withCloseButton: true,
      maxWidth: 480,
      child: _CashCheckForm(onCashed: (txid, amountSats) => Navigator.of(context).pop((txid, amountSats))),
    ),
  );
  if (cashed == null || !context.mounted) {
    return;
  }
  final (txid, amountSats) = cashed;
  await showThemedDialog<void>(
    context: context,
    builder: (context) => SailDialog(
      title: 'Your Check was Cashed',
      maxWidth: 480,
      action: SailDialogAction(label: 'Done', onPressed: () async => Navigator.of(context).pop()),
      child: SailColumn(
        spacing: SailStyleValues.padding12,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SailText.secondary13('Funds are on their way to your wallet'),
          SailDetailGroup(
            fill: SailDetailFill.canvas,
            children: [
              SailDetailLine(wrap: true, label: 'Amount:', value: _formatSats(amountSats)),
              SailDetailLine(
                wrap: true,
                label: 'Transaction:',
                value: '${txid.substring(0, 10)}...${txid.substring(txid.length - 10)}',
                trailing: CopyButton(text: txid),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _CashCheckForm extends StatefulWidget {
  /// Gets the sweep txid and the amount. Null opens the success page in place of this page.
  final void Function(String txid, int amountSats)? onCashed;

  const _CashCheckForm({this.onCashed});

  @override
  State<_CashCheckForm> createState() => _CashCheckFormState();
}

class _CashCheckFormState extends State<_CashCheckForm> {
  final BitwindowRPC _bitwindowRPC = GetIt.I.get<BitwindowRPC>();
  final OrchestratorWalletRPC _orchestratorWallet = GetIt.I.get<OrchestratorRPC>().wallet;
  final WalletReaderProvider _walletReader = GetIt.I.get<WalletReaderProvider>();
  final TextEditingController _wifController = TextEditingController();
  bool _isCashing = false;
  bool _isChecking = false;
  SweepPreview? _preview;
  String? _destination;
  String? _error;
  Timer? _debounce;

  String get _wif => _wifController.text.trim();

  @override
  void dispose() {
    _debounce?.cancel();
    _wifController.dispose();
    super.dispose();
  }

  void _onKeyChanged(String value) {
    _debounce?.cancel();
    final hasKey = value.trim().isNotEmpty;
    setState(() {
      _error = null;
      _preview = null;
      _isChecking = hasKey;
    });
    if (hasKey) {
      _debounce = Timer(_checkDebounce, _check);
    }
  }

  /// Reads what the key holds and what the sweep to this wallet costs.
  Future<void> _check() async {
    final wif = _wif;
    try {
      final walletId = _walletReader.activeWalletId;
      if (walletId == null) {
        throw Exception('No active wallet');
      }
      final destination = (await _orchestratorWallet.getNewAddress(walletId)).address;
      final preview = await _bitwindowRPC.wallet.previewSweep(wif, destinationAddress: destination);
      if (!mounted || _wif != wif) {
        return;
      }
      setState(() {
        _isChecking = false;
        _destination = destination;
        _preview = preview.hasFunds ? preview : null;
        _error = preview.hasFunds ? null : 'This key holds no coins.';
      });
    } catch (e) {
      if (!mounted || _wif != wif) {
        return;
      }
      setState(() {
        _isChecking = false;
        _error = 'Failed to cash check: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final phone = SailStyleValues.phoneLayout(context);
    final field = SailTextField(
      controller: _wifController,
      hintText: 'Private key (WIF format)',
      textFieldType: TextFieldType.text,
      maxLines: 3,
      onChanged: _onKeyChanged,
    );
    if (widget.onCashed != null) {
      return SailColumn(
        spacing: SailStyleValues.padding12,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SailText.primary13('Enter the private key (WIF)', bold: true),
          SailText.secondary13(
            'Paste the private key from the check you received. The funds will be swept to your wallet.',
          ),
          field,
          if (_preview case final preview?) _SweepPreviewRows(preview: preview, phone: false),
          if (_error != null) SailInlineError(_error!),
          SailButton(
            label: 'Cash Check',
            loading: _isCashing || _isChecking,
            disabled: _preview == null,
            onPressed: () async => _cashCheck(),
          ),
        ],
      );
    }
    return SailColumn(
      spacing: phone ? SailStyleValues.padding16 : SailStyleValues.padding32,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        phone
            ? SailText.primary15('Enter the private key (WIF)', bold: true)
            : SailText.primary24('Enter the private key (WIF)'),
        SailText.secondary13(
          'Paste the private key from the check you received. The funds will be swept to your wallet.',
          textAlign: phone ? TextAlign.start : TextAlign.center,
        ),
        field,
        if (_preview case final preview?) _SweepPreviewRows(preview: preview, phone: phone),
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
              label: 'Cash Check',
              loading: _isCashing || _isChecking,
              disabled: _preview == null,
              onPressed: () async => _cashCheck(),
            ),
          ],
        ),
        if (_error != null) SailInlineError(_error!),
      ],
    );
  }

  Future<void> _cashCheck() async {
    final wif = _wif;
    final preview = _preview;
    final destinationAddress = _destination;
    if (preview == null || destinationAddress == null) {
      return;
    }

    setState(() {
      _isCashing = true;
      _error = null;
    });

    try {
      final walletId = _walletReader.activeWalletId;
      if (walletId == null) {
        throw Exception('No active wallet');
      }

      final result = await _bitwindowRPC.wallet.sweepCheque(
        walletId,
        wif,
        destinationAddress,
        preview.feeSatPerVbyte,
      );

      if (!mounted) {
        return;
      }

      final onCashed = widget.onCashed;
      if (onCashed != null) {
        onCashed(result.txid, result.receiveSats);
        return;
      }
      await context.router.replace(
        CashCheckSuccessRoute(
          txid: result.txid,
          amountSats: result.receiveSats,
        ),
      );
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
          await showUnlockWalletDialog(context, message: 'Enter your wallet password to cash checks');
          if (!mounted) {
            return;
          }
          if (_walletReader.isWalletUnlocked) {
            await _cashCheck();
          }
        } else {
          setState(() => _error = 'Backend wallet not initialized. Please restart the app.');
        }
      } else {
        setState(() => _error = 'Failed to cash check: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCashing = false;
        });
      }
    }
  }
}

String _formatSats(int sats) => '${(sats / 100000000).toStringAsFixed(8)} ${activeTicker.symbol}';

/// What the key holds, the fee of the sweep, and what the wallet receives.
class _SweepPreviewRows extends StatelessWidget {
  final SweepPreview preview;
  final bool phone;

  const _SweepPreviewRows({required this.preview, required this.phone});

  @override
  Widget build(BuildContext context) {
    final rows = [
      ('Check amount', _formatSats(preview.amountSats)),
      ('Network fee', _formatSats(preview.feeSats)),
      ('You receive', _formatSats(preview.receiveSats)),
    ];
    if (phone) {
      final divider = Container(height: 1, color: SailTheme.of(context).colors.divider);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (label, value) in rows) ...[divider, SailValueRow(label: label, value: value)],
          divider,
        ],
      );
    }
    return SailCard(
      padding: true,
      secondary: true,
      child: SailColumn(
        spacing: SailStyleValues.padding12,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (label, value) in rows)
            SailRow(
              spacing: SailStyleValues.padding08,
              children: [
                SailText.primary13('$label:', bold: true),
                SailText.primary13(value),
              ],
            ),
        ],
      ),
    );
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
