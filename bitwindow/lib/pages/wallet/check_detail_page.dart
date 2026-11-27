import 'package:auto_route/auto_route.dart' hide AutoRouterX;
import 'package:bitwindow/providers/check_provider.dart';
import 'package:bitwindow/providers/transactions_provider.dart';
import 'package:bitwindow/utils/explorer_url.dart';
import 'package:collection/collection.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/gen/wallet/v1/wallet.pb.dart';

class CheckDetailViewModel extends BaseViewModel {
  Logger get log => GetIt.I.get<Logger>();
  final CheckProvider _checkProvider = GetIt.I.get<CheckProvider>();
  final TransactionProvider _transactionProvider = GetIt.I.get<TransactionProvider>();
  final OrchestratorWalletRPC _orchestratorWallet = GetIt.I.get<OrchestratorRPC>().wallet;
  WalletReaderProvider get _walletReader => GetIt.I<WalletReaderProvider>();
  final int checkId;

  Cheque? _check;
  bool _isLoading = false;
  @override
  String? modelError;
  String? actionError;
  bool _funding = false;
  bool _sweeping = false;

  Cheque? get check => _check;
  bool get isLoading => _isLoading;

  CheckDetailViewModel(this.checkId) {
    _check = _checkProvider.checks.firstWhereOrNull((c) => c.id.toInt() == checkId);
    _loadCheck();
    _checkProvider.addListener(_onCheckProviderChanged);
  }

  void _onCheckProviderChanged() {
    _loadCheck();
  }

  Future<void> _loadCheck() async {
    if (_check == null) {
      _isLoading = true;
      notifyListeners();
    }

    try {
      _check = await _checkProvider.getCheck(checkId);
      modelError = null;
    } catch (e) {
      _check = null;
      modelError = e.toString().contains('cheque not found') ? 'Check not found' : 'Failed to load check: $e';
    }

    _isLoading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _checkProvider.removeListener(_onCheckProviderChanged);
    super.dispose();
  }

  void copyAddress(BuildContext context) {
    if (_check != null) {
      Clipboard.setData(ClipboardData(text: _check!.address));
      showSailToast(context, 'Address copied to clipboard');
    }
  }

  void copyTxid(BuildContext context, String txid) {
    Clipboard.setData(ClipboardData(text: txid));
    showSailToast(context, 'Transaction ID copied to clipboard');
  }

  Future<void> fundWithWallet(BuildContext context) async {
    if (_check == null || _funding) {
      return;
    }

    _funding = true;
    _setActionError(null);
    try {
      final walletId = _walletReader.activeWalletId;
      if (walletId == null) {
        throw Exception('No active wallet');
      }

      final amountSats = checkMissingSats(_check!);
      if (amountSats <= 0) {
        throw Exception('The check is already funded');
      }

      final txid = (await _orchestratorWallet.sendTransaction(
        walletId: walletId,
        destinations: {_check!.address: amountSats},
        feeRateSatPerVbyte: 10,
      )).txid;

      final network = GetIt.I.get<BitcoinConfProvider>().network;
      GetIt.I.get<NotificationProvider>().add(
        title: 'Transaction sent',
        content: txid,
        dialogType: DialogType.info,
        links: [NotificationLink(text: 'View transaction', url: mempoolTxUrl(txid, network))],
      );

      if (!context.mounted) {
        return;
      }
      Navigator.of(context).pop();
    } catch (e) {
      _setActionError('Failed to fund check: $e');
    } finally {
      _funding = false;
    }
  }

  void _setActionError(String? error) {
    actionError = error;
    notifyListeners();
  }

  Future<void> sweepCheck(BuildContext context) async {
    if (_sweeping) {
      return;
    }

    _sweeping = true;
    try {
      await _sweepOnce(context);
    } finally {
      _sweeping = false;
    }
  }

  Future<void> _sweepOnce(BuildContext context) async {
    if (_check == null || _check!.fundedTxids.isEmpty) {
      return;
    }

    _setActionError(null);
    final destinationAddress = _transactionProvider.address;
    if (destinationAddress.isEmpty) {
      _setActionError('No receive address available');
      return;
    }

    if (!_check!.hasPrivateKeyWif() || _check!.privateKeyWif.isEmpty) {
      _setActionError('Private key not available - wallet may be locked');
      return;
    }

    try {
      // 0 means "use the backend's electrum fee estimate".
      final txid = await _checkProvider.sweepCheck(_check!.privateKeyWif, destinationAddress, 0);

      if (!context.mounted) {
        return;
      }

      showSailToast(context, 'Check swept! TXID: ${txid.substring(0, 10)}...');

      Navigator.of(context).pop();
    } catch (e) {
      if (!context.mounted) {
        return;
      }

      if (e.toString().toLowerCase().contains('wallet is locked')) {
        final isEncrypted = await _walletReader.isWalletEncrypted();
        if (!context.mounted) {
          return;
        }
        if (isEncrypted) {
          await _showUnlockDialog(context);
          if (!context.mounted) {
            return;
          }
          if (_walletReader.isWalletUnlocked) {
            await _sweepOnce(context);
          }
        } else {
          _setActionError('Backend wallet not initialized. Please restart the app.');
        }
      } else {
        _setActionError('Failed to sweep check: $e');
      }
    }
  }

  Future<void> _showUnlockDialog(BuildContext context) async {
    final passwordController = TextEditingController();
    bool isUnlocking = false;

    await showThemedDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => SailDialog(
          title: 'Unlock Wallet',
          actions: [
            SailButton(
              label: 'Cancel',
              variant: ButtonVariant.ghost,
              onPressed: () async => Navigator.of(context).pop(),
            ),
            SailButton(
              label: 'Unlock',
              loading: isUnlocking,
              onPressed: () async {
                setState(() => isUnlocking = true);
                final success = await _walletReader.unlockWallet(passwordController.text);

                if (success && context.mounted) {
                  Navigator.of(context).pop();
                } else {
                  setState(() => isUnlocking = false);
                  if (context.mounted) {
                    showSailToast(context, 'Incorrect password');
                  }
                }
              },
            ),
          ],
          child: SizedBox(
            width: 400,
            child: SailColumn(
              spacing: SailStyleValues.padding12,
              mainAxisSize: MainAxisSize.min,
              children: [
                SailText.secondary13('Enter your wallet password to sweep checks'),
                SailTextField(controller: passwordController, hintText: 'Password', obscureText: true, maxLines: 1),
              ],
            ),
          ),
        ),
      ),
    );

    passwordController.dispose();
  }
}

@RoutePage()
class CheckDetailPage extends StatelessWidget {
  final int checkId;

  const CheckDetailPage({super.key, @PathParam('id') required this.checkId});

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<CheckDetailViewModel>.reactive(
      viewModelBuilder: () => CheckDetailViewModel(checkId),
      builder: (context, model, child) {
        final title = model.check == null
            ? 'Check'
            : 'Check for ${formatCheckSats(model.check!.expectedAmountSats.toInt())}';

        return SailScaffold(
          backgroundColor: SailTheme.of(context).colors.background,
          appBar: SailAppBar.build(context, title: SailText.primary20(title)),
          body: Builder(
            builder: (context) {
              if (model.isLoading) {
                return const Center(child: LoadingIndicator());
              }

              if (model.modelError != null || model.check == null) {
                return Center(
                  child: SailColumn(
                    spacing: SailStyleValues.padding16,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SailText.primary15(model.modelError ?? 'Check not found'),
                      SailButton(label: 'Go Back', onPressed: () async => Navigator.of(context).pop()),
                    ],
                  ),
                );
              }

              final check = model.check!;
              final phone = SailStyleValues.phoneLayout(context);
              final swept = check.sweptTxid.isNotEmpty;
              final awaitingFunding = !swept && check.fundedTxids.isEmpty;
              final partlyFunded = !swept && check.fundedTxids.isNotEmpty && !check.funded;
              final colors = context.sailTheme.colors;
              final statusColor = swept
                  ? colors.text.withValues(alpha: 0.5)
                  : check.funded
                  ? colors.success
                  : colors.orange;
              final buttonWidth = phone ? double.infinity : 400.0;

              return SafeArea(
                child: SingleChildScrollView(
                  child: Center(
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 600),
                      padding: EdgeInsets.all(phone ? SailStyleValues.padding16 : SailStyleValues.padding40),
                      child: _PhonePanel(
                        phone: phone,
                        child: SailColumn(
                          spacing: phone ? SailStyleValues.padding16 : SailStyleValues.padding20,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (phone)
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(shape: BoxShape.circle, color: statusColor),
                                  )
                                else
                                  SizedBox(
                                    width: 32,
                                    height: 32,
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        Container(
                                          width: 32,
                                          height: 32,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: statusColor.withValues(alpha: 0.2),
                                          ),
                                        ),
                                        Container(
                                          width: 20,
                                          height: 20,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: statusColor.withValues(alpha: 0.5),
                                          ),
                                        ),
                                        Container(
                                          width: 12,
                                          height: 12,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: statusColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                SizedBox(width: phone ? SailStyleValues.padding08 : SailStyleValues.padding12),
                                SailText.primary13(swept ? 'Swept' : _statusLabel(check)),
                              ],
                            ),
                            if (!awaitingFunding)
                              SizedBox(
                                width: phone ? double.infinity : 520,
                                child: CheckAmounts(check: check),
                              ),
                            if (awaitingFunding)
                              Container(
                                padding: const EdgeInsets.all(SailStyleValues.padding20),
                                decoration: BoxDecoration(
                                  color: context.sailTheme.colors.backgroundSecondary,
                                  borderRadius: context.sailTheme.chrome.radiusSmall,
                                ),
                                child: QrImageView(
                                  data: check.address,
                                  version: QrVersions.auto,
                                  size: 200,
                                  backgroundColor: context.sailTheme.colors.backgroundSecondary,
                                  eyeStyle: QrEyeStyle(
                                    color: context.sailTheme.colors.text,
                                    eyeShape: QrEyeShape.square,
                                  ),
                                  dataModuleStyle: QrDataModuleStyle(
                                    color: context.sailTheme.colors.text,
                                    dataModuleShape: QrDataModuleShape.square,
                                  ),
                                ),
                              ),
                            if (awaitingFunding && phone)
                              Row(
                                children: [
                                  Expanded(child: SailText.primary13(check.address)),
                                  const SizedBox(width: SailStyleValues.padding08),
                                  CopyButton(text: check.address),
                                ],
                              ),
                            if (awaitingFunding && !phone)
                              SailRow(
                                spacing: SailStyleValues.padding08,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Flexible(child: SailText.primary13(check.address, textAlign: TextAlign.center)),
                                  CopyButton(text: check.address),
                                ],
                              ),
                            if (!swept &&
                                check.fundedTxids.isNotEmpty &&
                                check.hasPrivateKeyWif() &&
                                check.privateKeyWif.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.all(SailStyleValues.padding16),
                                decoration: BoxDecoration(
                                  color: context.sailTheme.colors.backgroundSecondary,
                                  borderRadius: context.sailTheme.chrome.radiusSmall,
                                  border: Border.all(color: context.sailTheme.colors.orange.withValues(alpha: 0.3)),
                                ),
                                child: SailColumn(
                                  spacing: SailStyleValues.padding08,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        SailSVG.icon(SailSVGAsset.iconWarning, width: 16),
                                        const SizedBox(width: SailStyleValues.padding08),
                                        SailText.primary13('Private Key (WIF)', bold: true),
                                      ],
                                    ),
                                    SailText.secondary12(
                                      'Share this private key with the recipient. They can import it into most Bitcoin wallets to access the funds.',
                                    ),
                                    SailRow(
                                      spacing: SailStyleValues.padding08,
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Flexible(
                                          child: SailSelectableText(
                                            check.privateKeyWif,
                                            style: TextStyle(
                                              fontFamily: SailFonts.mono,
                                              fontSize: 12,
                                              color: context.sailTheme.colors.text,
                                            ),
                                          ),
                                        ),
                                        CopyButton(secret: true, text: check.privateKeyWif),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            if (awaitingFunding)
                              SizedBox(
                                width: buttonWidth,
                                child: SailButton(
                                  label: 'Fund with Wallet',
                                  onPressed: () async => model.fundWithWallet(context),
                                ),
                              ),
                            if (partlyFunded)
                              SizedBox(
                                width: buttonWidth,
                                child: SailButton(
                                  label: 'Fund the Rest with Wallet',
                                  variant: ButtonVariant.secondary,
                                  onPressed: () async => model.fundWithWallet(context),
                                ),
                              ),
                            if (!swept && check.fundedTxids.isNotEmpty)
                              SizedBox(
                                width: buttonWidth,
                                child: SailButton(
                                  label: 'Sweep Check to Wallet',
                                  onPressed: () async => model.sweepCheck(context),
                                ),
                              ),
                            if (model.actionError != null)
                              SizedBox(width: buttonWidth, child: SailInlineError(model.actionError!)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/// The sats the check address still needs to hold the check amount.
int checkMissingSats(Cheque check) {
  final onCheck = check.hasActualAmountSats() ? check.actualAmountSats.toInt() : 0;
  final missing = check.expectedAmountSats.toInt() - onCheck;
  return missing > 0 ? missing : 0;
}

String formatCheckSats(int sats) => '${(sats / 100000000).toStringAsFixed(8)} ${activeTicker.symbol}';

/// Sweep txid the server stores for a check cashed outside this wallet.
const sweptOutsideTxid = 'swept_externally';

/// The amounts of a funded or swept check, and its sweep transaction.
class CheckAmounts extends StatelessWidget {
  final Cheque check;

  const CheckAmounts({super.key, required this.check});

  @override
  Widget build(BuildContext context) {
    final swept = check.sweptTxid.isNotEmpty;
    final onCheck = check.hasActualAmountSats() ? check.actualAmountSats.toInt() : 0;
    final missing = checkMissingSats(check);
    return SailColumn(
      spacing: SailStyleValues.padding08,
      children: [
        _AmountRow(label: 'Check amount', value: formatCheckSats(check.expectedAmountSats.toInt())),
        if (swept) ...[
          _AmountRow(label: 'Amount swept', value: formatCheckSats(onCheck)),
          if (check.sweptTxid == sweptOutsideTxid)
            const _AmountRow(label: 'Sweep transaction', value: 'Cashed outside this wallet')
          else
            _AmountRow(
              label: 'Sweep transaction',
              value: '${check.sweptTxid.substring(0, 10)}…${check.sweptTxid.substring(check.sweptTxid.length - 7)}',
              copyValue: check.sweptTxid,
            ),
        ] else ...[
          _AmountRow(label: 'On the check', value: formatCheckSats(onCheck)),
          if (missing > 0) _AmountRow(label: 'Still to fund', value: formatCheckSats(missing)),
        ],
      ],
    );
  }
}

class _AmountRow extends StatelessWidget {
  final String label;
  final String value;
  final String? copyValue;

  const _AmountRow({required this.label, required this.value, this.copyValue});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: SailText.secondary13(label)),
        SailText.primary13(value),
        if (copyValue != null) ...[
          const SizedBox(width: SailStyleValues.padding08),
          CopyButton(text: copyValue!),
        ],
      ],
    );
  }
}

String _statusLabel(Cheque check) => check.funded
    ? 'Funded'
    : check.fundedTxids.isNotEmpty
    ? 'Partially Funded'
    : 'Awaiting funding';

/// The phone form puts the page content in one panel.
class _PhonePanel extends StatelessWidget {
  final bool phone;
  final Widget child;

  const _PhonePanel({required this.phone, required this.child});

  @override
  Widget build(BuildContext context) => phone ? SailCard(child: child) : child;
}
