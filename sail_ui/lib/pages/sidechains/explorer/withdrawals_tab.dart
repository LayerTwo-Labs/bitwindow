import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/gen/explorer/v1/explorer.pb.dart' as pb;

/// WithdrawalsTab reads the bundle the chain proposes to the mainchain, and
/// the withdrawals inside it.
class WithdrawalsTab extends StatelessWidget {
  /// True makes the table fill the height it gets.
  final bool fill;

  const WithdrawalsTab({super.key, this.fill = true});

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<WithdrawalsModel>.reactive(
      viewModelBuilder: () => WithdrawalsModel(),
      builder: (context, model, child) {
        final state = model.state;
        if (state == null) {
          return Align(
            alignment: Alignment.topCenter,
            child: SailCard(
              title: 'Withdrawals',
              subtitle: model.readError ?? 'Reading the bundle',
              child: const SizedBox(height: 40),
            ),
          );
        }
        final table = _BundleTable(bundle: state.bundle);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _BundleSummary(state: state),
            const SizedBox(height: SailStyleValues.padding12),
            if (fill) Expanded(child: table) else SizedBox(height: 320, child: table),
          ],
        );
      },
    );
  }
}

class _BundleSummary extends StatelessWidget {
  final pb.GetWithdrawalsResponse state;

  const _BundleSummary({required this.state});

  @override
  Widget build(BuildContext context) {
    final bundle = state.bundle;
    final failed = state.lastFailedHeight == 0 ? '—' : 'Height ${state.lastFailedHeight}';
    final subtitle = !bundle.present
        ? 'The chain proposes none'
        : bundle.heightCreated != 0
        ? '${bundle.withdrawals.length} withdrawals, pending since height ${bundle.heightCreated}'
        : '${bundle.withdrawals.length} withdrawals pending';
    final theme = SailTheme.of(context);
    return DecoratedBox(
      decoration: theme.chrome.panel(theme.colors),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SailText.primary15('The bundle now', bold: true),
                  SailText.secondary13(subtitle),
                ],
              ),
            ),
            const SizedBox(width: SailStyleValues.padding16),
            Wrap(
              spacing: 40,
              runSpacing: SailStyleValues.padding08,
              children: [
                if (bundle.present) ...[
                  SailStat(label: 'Total amount', value: '${bundle.totalValueSats} sats'),
                  SailStat(label: 'Total mainchain fees', value: '${bundle.totalMainFeesSats} sats'),
                  SailStat(label: 'Bundle weight', value: '${bundle.totalWeight} / ${bundle.maxWeight}'),
                ],
                SailStat(label: 'Last failed bundle', value: failed),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BundleTable extends StatelessWidget {
  final pb.WithdrawalBundle bundle;

  const _BundleTable({required this.bundle});

  @override
  Widget build(BuildContext context) {
    final rows = bundle.withdrawals;
    return SailCard(
      title: 'In this bundle',
      widgetHeaderEnd: SailText.secondary13(
        '${rows.length} withdrawals · ${bundle.totalWeight} of ${bundle.maxWeight} weight',
      ),
      bottomPadding: false,
      child: SailTable(
        getRowId: (index) => '${rows[index].mainAddress}:$index',
        headerBuilder: (context) => const [
          SailTableHeaderCell(name: 'Amount', alignment: Alignment.centerRight),
          SailTableHeaderCell(name: 'Mainchain fee', alignment: Alignment.centerRight),
          SailTableHeaderCell(name: 'Destination address'),
          SailTableHeaderCell(name: 'Bundle weight', alignment: Alignment.centerRight),
        ],
        rowBuilder: (context, index, selected) {
          final row = rows[index];
          return [
            SailTableCell(value: explorerAmount(context, row.valueSats.toInt()), alignment: Alignment.centerRight),
            SailTableCell(value: explorerAmount(context, row.mainFeeSats.toInt()), alignment: Alignment.centerRight),
            SailTableCell(value: row.mainAddress, monospace: true),
            SailTableCell(value: '${row.cumulativeWeight} / ${bundle.maxWeight}', alignment: Alignment.centerRight),
          ];
        },
        rowCount: rows.length,
        contextMenuItems: (rowId) => [
          SailMenuItem(
            onSelected: () async {
              final address = rowId.substring(0, rowId.lastIndexOf(':'));
              await Clipboard.setData(ClipboardData(text: address));
            },
            child: SailText.primary12('Copy address'),
          ),
        ],
        emptyPlaceholder: 'No withdrawals in the bundle',
      ),
    );
  }
}
