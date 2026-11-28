import 'dart:async';
import 'dart:math';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:sail_ui/sail_ui.dart';

@RoutePage()
class ParentChainPage extends StatelessWidget {
  const ParentChainPage({super.key});

  @override
  Widget build(BuildContext context) {
    return QtPage(
      child: ViewModelBuilder.reactive(
        viewModelBuilder: () => ParentChainTabViewModel(),
        builder: ((context, model, child) {
          return const TransferTab();
        }),
      ),
    );
  }
}

class TransferTab extends StatelessWidget {
  const TransferTab({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: SailRow(
        spacing: SailStyleValues.padding12,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Expanded(child: DepositTab()),
          Expanded(child: WithdrawTab()),
        ],
      ),
    );
  }
}

class DepositWithdrawHelp extends StatelessWidget {
  SidechainRPC get _rpc => GetIt.I.get<SidechainRPC>();

  const DepositWithdrawHelp({super.key});

  @override
  Widget build(BuildContext context) {
    return QuestionContainer(
      category: 'Deposit & Withdraw help',
      children: [
        const QuestionTitle('What are deposits and withdrawals?'),
        QuestionText(
          'You are currently connected to two blockchains. Bitcoin Core with BIP 300+301, and a sidechain called ${_rpc.chain.name}.',
        ),
        const QuestionText(
          'Deposits and withdrawals move bitcoin from one chain to the other. A deposit adds bitcoin to the sidechain, and a withdrawal removes bitcoin from the sidechain.',
        ),
        const QuestionText(
          'When we use the word deposit or withdraw in this application, we always refer to moving coins across chains.',
        ),
        const QuestionText(
          "Only after you have deposited coins to the sidechain, can you start using it's special features! If you're a developer and know your way around a command line, there's a special rpc called createsidechaindeposit that lets you deposit from your parent chain wallet.",
        ),
      ],
    );
  }
}

class ZSideWidgetTitleViewModel extends BaseViewModel {
  final log = Logger(level: Level.debug);
  SidechainBalanceProvider get _balanceProvider => GetIt.I.get<SidechainBalanceProvider>();

  double get balance => _balanceProvider.balance + _balanceProvider.pendingBalance;

  bool showAll = false;

  ZSideWidgetTitleViewModel() {
    _balanceProvider.addListener(notifyListeners);
  }

  @override
  void dispose() {
    super.dispose();
    _balanceProvider.removeListener(notifyListeners);
  }
}

class ParentChainTabViewModel extends BaseViewModel with ChangeTrackingMixin {
  @override
  final log = Logger(level: Level.debug);
  SidechainTransactionsProvider get _transactionsProvider => GetIt.I.get<SidechainTransactionsProvider>();
  SidechainRPC get _rpc => GetIt.I.get<SidechainRPC>();
  SidechainBalanceProvider get _balanceProvider => GetIt.I.get<SidechainBalanceProvider>();
  AddressProvider get _addressProvider => GetIt.I.get<AddressProvider>();

  final bitcoinAddressController = TextEditingController();
  final bitcoinAmountController = TextEditingController();
  final labelController = TextEditingController();

  double? sidechainFee;
  double? mainchainFee;

  String? get depositError => _addressProvider.depositError;
  String? withdrawError;

  double? get pegAmount => double.tryParse(bitcoinAmountController.text);
  double? get maxAmount => max(
    _balanceProvider.balance - (sidechainFee ?? 0) - (mainchainFee ?? 0),
    0,
  );
  String get sidechainName => _rpc.chain.name;

  String get totalBitcoinAmount => formatBitcoin(
    ((double.tryParse(bitcoinAmountController.text) ?? 0) + (mainchainFee ?? 0) + (sidechainFee ?? 0)),
  );

  String? get depositAddress => _addressProvider.depositAddress;

  ParentChainTabViewModel() {
    initChangeTracker();
    _initControllers();
    _initFees();
    _transactionsProvider.addListener(_onChange);
    _balanceProvider.addListener(_onChange);
    _addressProvider.addListener(_onChange);
  }

  void _onChange() {
    track('balance', _balanceProvider.balance);
    track('pendingBalance', _balanceProvider.pendingBalance);
    track('transactions', _transactionsProvider.sidechainTransactions);
    track('depositAddress', depositAddress);
    notifyIfChanged();
  }

  void _initControllers() {
    bitcoinAddressController.addListener(notifyListeners);
    bitcoinAmountController.addListener(_capAmount);
  }

  Future<void> _initFees() async {
    await Future.wait([estimateSidechainFee(), estimateMainchainFee()]);
  }

  void _capAmount() {
    String currentInput = bitcoinAmountController.text;
    if (maxAmount != null && (double.tryParse(currentInput) != null && double.parse(currentInput) > maxAmount!)) {
      bitcoinAmountController.text = maxAmount.toString();
      bitcoinAmountController.selection = TextSelection.fromPosition(
        TextPosition(offset: bitcoinAmountController.text.length),
      );
    }
    notifyListeners();
  }

  Future<void> estimateSidechainFee() async {
    sidechainFee = await _rpc.sideEstimateFee();
    notifyListeners();
  }

  Future<void> estimateMainchainFee() async {
    mainchainFee = 0.0001;
    notifyListeners();
  }

  Future<void> executePegOut(BuildContext context) async {
    if (pegAmount == null) {
      withdrawError = 'Invalid amount or fees not calculated';
      notifyListeners();
      log.e('Invalid peg out parameters');
      return;
    }

    if (sidechainFee == null) {
      await estimateSidechainFee();
      if (sidechainFee == null) {
        sidechainFee = 0.0001;
        notifyListeners();
      }
    }

    if (bitcoinAddressController.text.isEmpty) {
      withdrawError = 'Bitcoin address is required';
      notifyListeners();
      return;
    }

    setBusy(true);
    withdrawError = null;
    try {
      final withdrawalTxid = await _rpc.withdraw(
        bitcoinAddressController.text,
        btcToSatoshi(pegAmount!),
        btcToSatoshi(sidechainFee!),
        btcToSatoshi(mainchainFee!),
      );

      if (!context.mounted) {
        return;
      }

      unawaited(_balanceProvider.fetch());
      unawaited(_transactionsProvider.fetch());

      await successDialog(
        context: context,
        action: 'Withdraw to parent chain',
        title: 'Submitted withdraw successfully',
        subtitle: 'TXID: $withdrawalTxid',
      );
    } catch (error) {
      log.e('Could not execute withdrawal: ', error: error);
      withdrawError = error.toString();
      if (!context.mounted) {
        return;
      }

      await errorDialog(
        context: context,
        action: 'Withdraw to parent chain',
        title: 'Could not execute withdrawal',
        subtitle: error.toString(),
      );
    } finally {
      setBusy(false);
      notifyListeners();
    }
  }

  void castHelp(BuildContext context) async {
    await showThemedDialog(
      context: context,
      builder: (BuildContext context) {
        return const DepositWithdrawHelp();
      },
    );
  }

  @override
  void dispose() {
    bitcoinAddressController.dispose();
    bitcoinAmountController.dispose();
    labelController.dispose();
    _transactionsProvider.removeListener(_onChange);
    _balanceProvider.removeListener(_onChange);
    _addressProvider.removeListener(_onChange);
    super.dispose();
  }
}

class DepositTab extends StatelessWidget {
  const DepositTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder.reactive(
      viewModelBuilder: () => ParentChainTabViewModel(),
      builder: (context, model, child) {
        return SailCard(
          title: 'Deposit from Parent Chain',
          subtitle: 'Deposit coins to the sidechain',
          error: model.depositError,
          widgetHeaderEnd: HelpButton(
            onPressed: () async => model.castHelp(context),
          ),
          child: SailTextField(
            loading: LoadingDetails(
              enabled: model.depositAddress == null,
              description: 'Waiting for ${model.sidechainName} to boot...',
            ),
            controller: TextEditingController(text: model.depositAddress),
            hintText: 'Generating deposit address...',
            readOnly: true,
            suffixWidget: CopyButton(text: model.depositAddress ?? ''),
          ),
        );
      },
    );
  }
}

class WithdrawTab extends ViewModelWidget<ParentChainTabViewModel> {
  const WithdrawTab({super.key});

  @override
  Widget build(BuildContext context, ParentChainTabViewModel viewModel) {
    final theme = SailTheme.of(context);

    return SailCard(
      title: 'Withdraw to Parent Chain',
      subtitle: 'Withdraw bitcoin from the sidechain to the parent chain',
      error: viewModel.withdrawError,
      widgetHeaderEnd: SailRowMenuButton(
        items: () => [
          SailMenuItem(
            onSelected: () {
              viewModel.bitcoinAddressController.clear();
              viewModel.bitcoinAmountController.clear();
              viewModel.labelController.clear();
            },
            child: SailText.primary13('Clear All'),
          ),
        ],
      ),
      child: SailColumn(
        spacing: SailStyleValues.padding12,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SailTextField(
            label: 'Pay To',
            controller: viewModel.bitcoinAddressController,
            hintText: 'Enter a L1 bitcoin-address (e.g. 1NS17iag9jJgTHD1VXjvLCEnZuQ3rJDE9L)',
            suffixWidget: PasteButton(
              onPaste: (text) {
                viewModel.bitcoinAddressController.text = text;
              },
            ),
          ),
          NumericField(
            label: 'Amount',
            controller: viewModel.bitcoinAmountController,
            suffixWidget: SailButton(
              label: 'MAX',
              variant: ButtonVariant.link,
              onPressed: () async {
                if (viewModel.maxAmount != null) {
                  viewModel.bitcoinAmountController.text = viewModel.maxAmount.toString();
                }
              },
            ),
          ),
          SailTextField(
            label: 'Label (optional)',
            controller: viewModel.labelController,
            hintText: 'Enter a label',
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: SailStyleValues.padding12,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: theme.colors.background,
              borderRadius: theme.chrome.radius,
            ),
            child: SailColumn(
              spacing: 10,
              children: [
                _FeeRow(
                  label: 'Withdrawal Amount',
                  value: viewModel.pegAmount ?? 0,
                ),
                _FeeRow(
                  label: 'Sidechain Fee',
                  value: viewModel.sidechainFee ?? 0,
                ),
                _FeeRow(
                  label: 'Mainchain Fee',
                  value: viewModel.mainchainFee ?? 0,
                ),
                _FeeRow(
                  label: 'Total Cost',
                  value: (viewModel.pegAmount ?? 0) + (viewModel.sidechainFee ?? 0) + (viewModel.mainchainFee ?? 0),
                ),
              ],
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: SailButton(
              label: 'Send',
              onPressed: () => viewModel.executePegOut(context),
              loading: viewModel.isBusy,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeeRow extends StatelessWidget {
  final String label;
  final double value;

  const _FeeRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        SailText.primary13(label, color: theme.colors.textSecondary),
        SailText.primary13(formatBitcoin(value), monospace: true),
      ],
    );
  }
}
