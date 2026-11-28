import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/pages/sidechains/sidechain_overview_page.dart';
import 'package:sail_ui/sail_ui.dart';

@RoutePage()
class TransactionBuilderPage extends StatelessWidget {
  const TransactionBuilderPage({super.key});

  @override
  Widget build(BuildContext context) {
    return QtPage(
      child: ViewModelBuilder<TransactionBuilderViewModel>.reactive(
        viewModelBuilder: () => TransactionBuilderViewModel(),
        builder: (context, model, child) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left panel - UTXO selector
              Expanded(flex: 2, child: _UtxoSelectorPanel(model: model)),
              const SizedBox(width: SailStyleValues.padding12),
              // Right panel - Transaction creator
              Expanded(flex: 3, child: _TransactionCreatorPanel(model: model)),
            ],
          );
        },
      ),
    );
  }
}

class _UtxoSelectorPanel extends StatelessWidget {
  final TransactionBuilderViewModel model;

  const _UtxoSelectorPanel({required this.model});

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    final formatter = GetIt.I<FormatterProvider>();

    return SailCard(
      title: 'Wallet UTXOs',
      subtitle: 'Available funds to spend',
      bottomPadding: false,
      widgetHeaderEnd: SailButton(
        label: 'Refresh',
        variant: ButtonVariant.secondary,
        small: true,
        onPressed: model.refreshUtxos,
        loading: model.isLoadingUtxos,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListenableBuilder(
            listenable: formatter,
            builder: (context, child) => Wrap(
              spacing: SailStyleValues.padding20,
              runSpacing: SailStyleValues.padding08,
              children: [
                SailStat(label: 'Total Available', value: formatter.formatSats(model.totalAvailable)),
                SailStat(label: 'Selected', value: formatter.formatSats(model.selectedValue)),
              ],
            ),
          ),
          const SizedBox(height: SailStyleValues.padding08),
          // UTXO list
          Expanded(
            child: model.utxoError != null
                ? Center(
                    child: SailText.primary13(
                      model.utxoError!,
                      color: theme.colors.error,
                    ),
                  )
                : ListenableBuilder(
                    listenable: formatter,
                    builder: (context, child) => SailTable(
                      getRowId: (index) => model.walletUtxos[index].outpoint,
                      headerBuilder: (context) => [
                        SailTableHeaderCell(name: ''),
                        SailTableHeaderCell(name: 'Outpoint'),
                        SailTableHeaderCell(name: 'Value', alignment: Alignment.centerRight),
                      ],
                      rowBuilder: (context, row, selected) {
                        final utxo = model.walletUtxos[row];
                        final isSelected = model.selectedUtxos.contains(
                          utxo.outpoint,
                        );
                        return [
                          SailTableCell(
                            value: '',
                            child: SailCheckbox(
                              value: isSelected,
                              onChanged: (_) => model.toggleUtxo(utxo.outpoint),
                            ),
                          ),
                          SailTableCell(
                            value: _truncateOutpoint(utxo.outpoint),
                            copyValue: utxo.outpoint,
                            monospace: true,
                          ),
                          SailTableCell(
                            value: formatter.formatSats(utxo.valueSats.toInt()),
                            monospace: true,
                            alignment: Alignment.centerRight,
                          ),
                        ];
                      },
                      rowCount: model.walletUtxos.length,
                      drawGrid: true,
                      rowHasMenu: (_) => false,
                      rowBackgroundColor: (index) => model.selectedUtxos.contains(model.walletUtxos[index].outpoint)
                          ? theme.colors.formField
                          : null,
                      emptyPlaceholder: model.isLoadingUtxos ? 'Loading UTXOs...' : 'No UTXOs in wallet',
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  String _truncateOutpoint(String outpoint) {
    if (outpoint.length <= 16) return outpoint;
    final parts = outpoint.split(':');
    if (parts.length == 2) {
      final hash = parts[0];
      final index = parts[1];
      if (hash.length > 8) {
        return '${hash.substring(0, 8)}...:$index';
      }
    }
    return outpoint;
  }
}

class _TransactionCreatorPanel extends StatelessWidget {
  final TransactionBuilderViewModel model;

  const _TransactionCreatorPanel({required this.model});

  @override
  Widget build(BuildContext context) {
    final formatter = GetIt.I<FormatterProvider>();

    return SailCard(
      title: 'Create Transaction',
      subtitle: 'Build and broadcast a transaction',
      widgetHeaderEnd: SailRowMenuButton(
        filled: true,
        items: () => [
          SailMenuItem(onSelected: model.clear, child: SailText.primary12('Clear')),
        ],
      ),
      child: SingleChildScrollView(
        child: SailColumn(
          spacing: SailStyleValues.padding12,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SidechainNotice(
              message:
                  'UTXO selection is informational. The wallet will automatically select UTXOs for the transaction.',
            ),
            SailText.primary13('Create Output', bold: true),
            SailTextField(
              label: 'Destination Address',
              controller: model.addressController,
              hintText: 'Enter recipient address',
            ),
            NumericField(label: 'Amount (BTC)', controller: model.amountController, hintText: '0.00000000'),
            SailTextField(label: 'Fee (BTC)', controller: model.feeController, hintText: '0.00001', readOnly: true),
            if (model.amountBtc != null)
              ListenableBuilder(
                listenable: formatter,
                builder: (context, child) => SailDetailGroup(
                  children: [
                    SailDetailLine(label: 'Amount', value: formatBitcoin(model.amountBtc ?? 0)),
                    SailDetailLine(label: 'Fee', value: formatBitcoin(model.feeBtc)),
                    SailDetailLine(label: 'Total', value: formatBitcoin((model.amountBtc ?? 0) + model.feeBtc)),
                  ],
                ),
              ),
            SailButton(
              label: 'Sign & Broadcast',
              onPressed: model.canSend ? () async => model.sendTransaction(context) : null,
              disabled: !model.canSend,
              loading: model.isSending,
            ),
            if (model.sendError != null) SidechainNotice(message: model.sendError!, tone: SidechainNoticeTone.error),
            if (model.txid != null)
              SidechainNotice(
                title: 'Transaction sent!',
                message: 'TXID: ${model.txid}',
                tone: SidechainNoticeTone.success,
                trailing: CopyButton(text: model.txid!),
              ),
          ],
        ),
      ),
    );
  }
}

class TransactionBuilderViewModel extends BaseViewModel {
  PhotonRPC get _rpc => GetIt.I.get<PhotonRPC>();
  SidechainBalanceProvider get _balanceProvider => GetIt.I.get<SidechainBalanceProvider>();

  final TextEditingController addressController = TextEditingController();
  final TextEditingController amountController = TextEditingController();
  final TextEditingController feeController = TextEditingController(text: '0.00001');

  List<SidechainUTXO> walletUtxos = [];
  Set<String> selectedUtxos = {};
  String? utxoError;
  String? sendError;
  String? txid;
  bool isLoadingUtxos = true;
  bool isSending = false;

  int get totalAvailable => walletUtxos.fold(0, (sum, utxo) => sum + utxo.valueSats.toInt());

  int get selectedValue {
    int total = 0;
    for (final utxo in walletUtxos) {
      if (selectedUtxos.contains(utxo.outpoint)) {
        total += utxo.valueSats.toInt();
      }
    }
    return total;
  }

  double? get amountBtc => double.tryParse(amountController.text);
  double get feeBtc => double.tryParse(feeController.text) ?? 0.00001;

  bool get canSend {
    return addressController.text.isNotEmpty && amountBtc != null && amountBtc! > 0 && !isSending;
  }

  TransactionBuilderViewModel() {
    _init();
    addressController.addListener(notifyListeners);
    amountController.addListener(notifyListeners);
    feeController.addListener(notifyListeners);
  }

  Future<void> _init() async {
    await refreshUtxos();
  }

  Future<void> refreshUtxos() async {
    isLoadingUtxos = true;
    utxoError = null;
    notifyListeners();

    try {
      walletUtxos = await _rpc.listUTXOs();
    } catch (e) {
      utxoError = e.toString();
    } finally {
      isLoadingUtxos = false;
      notifyListeners();
    }
  }

  void toggleUtxo(String outpoint) {
    if (selectedUtxos.contains(outpoint)) {
      selectedUtxos.remove(outpoint);
    } else {
      selectedUtxos.add(outpoint);
    }
    notifyListeners();
  }

  Future<void> sendTransaction(BuildContext context) async {
    if (!canSend) return;

    isSending = true;
    sendError = null;
    txid = null;
    notifyListeners();

    try {
      final resultTxid = await _rpc.sideSend(
        addressController.text,
        amountBtc!,
        false,
      );
      txid = resultTxid;

      // Refresh balance and UTXOs
      await Future.wait([
        _balanceProvider.fetch(),
        refreshUtxos(),
      ]);

      if (context.mounted) {
        await successDialog(
          context: context,
          action: 'Send Transaction',
          title: 'Transaction sent successfully',
          subtitle: 'TXID: $resultTxid',
        );
      }
    } catch (e) {
      sendError = e.toString();
      if (context.mounted) {
        await errorDialog(
          context: context,
          action: 'Send Transaction',
          title: 'Failed to send transaction',
          subtitle: e.toString(),
        );
      }
    } finally {
      isSending = false;
      notifyListeners();
    }
  }

  Future<void> clear() async {
    addressController.clear();
    amountController.clear();
    feeController.text = '0.00001';
    selectedUtxos.clear();
    sendError = null;
    txid = null;
    notifyListeners();
  }

  @override
  void dispose() {
    addressController.dispose();
    amountController.dispose();
    feeController.dispose();
    super.dispose();
  }
}
