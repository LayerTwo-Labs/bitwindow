import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/pages/sidechains/sidechain_overview_page.dart';
import 'package:sail_ui/sail_ui.dart';

@RoutePage()
class MempoolExplorerPage extends StatelessWidget {
  const MempoolExplorerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return QtPage(
      child: ViewModelBuilder<MempoolExplorerViewModel>.reactive(
        viewModelBuilder: () => MempoolExplorerViewModel(),
        builder: (context, model, child) {
          final theme = SailTheme.of(context);
          final formatter = GetIt.I<FormatterProvider>();
          final phone = SailStyleValues.phoneLayout(context);

          return SailColumn(
            spacing: SailStyleValues.padding12,
            children: [
              if (phone)
                SailStatList(
                  children: [
                    SailStatRow(
                      title: 'Total UTXOs',
                      subtitle: '',
                      value: model.utxos.length.toString(),
                      loading: LoadingDetails(enabled: model.isLoading, description: 'Loading...'),
                    ),
                    SailStatRow(
                      title: 'Total Value',
                      subtitle: '',
                      value: formatter.formatSats(model.totalValue),
                      loading: LoadingDetails(enabled: model.isLoading, description: 'Loading...'),
                    ),
                  ],
                )
              else
                SailStrip(
                  stats: [
                    SailStat(label: 'Total UTXOs', value: model.utxos.length.toString()),
                    SailStat(label: 'Total Value', value: formatter.formatSats(model.totalValue)),
                  ],
                  actions: [_RefreshButton(model: model)],
                ),
              SidechainNotice(
                message: 'Showing all UTXOs on the sidechain. Full mempool transaction list requires additional RPC support.',
                trailing: phone ? _RefreshButton(model: model) : null,
              ),
              Expanded(
                child: SailCard(
                  title: 'All UTXOs',
                  bottomPadding: false,
                  child: model.errorMessage != null
                      ? Center(child: SailText.primary13(model.errorMessage!, color: theme.colors.error))
                      : ListenableBuilder(
                          listenable: formatter,
                          builder: (context, child) => SailTable(
                            getRowId: (index) => model.utxos[index].outpoint,
                            headerBuilder: (context) => [
                              SailTableHeaderCell(name: 'Outpoint'),
                              SailTableHeaderCell(name: 'Type'),
                              SailTableHeaderCell(name: 'Address'),
                              SailTableHeaderCell(name: 'Value', alignment: Alignment.centerRight),
                            ],
                            rowBuilder: (context, row, selected) {
                              final utxo = model.utxos[row];
                              return [
                                SailTableCell(
                                  value: _truncateOutpoint(utxo.outpoint),
                                  copyValue: utxo.outpoint,
                                  monospace: true,
                                ),
                                SailTableCell(value: utxo.type.name),
                                SailTableCell(
                                  value: _truncateAddress(utxo.address),
                                  copyValue: utxo.address,
                                  monospace: true,
                                ),
                                SailTableCell(
                                  value: formatter.formatSats(utxo.valueSats.toInt()),
                                  monospace: true,
                                  alignment: Alignment.centerRight,
                                ),
                              ];
                            },
                            rowCount: model.utxos.length,
                            drawGrid: true,
                            phoneColumns: const [1, 2, 3],
                            emptyPlaceholder: model.isLoading ? 'Loading UTXOs...' : 'No UTXOs found',
                            contextMenuItems: (rowId) {
                              final utxo = model.utxos.firstWhere((u) => u.outpoint == rowId);
                              return [
                                SailMenuItem(
                                  onSelected: () => Clipboard.setData(ClipboardData(text: utxo.outpoint)),
                                  child: SailText.primary12('Copy outpoint'),
                                ),
                                SailMenuItem(
                                  onSelected: () => Clipboard.setData(ClipboardData(text: utxo.address)),
                                  child: SailText.primary12('Copy address'),
                                ),
                              ];
                            },
                          ),
                        ),
                ),
              ),
            ],
          );
        },
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

  String _truncateAddress(String address) {
    if (address.length <= 16) return address;
    return '${address.substring(0, 8)}...${address.substring(address.length - 4)}';
  }
}

class _RefreshButton extends StatelessWidget {
  final MempoolExplorerViewModel model;

  const _RefreshButton({required this.model});

  @override
  Widget build(BuildContext context) => SailButton(
    label: 'Refresh',
    variant: ButtonVariant.secondary,
    small: true,
    onPressed: model.refresh,
    loading: model.isRefreshing,
  );
}

class MempoolExplorerViewModel extends BaseViewModel {
  PhotonRPC get _rpc => GetIt.I.get<PhotonRPC>();

  List<SidechainUTXO> utxos = [];
  String? errorMessage;
  bool isLoading = true;
  bool isRefreshing = false;
  Timer? _refreshTimer;

  int get totalValue => utxos.fold(0, (sum, utxo) => sum + utxo.valueSats.toInt());

  MempoolExplorerViewModel() {
    _fetchData();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) => _fetchData());
  }

  Future<void> _fetchData() async {
    try {
      errorMessage = null;
      final newUtxos = await _rpc.listAllUTXOs();
      utxos = newUtxos;
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    isRefreshing = true;
    notifyListeners();

    try {
      await _fetchData();
    } finally {
      isRefreshing = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
}
