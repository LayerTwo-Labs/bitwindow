import 'package:auto_route/auto_route.dart';
import 'package:bitassets/providers/bitassets_provider.dart';
import 'package:bitassets/settings/amm_settings.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';

@RoutePage()
class AmmTabPage extends StatelessWidget {
  const AmmTabPage({super.key});

  @override
  Widget build(BuildContext context) {
    return QtPage(
      child: ViewModelBuilder<AmmSwapViewModel>.reactive(
        viewModelBuilder: () => AmmSwapViewModel(),
        builder: (context, model, child) {
          final theme = SailTheme.of(context);
          return SingleChildScrollView(
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: SailCard(
                  title: 'Swap',
                  subtitle: 'Trade BitAssets',
                  error: model.swapError,
                  child: SailColumn(
                    spacing: SailStyleValues.padding08,
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SailText.primary13('You pay'),
                      SailRow(
                        spacing: SailStyleValues.padding08,
                        children: [
                          Expanded(
                            flex: 2,
                            child: SailDropdownButton<String>(
                              value: model.assetSpend,
                              items: model.assetOptions,
                              onChanged: (value) => model.setAssetSpend(value),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: SailTextField(
                              hintText: '0',
                              controller: model.amountSpendController,
                              suffix: model.assetSpend.isEmpty ? activeTicker.symbol : null,
                            ),
                          ),
                        ],
                      ),
                      Center(
                        child: SailIconBoxButton(
                          icon: SailSVGAsset.arrowDownUp,
                          tooltip: 'Swap direction',
                          onPressed: () async => model.swapAssets(),
                        ),
                      ),
                      SailText.primary13('You receive (estimated)'),
                      SailRow(
                        spacing: SailStyleValues.padding08,
                        children: [
                          Expanded(
                            flex: 2,
                            child: SailDropdownButton<String>(
                              value: model.assetReceive,
                              items: model.assetOptions,
                              onChanged: (value) => model.setAssetReceive(value),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: SailTextField(
                              hintText: '0',
                              controller: model.amountReceiveController,
                              readOnly: true,
                              suffix: model.assetReceive.isEmpty ? activeTicker.symbol : null,
                            ),
                          ),
                        ],
                      ),
                      if (model.priceInfo != null)
                        Padding(
                          padding: const EdgeInsets.only(top: SailStyleValues.padding04),
                          child: SailDetailGroup(
                            children: [
                              SailDetailLine(label: 'Rate', value: model.priceInfo!),
                              if (model.feeEstimate != null)
                                SailDetailLine(
                                  label: 'Swap Fee (0.3%)',
                                  value: '~${model.feeEstimate} ${activeTicker.subunit}',
                                ),
                              if (model.minimumReceived != null)
                                SailDetailLine(
                                  label: 'Min. received (${model.slippageTolerance}% slippage)',
                                  value: '~${model.minimumReceived}',
                                ),
                            ],
                          ),
                        ),
                      SailCollapsible(
                        trigger: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: SailText.primary13('Advanced Settings'),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SailText.secondary12('Slippage Tolerance', color: theme.colors.textSecondary),
                              const SizedBox(height: SailStyleValues.padding08),
                              SailSegments(
                                labels: [for (final value in slippageChoices) '$value%'],
                                activeIndex: slippageChoices.indexOf(model.slippageTolerance),
                                onSelect: (index) => model.setSlippage(slippageChoices[index]),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SailButton(
                        label: 'Swap',
                        loading: model.swapLoading,
                        loadingLabel: 'Swapping...',
                        disabled: !model.canSwap,
                        onPressed: () async => model.executeSwap(context),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The slippage tolerances the swap offers, in percent.
const slippageChoices = [0.1, 0.5, 1.0, 2.0];

class AmmSwapViewModel extends BaseViewModel {
  final BitAssetsRPC rpc = GetIt.I.get<BitAssetsRPC>();
  final BitAssetsProvider bitAssetsProvider = GetIt.I.get<BitAssetsProvider>();
  final NotificationProvider notificationProvider = GetIt.I.get<NotificationProvider>();
  final ClientSettings _settings = GetIt.I.get<ClientSettings>();

  final TextEditingController amountSpendController = TextEditingController();
  final TextEditingController amountReceiveController = TextEditingController();

  String assetSpend = ''; // empty string = BTC
  String assetReceive = '';
  String? swapError;
  String? priceInfo;
  bool swapLoading = false;
  double slippageTolerance = 0.5;

  AmmSwapViewModel() {
    bitAssetsProvider.addListener(notifyListeners);
    bitAssetsProvider.fetch();
    amountSpendController.addListener(_onAmountChanged);
    _loadSlippage();
  }

  Future<void> _loadSlippage() async {
    final setting = await _settings.getValue(SlippageToleranceSetting());
    slippageTolerance = setting.value;
    notifyListeners();
  }

  void setSlippage(double value) {
    slippageTolerance = value;
    _settings.setValue(SlippageToleranceSetting(newValue: value));
    notifyListeners();
  }

  int? get feeEstimate {
    final amount = int.tryParse(amountSpendController.text);
    if (amount == null || amount <= 0) return null;
    return (amount * 0.003).round();
  }

  String? get minimumReceived {
    final receiveAmount = int.tryParse(amountReceiveController.text);
    if (receiveAmount == null || receiveAmount <= 0) return null;
    final minAmount = (receiveAmount * (1 - slippageTolerance / 100)).round();
    return minAmount.toString();
  }

  List<SailDropdownItem<String>> get assetOptions {
    final options = <SailDropdownItem<String>>[
      SailDropdownItem(value: '', label: '${activeTicker.symbol} (Native)'),
    ];

    for (final entry in bitAssetsProvider.entries) {
      final label = entry.plaintextName ?? entry.hash.substring(0, 12);
      options.add(SailDropdownItem(value: entry.hash, label: label));
    }

    return options;
  }

  bool get canSwap {
    if (assetSpend == assetReceive) return false;
    final amount = int.tryParse(amountSpendController.text);
    return amount != null && amount > 0;
  }

  void setAssetSpend(String? value) {
    if (value == null) return;
    assetSpend = value;
    _updatePrice();
    notifyListeners();
  }

  void setAssetReceive(String? value) {
    if (value == null) return;
    assetReceive = value;
    _updatePrice();
    notifyListeners();
  }

  void swapAssets() {
    final temp = assetSpend;
    assetSpend = assetReceive;
    assetReceive = temp;

    final tempAmount = amountSpendController.text;
    amountSpendController.text = amountReceiveController.text;
    amountReceiveController.text = tempAmount;

    _updatePrice();
    notifyListeners();
  }

  void _onAmountChanged() {
    _updatePrice();
  }

  Future<void> _updatePrice() async {
    if (assetSpend == assetReceive) {
      priceInfo = null;
      amountReceiveController.text = '';
      notifyListeners();
      return;
    }

    try {
      final price = await rpc.getAmmPrice(
        base: assetSpend.isEmpty ? 'btc' : assetSpend,
        quote: assetReceive.isEmpty ? 'btc' : assetReceive,
      );

      if (price != null) {
        final base = price['base'];
        final quote = price['quote'];
        if (base != null && quote != null) {
          priceInfo =
              '1 ${_assetLabel(assetSpend)} = ${(quote / base).toStringAsFixed(6)} ${_assetLabel(assetReceive)}';

          // Update estimated receive amount
          final spendAmount = int.tryParse(amountSpendController.text);
          if (spendAmount != null && spendAmount > 0) {
            final estimated = (spendAmount * quote / base).round();
            amountReceiveController.text = estimated.toString();
          }
        }
      } else {
        priceInfo = 'No liquidity pool exists for this pair';
        amountReceiveController.text = '';
      }
    } catch (e) {
      priceInfo = null;
      amountReceiveController.text = '';
    }
    notifyListeners();
  }

  String _assetLabel(String assetId) {
    if (assetId.isEmpty) return activeTicker.symbol;
    final entry = bitAssetsProvider.entries.where((e) => e.hash == assetId).firstOrNull;
    return entry?.plaintextName ?? assetId.substring(0, 8);
  }

  Future<void> executeSwap(BuildContext context) async {
    swapError = null;
    swapLoading = true;
    notifyListeners();

    try {
      final amountSpend = int.parse(amountSpendController.text);

      final amountReceived = await rpc.ammSwap(
        assetSpend: assetSpend.isEmpty ? 'btc' : assetSpend,
        assetReceive: assetReceive.isEmpty ? 'btc' : assetReceive,
        amountSpend: amountSpend,
      );

      if (context.mounted) {
        notificationProvider.add(
          title: 'Swap Successful',
          content: 'Received $amountReceived ${_assetLabel(assetReceive)}',
          dialogType: DialogType.success,
        );
      }

      // Clear form
      amountSpendController.clear();
      amountReceiveController.clear();
    } catch (e) {
      swapError = e.toString();
    } finally {
      swapLoading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    amountSpendController.removeListener(_onAmountChanged);
    amountSpendController.dispose();
    amountReceiveController.dispose();
    bitAssetsProvider.removeListener(notifyListeners);
    super.dispose();
  }
}
