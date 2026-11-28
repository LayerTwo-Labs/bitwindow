import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sail_ui/pages/sidechains/sidechain_overview_page.dart';
import 'package:photon/widgets/miner_widget.dart';
import 'package:photon/widgets/parent_chain_info_widget.dart';

class PhotonWidgetCatalog {
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
              loadingDescription: 'Waiting for photon to boot...',
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

    'utxo_table': HomepageWidgetInfo(
      id: 'utxo_table',
      name: 'Transaction History',
      sizes: [WidgetSize.full],
      builder: (_) => SizedBox(
        height: 400, // Fixed height to prevent layout issues
        child: UTXOsTab(showStatus: false),
      ),
    ),

    'miner': HomepageWidgetInfo(
      id: 'miner',
      name: 'Miner',
      sizes: [WidgetSize.half],
      builder: (_) => const MinerWidget(),
    ),

    'parent_chain_info': HomepageWidgetInfo(
      id: 'parent_chain_info',
      name: 'Parent Chain Info',
      sizes: [WidgetSize.half],
      builder: (_) => const ParentChainInfoWidget(),
    ),
  };

  static Map<String, HomepageWidgetInfo> getCatalogMap() {
    return Map.from(_widgets);
  }
}
