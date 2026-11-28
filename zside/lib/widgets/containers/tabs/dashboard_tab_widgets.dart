import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sail_ui/shell/chain_navigator.dart';
import 'package:zside/providers/transactions_provider.dart';
import 'package:zside/widgets/containers/dashboard_action_modal.dart';
import 'package:zside/widgets/v2_parts.dart';

class SendOnSidechainAction extends StatelessWidget {
  final double? maxAmount;
  final Future<String> Function(String address, double amount)? customSendAction;

  const SendOnSidechainAction({
    super.key,
    this.maxAmount,
    this.customSendAction,
  });

  @override
  Widget build(BuildContext context) {
    final formatter = GetIt.I<FormatterProvider>();

    return ViewModelBuilder.reactive(
      viewModelBuilder: () => SendOnSidechainViewModel(
        customSendAction: customSendAction,
        maxAmount: maxAmount,
      ),
      builder: ((context, model, child) {
        return ListenableBuilder(
          listenable: formatter,
          builder: (context, child) => DashboardActionModal(
            'Send on sidechain',
            endActionButton: SailButton(
              variant: ButtonVariant.primary,
              label: 'Execute send',
              disabled: model.bitcoinAddressController.text.isEmpty || model.bitcoinAmountController.text.isEmpty,
              loading: model.isBusy,
              onPressed: () async {
                await model.executeSendOnSidechain(context);
              },
            ),
            children: [
              ZSideField(
                controller: model.bitcoinAddressController,
                hintText: 'Enter a sidechain-address',
                autofocus: true,
              ),
              ZSideField(
                controller: model.bitcoinAmountController,
                hintText: 'Enter a ${model.ticker}-amount',
                suffixText: model.ticker,
                bitcoinInput: true,
              ),
              StaticActionField(
                label: 'Fee',
                value: (formatter.formatBTC(model.sidechainExpectedFee ?? 0)),
              ),
              StaticActionField(
                label: 'Total amount',
                value: model.totalBitcoinAmount,
              ),
            ],
          ),
        );
      }),
    );
  }
}

class SendOnSidechainViewModel extends BaseViewModel {
  final log = Logger(level: Level.debug);
  ZSideRPC get _rpc => GetIt.I.get<ZSideRPC>();

  SidechainBalanceProvider get _balanceProvider => GetIt.I.get<SidechainBalanceProvider>();
  TransactionsProvider get _transactionsProvider => GetIt.I.get<TransactionsProvider>();
  ChainNavigator get _navigator => GetIt.I.get<ChainNavigator>();

  final bitcoinAddressController = TextEditingController();
  final bitcoinAmountController = TextEditingController();
  String get totalBitcoinAmount {
    final formatter = GetIt.I<FormatterProvider>();
    return formatter.formatBTC(
      (double.tryParse(bitcoinAmountController.text) ?? 0) + (sidechainExpectedFee ?? 0),
    );
  }

  String get ticker => _rpc.chain.ticker;

  double? sidechainExpectedFee;
  double? get sendAmount => double.tryParse(bitcoinAmountController.text);

  final Future<String> Function(String address, double amount)? customSendAction;
  final double? maxAmount;

  SendOnSidechainViewModel({this.customSendAction, this.maxAmount}) {
    bitcoinAddressController.addListener(notifyListeners);
    bitcoinAmountController.addListener(_capAmount);
    init();
  }

  void _capAmount() {
    String currentInput = bitcoinAmountController.text;

    if (maxAmount != null && (double.tryParse(currentInput) != null && double.parse(currentInput) > maxAmount!)) {
      bitcoinAmountController.text = maxAmount.toString();
      bitcoinAmountController.selection = TextSelection.fromPosition(
        TextPosition(offset: bitcoinAmountController.text.length),
      );
    } else {
      notifyListeners();
    }
  }

  void init() async {
    await estimateFee();
  }

  Future<void> executeSendOnSidechain(BuildContext context) async {
    if (isBusy) {
      return;
    }
    setBusy(true);
    try {
      await onSidechainSend(context);
    } finally {
      setBusy(false);
    }
  }

  Future<void> estimateFee() async {
    final estimate = await _rpc.sideEstimateFee();
    sidechainExpectedFee = estimate;
    notifyListeners();
  }

  Future<void> onSidechainSend(BuildContext context) async {
    if (sendAmount == null) {
      log.e('withdrawal amount was empty');
      return;
    }
    if (sidechainExpectedFee == null) {
      log.e('sidechain fee was empty');
      return;
    }

    final address = bitcoinAddressController.text;

    // Because the function is async, the view might disappear/unmount
    // by the time it's used. The linter doesn't like that, and wants
    // you to check whether the view is mounted before using it
    if (!context.mounted) {
      return;
    }

    await _doSidechainSend(context, address, sendAmount!);
  }

  Future<void> _doSidechainSend(
    BuildContext context,
    String address,
    double amount,
  ) async {
    log.i(
      'doing sidechain withdrawal: $amount $ticker to $address with $sidechainExpectedFee SC fee',
    );

    try {
      final sendTXID = await _send(address, amount);
      log.i('sent sidechain withdrawal txid: $sendTXID sendTXID');

      // refresh balance, but don't await, so dialog is showed instantly
      unawaited(_balanceProvider.fetch());
      // refresh transactions, but don't await, so dialog is showed instantly
      unawaited(_transactionsProvider.fetch());

      if (!context.mounted) {
        return;
      }

      await showSendSentDialog(
        context,
        sentText: 'You sent $amount $ticker to $address',
        txid: sendTXID,
      );
      // also pop the info modal
      await _navigator.pop();
    } catch (error) {
      if (!context.mounted) {
        return;
      }

      await showSendFailedDialog(context, error: error.toString());
    }
  }

  Future<String> _send(String address, double amount) async {
    if (customSendAction != null) {
      return await customSendAction!(address, amount);
    }

    return await _rpc.sideSend(address, amount, false);
  }
}

class ReceiveAction extends StatelessWidget {
  final Future<String> Function()? customReceiveAction;
  final String? customTitle;
  final String? initialAddress;

  const ReceiveAction({
    super.key,
    this.customReceiveAction,
    this.customTitle,
    this.initialAddress,
  });

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder.reactive(
      viewModelBuilder: () => ReceiveViewModel(
        initialAddress: initialAddress,
        customReceiveAction: customReceiveAction,
      ),
      builder: ((context, model, child) {
        return Padding(
          padding: const EdgeInsets.only(left: SailStyleValues.padding04),
          child: DashboardActionModal(
            customTitle ?? 'Receive on sidechain',
            endActionButton: SailButton(
              variant: ButtonVariant.primary,
              label: 'Generate new address',
              loading: model.isBusy,
              onPressed: () async {
                await model.generateSidechainAddress();
              },
            ),
            children: [
              StaticActionField(
                label: 'Address',
                value: model.address,
                copyable: true,
              ),
            ],
          ),
        );
      }),
    );
  }
}

class ReceiveViewModel extends BaseViewModel {
  ZSideRPC get _rpc => GetIt.I.get<ZSideRPC>();
  final log = Logger(level: Level.debug);

  String? sidechainAddress;
  final Future<String> Function()? customReceiveAction;
  final String? initialAddress;
  String get address => sidechainAddress ?? initialAddress ?? '';

  ReceiveViewModel({this.customReceiveAction, this.initialAddress}) {
    if (initialAddress == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await generateSidechainAddress();
      });
    }
  }

  Future<void> generateSidechainAddress() async {
    sidechainAddress = await _receive();
    notifyListeners();
  }

  Future<String> _receive() async {
    if (customReceiveAction != null) {
      return await customReceiveAction!();
    }

    return await _rpc.getSideAddress();
  }
}

const _sendTitle = 'Send on sidechain';

Future<void> showSendSentDialog(
  BuildContext context, {
  required String sentText,
  required String txid,
}) async {
  await widgetDialog(
    context: context,
    title: _sendTitle,
    maxWidth: 480,
    child: SendResultBody(
      lead: SailText.primary13(sentText, overflow: TextOverflow.visible),
      detail: 'TXID: $txid',
    ),
  );
}

Future<void> showSendFailedDialog(
  BuildContext context, {
  required String error,
}) async {
  await widgetDialog(
    context: context,
    title: _sendTitle,
    maxWidth: 480,
    child: SendResultBody(
      lead: const _SendErrorRow('Could not execute withdrawal'),
      detail: error,
    ),
  );
}

/// The body of a send result: the outcome line over the grey detail.
class SendResultBody extends StatelessWidget {
  final Widget lead;
  final String detail;

  const SendResultBody({super.key, required this.lead, required this.detail});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        lead,
        const SizedBox(height: SailStyleValues.padding12),
        SailText.primary13(
          detail,
          color: SailTheme.of(context).colors.textSecondary,
          overflow: TextOverflow.visible,
        ),
        const DialogButtons(onPressed: null),
      ],
    );
  }
}

class _SendErrorRow extends StatelessWidget {
  final String message;

  const _SendErrorRow(this.message);

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SailStyleValues.padding12,
        vertical: SailStyleValues.padding10,
      ),
      decoration: BoxDecoration(
        color: theme.colors.formField,
        borderRadius: theme.chrome.radius,
      ),
      child: SailInlineError(message),
    );
  }
}
