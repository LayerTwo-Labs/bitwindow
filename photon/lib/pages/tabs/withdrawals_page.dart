import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';

@RoutePage()
class WithdrawalsPage extends StatelessWidget {
  const WithdrawalsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return QtPage(
      child: ViewModelBuilder<WithdrawalsViewModel>.reactive(
        viewModelBuilder: () => WithdrawalsViewModel(),
        builder: (context, model, child) {
          final theme = SailTheme.of(context);
          final formatter = GetIt.I<FormatterProvider>();
          final bundle = model.bundle;

          return SailColumn(
            spacing: SailStyleValues.padding12,
            children: [
              SailStrip(
                stats: [
                  SailStatusPill(
                    label: bundle != null
                        ? 'Pending Withdrawals: ${bundle.spendUtxos.length} UTXOs'
                        : 'No pending withdrawal bundle',
                    tone: bundle != null ? SailStatusTone.success : SailStatusTone.neutral,
                  ),
                  if (model.lastFailedHeight != null)
                    SailText.primary12(
                      'Last failed bundle at height: ${model.lastFailedHeight}',
                      color: theme.colors.error,
                    ),
                ],
                actions: [
                  SailButton(
                    label: 'Refresh',
                    variant: ButtonVariant.secondary,
                    small: true,
                    onPressed: model.refresh,
                    loading: model.isRefreshing,
                  ),
                ],
              ),
              if (bundle != null)
                SailCard(
                  title: 'Bundle Summary',
                  child: ListenableBuilder(
                    listenable: formatter,
                    builder: (context, child) => Wrap(
                      spacing: SailStyleValues.padding20,
                      runSpacing: SailStyleValues.padding08,
                      children: [
                        SailStat(label: 'Height Created', value: bundle.heightCreated.toString()),
                        SailStat(label: 'Total Value', value: formatter.formatSats(bundle.totalValue)),
                        SailStat(label: 'UTXOs', value: bundle.spendUtxos.length.toString()),
                      ],
                    ),
                  ),
                ),
              Expanded(
                child: SailCard(
                  title: 'Spent UTXOs',
                  bottomPadding: false,
                  child: bundle == null
                      ? Center(child: SailText.secondary13('No pending bundle'))
                      : ListenableBuilder(
                          listenable: formatter,
                          builder: (context, child) => SailTable(
                            getRowId: (index) => _formatOutPoint(bundle.spendUtxos[index].outPoint),
                            headerBuilder: (context) => [
                              SailTableHeaderCell(name: 'Outpoint'),
                              SailTableHeaderCell(name: 'Value', alignment: Alignment.centerRight),
                            ],
                            rowBuilder: (context, row, selected) {
                              final utxo = bundle.spendUtxos[row];
                              final outpointStr = _formatOutPoint(utxo.outPoint);
                              final value = utxo.output.content.type == OutputContentType.value
                                  ? formatter.formatSats(utxo.output.content.value!)
                                  : '-';
                              return [
                                SailTableCell(
                                  value: _truncateOutpoint(outpointStr),
                                  copyValue: outpointStr,
                                  monospace: true,
                                ),
                                SailTableCell(value: value, monospace: true, alignment: Alignment.centerRight),
                              ];
                            },
                            rowCount: bundle.spendUtxos.length,
                            drawGrid: true,
                            emptyPlaceholder: 'No UTXOs in bundle',
                            contextMenuItems: (rowId) => [
                              SailMenuItem(
                                onSelected: () => Clipboard.setData(ClipboardData(text: rowId)),
                                child: SailText.primary12('Copy outpoint'),
                              ),
                            ],
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

  String _formatOutPoint(PWBOutPoint outPoint) {
    switch (outPoint.type) {
      case OutPointType.regular:
        final regular = outPoint.regular!;
        return '${regular.txid}:${regular.vout}';
      case OutPointType.coinbase:
        final coinbase = outPoint.coinbase!;
        return 'coinbase:${coinbase.merkleRoot}:${coinbase.vout}';
      case OutPointType.deposit:
        final deposit = outPoint.deposit!;
        return 'deposit:${deposit.txid}:${deposit.vout}';
      case OutPointType.unsuccessfulWithdrawal:
        final unsuccessfulWithdrawal = outPoint.unsuccessfulWithdrawal!;
        return 'unsuccessful-withdrawal:${unsuccessfulWithdrawal.m6id}:${unsuccessfulWithdrawal.vout}';
    }
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

class WithdrawalsViewModel extends BaseViewModel {
  PhotonRPC get _rpc => GetIt.I.get<PhotonRPC>();

  PendingWithdrawalBundle? bundle;
  int? lastFailedHeight;
  bool isRefreshing = false;
  Timer? _refreshTimer;

  WithdrawalsViewModel() {
    _fetchData();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) => _fetchData());
  }

  Future<void> _fetchData() async {
    try {
      final bundleFuture = _rpc.getPendingWithdrawalBundle();
      final failedHeightFuture = _rpc.getLatestFailedWithdrawalBundleHeight();

      final results = await Future.wait([bundleFuture, failedHeightFuture]);

      final newBundle = results[0] as PendingWithdrawalBundle?;
      final newFailedHeight = results[1] as int?;

      if (bundle?.toJson() != newBundle?.toJson() || lastFailedHeight != newFailedHeight) {
        bundle = newBundle;
        lastFailedHeight = newFailedHeight;
        notifyListeners();
      }
    } catch (e) {
      // Ignore errors during refresh
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
