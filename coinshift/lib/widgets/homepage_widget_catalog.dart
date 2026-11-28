import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sail_ui/pages/sidechains/sidechain_overview_page.dart';
import 'package:coinshift/providers/swap_provider.dart';
import 'package:coinshift/widgets/swap/swap_card.dart';
import 'package:coinshift/widgets/swap/swap_status_badge.dart';
import 'package:coinshift/widgets/swap_scheduler_widget.dart';
import 'package:coinshift/widgets/liquidity_monitor_widget.dart';
import 'package:coinshift/widgets/swap_failure_recovery.dart';

class CoinShiftWidgetCatalog {
  static final Map<String, HomepageWidgetInfo> _widgets = {
    'quote_bar': HomepageWidgetInfo(
      id: 'quote_bar',
      name: 'Quotes',
      sizes: [WidgetSize.bar],
      builder: (_) => const QuoteBar(),
    ),
    'balance_card': HomepageWidgetInfo(
      id: 'balance_card',
      name: 'Balance Card',
      sizes: [WidgetSize.half],
      builder: (_) => ViewModelBuilder<OverviewTabViewModel>.reactive(
        viewModelBuilder: () => OverviewTabViewModel(),
        builder: (context, model, child) {
          final formatter = GetIt.I<FormatterProvider>();
          return ListenableBuilder(
            listenable: formatter,
            builder: (context, child) => SidechainBalanceCard(
              total: formatter.formatBTC(model.totalBalance),
              available: formatter.formatBTC(model.balance),
              pending: formatter.formatBTC(model.pendingBalance),
              loading: !model.balanceInitialized,
              loadingDescription: 'Waiting for coinshift to boot...',
            ),
          );
        },
      ),
    ),

    'receive_card': HomepageWidgetInfo(
      id: 'receive_card',
      name: 'Receive Card',
      sizes: [WidgetSize.half],
      builder: (_) => ViewModelBuilder<OverviewTabViewModel>.reactive(
        viewModelBuilder: () => OverviewTabViewModel(),
        builder: (context, model, child) => SidechainReceiveCard(model: model),
      ),
    ),

    'send_card': HomepageWidgetInfo(
      id: 'send_card',
      name: 'Send Card',
      sizes: [WidgetSize.half],
      builder: (_) => ViewModelBuilder<OverviewTabViewModel>.reactive(
        viewModelBuilder: () => OverviewTabViewModel(),
        builder: (context, model, child) => SidechainSendCard(model: model),
      ),
    ),

    'swap_card': HomepageWidgetInfo(
      id: 'swap_card',
      name: 'Quick Swap',
      sizes: [WidgetSize.half],
      builder: (_) => const SwapCard(),
    ),

    'active_swaps': HomepageWidgetInfo(
      id: 'active_swaps',
      name: 'Active Swaps',
      sizes: [WidgetSize.full],
      builder: (_) => SizedBox(
        height: 300,
        child: _ActiveSwapsWidget(),
      ),
    ),

    'utxo_table': HomepageWidgetInfo(
      id: 'utxo_table',
      name: 'Transaction History',
      sizes: [WidgetSize.full],
      builder: (_) => const SizedBox(
        height: 400,
        child: UTXOsTab(showStatus: false),
      ),
    ),

    'swap_scheduler': HomepageWidgetInfo(
      id: 'swap_scheduler',
      name: 'Swap Scheduler',
      sizes: [WidgetSize.half],
      builder: (_) => const SizedBox(
        height: 450,
        child: SwapSchedulerWidget(),
      ),
    ),

    'liquidity_monitor': HomepageWidgetInfo(
      id: 'liquidity_monitor',
      name: 'Liquidity Monitor',
      sizes: [WidgetSize.full],
      builder: (_) => const SizedBox(
        height: 350,
        child: LiquidityMonitorWidget(),
      ),
    ),

    'swap_recovery': HomepageWidgetInfo(
      id: 'swap_recovery',
      name: 'Swap Recovery',
      sizes: [WidgetSize.full],
      builder: (_) => const SizedBox(
        height: 400,
        child: SwapFailureRecoveryWidget(),
      ),
    ),
  };

  static Map<String, HomepageWidgetInfo> getCatalogMap() {
    return Map.from(_widgets);
  }
}

class _ActiveSwapsWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<_ActiveSwapsViewModel>.reactive(
      viewModelBuilder: () => _ActiveSwapsViewModel(),
      builder: (context, model, child) {
        final formatter = GetIt.I<FormatterProvider>();

        return SailCard(
          title: 'Active Swaps (${model.activeSwaps.length})',
          bottomPadding: false,
          child: model.activeSwaps.isEmpty
              ? Center(
                  child: SailText.secondary13('No active swaps'),
                )
              : ListenableBuilder(
                  listenable: formatter,
                  builder: (context, child) => ListView.builder(
                    itemCount: model.activeSwaps.length,
                    itemBuilder: (context, index) => _ActiveSwapRow(
                      swap: model.activeSwaps[index],
                      formatter: formatter,
                      onClaim: () => model.claimSwap(context, model.activeSwaps[index]),
                    ),
                  ),
                ),
        );
      },
    );
  }
}

/// One active swap: direction and amount over the chain, its status, and a "…" with Claim.
class _ActiveSwapRow extends StatelessWidget {
  final CoinShiftSwap swap;
  final FormatterProvider formatter;
  final Future<void> Function() onClaim;

  const _ActiveSwapRow({required this.swap, required this.formatter, required this.onClaim});

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: SailStyleValues.padding08, vertical: SailStyleValues.padding08),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.colors.divider)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SailText.primary13(
                  '${swap.direction == SwapDirection.l2ToL1 ? 'L2→L1' : 'L1→L2'} - ${formatter.formatSats(swap.l2Amount)}',
                ),
                SailText.secondary12('Chain: ${swap.parentChain.label}'),
              ],
            ),
          ),
          SwapStatusBadge(state: swap.state),
          const SizedBox(width: SailStyleValues.padding16),
          SailRowMenuButton(
            items: () => [
              if (swap.state.isReadyToClaim)
                SailMenuItem(onSelected: () => onClaim(), child: SailText.primary12('Claim')),
              SailMenuItem(
                onSelected: () => Clipboard.setData(ClipboardData(text: swap.idHex)),
                child: SailText.primary12('Copy swap ID'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActiveSwapsViewModel extends BaseViewModel {
  SwapProvider get _swapProvider => GetIt.I.get<SwapProvider>();

  List<CoinShiftSwap> get activeSwaps => _swapProvider.activeSwaps;

  _ActiveSwapsViewModel() {
    _swapProvider.addListener(notifyListeners);
  }

  Future<void> claimSwap(BuildContext context, CoinShiftSwap swap) async {
    final txid = await _swapProvider.claimSwap(swap);
    if (txid != null && context.mounted) {
      showSailToast(
        context,
        'Swap claimed! TXID: $txid',
      );
    }
  }

  @override
  void dispose() {
    _swapProvider.removeListener(notifyListeners);
    super.dispose();
  }
}
