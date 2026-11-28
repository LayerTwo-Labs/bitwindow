import 'dart:async';
import 'dart:convert';

import 'package:bitwindow/pages/explorer/block_explorer_dialog.dart';
import 'package:bitwindow/pages/wallet/bump_fee_dialog.dart';
import 'package:bitwindow/providers/address_book_provider.dart';
import 'package:bitwindow/providers/transactions_provider.dart';
import 'package:bitwindow/utils/transaction_search.dart';
import 'package:bitwindow/utils/wallet_amount.dart';
import 'package:collection/collection.dart';
import 'package:bitwindow/utils/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fixnum/fixnum.dart';
import 'package:bitwindow/pages/wallet/wallet_page.dart';
import 'package:bitwindow/pages/wallet/widgets/wallet_v2_parts.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';
import 'package:sidechain_core/gen/wallet/v1/wallet.pb.dart';
import 'package:sail_ui/sail_ui.dart';

String _formatTimeAgo(DateTime when) {
  final d = DateTime.now().difference(when);
  if (d.inDays > 0) {
    return '${d.inDays} day${d.inDays == 1 ? '' : 's'} ago';
  }
  if (d.inHours > 0) {
    return '${d.inHours} hour${d.inHours == 1 ? '' : 's'} ago';
  }
  if (d.inMinutes > 0) {
    return '${d.inMinutes} minute${d.inMinutes == 1 ? '' : 's'} ago';
  }
  final s = d.inSeconds < 0 ? 0 : d.inSeconds;
  return '$s second${s == 1 ? '' : 's'} ago';
}

/// The subtitle of the lifetime fees card.
String feesSubtitle(int transactions) => 'across $transactions transaction${transactions == 1 ? '' : 's'}';

/// The subtitle of the last activity card: the block of the newest transaction.
String lastActivitySubtitle(GetStatsResponse? stats) {
  if (stats == null || !stats.hasLastTxAt()) {
    return '';
  }
  if (stats.lastTxBlockHeight == 0) {
    return 'Unconfirmed';
  }
  return 'at block ${formatWithThousandSpacers(stats.lastTxBlockHeight)}';
}

class OverviewTab extends StatelessWidget {
  const OverviewTab({super.key});

  @override
  Widget build(BuildContext context) {
    final formatter = GetIt.I<FormatterProvider>();
    return ViewModelBuilder<OverviewViewModel>.reactive(
      viewModelBuilder: () => OverviewViewModel(),
      builder: (context, model, child) {
        return ListenableBuilder(
          listenable: formatter,
          builder: (context, child) {
            if (SailStyleValues.phoneLayout(context)) {
              return _PhoneOverview(model: model, formatter: formatter);
            }
            return WalletOverviewDesktop(model: model);
          },
        );
      },
    );
  }
}

class _PhoneOverview extends StatelessWidget {
  final OverviewViewModel model;
  final FormatterProvider formatter;

  const _PhoneOverview({required this.model, required this.formatter});

  @override
  Widget build(BuildContext context) {
    final conf = GetIt.I.get<BitcoinConfProvider>();
    return SingleChildScrollView(
      child: SailColumn(
        spacing: SailStyleValues.padding16,
        children: [
          _StatsGrid(
            phone: true,
            stats: [
              WalletStats(
                title: 'Lifetime fees paid',
                value: formatter
                    .formatSats(model.stats?.totalFeesSats.toInt() ?? 0)
                    .replaceAll(' ${formatter.currentUnit.symbol}', ''),
                subtitle: feesSubtitle(model.stats?.transactionCountTotal.toInt() ?? 0),
                bitcoinAmount: true,
                icon: SailSVGAsset.bitcoin,
              ),
              WalletStats(
                title: 'Number of UTXOs',
                value: model.stats?.utxosCurrent.toString() ?? '0',
                subtitle:
                    '${model.stats?.utxosUniqueAddresses.toString() ?? '0'} unique address${model.stats?.utxosUniqueAddresses.toInt() == 1 ? '' : 'es'}',
                icon: SailSVGAsset.coins,
              ),
              SailTooltip(
                message: conf.networkSupportsSidechains ? '' : 'Sidechains require eCash or Signet network',
                child: Opacity(
                  opacity: conf.networkSupportsSidechains ? 1.0 : 0.4,
                  child: WalletStats(
                    title: 'Sidechain Deposit Volume',
                    phoneTitle: 'Sidechain deposits',
                    value: conf.networkSupportsSidechains
                        ? formatter
                              .formatSats(model.stats?.sidechainDepositVolume.toInt() ?? 0)
                              .replaceAll(' ${formatter.currentUnit.symbol}', '')
                        : '-',
                    subtitle: conf.networkSupportsSidechains
                        ? '${formatter.formatSats(model.stats?.sidechainDepositVolumeLast30Days.toInt() ?? 0)} last 30 days'
                        : 'Switch networks to unlock',
                    bitcoinAmount: conf.networkSupportsSidechains,
                    icon: SailSVGAsset.wallet,
                  ),
                ),
              ),
              WalletStats(
                title: 'Last activity',
                value: model.stats?.hasLastTxAt() ?? false
                    ? _formatTimeAgo(model.stats!.lastTxAt.toDateTime().toLocal())
                    : 'No activity',
                subtitle: lastActivitySubtitle(model.stats),
                icon: SailSVGAsset.activity,
              ),
            ],
          ),
          TransactionTable(
            model: model,
            searchWidget: SailTextField(
              controller: model.searchController,
              hintText: _searchHint,
            ),
          ),
        ],
      ),
    );
  }
}

const String _searchHint = 'Search with txid, address or amount';

/// The UTXO stat of the strip, such as "6 on 5 addresses".
String utxoStatText(GetStatsResponse? stats) {
  final addresses = stats?.utxosUniqueAddresses.toInt() ?? 0;
  return '${stats?.utxosCurrent.toInt() ?? 0} on $addresses address${addresses == 1 ? '' : 'es'}';
}

/// The desktop Overview: the balance strip over the transactions, and the side panel of the selected one.
class WalletOverviewDesktop extends StatefulWidget {
  final OverviewViewModel model;

  const WalletOverviewDesktop({super.key, required this.model});

  @override
  State<WalletOverviewDesktop> createState() => _WalletOverviewDesktopState();
}

class _WalletOverviewDesktopState extends State<WalletOverviewDesktop> {
  String? _selectedTxid;

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    final selected = model.loading ? null : model.entries.firstWhereOrNull((tx) => tx.txid == _selectedTxid);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WalletStripScroll(child: WalletBalanceStrip(model: model)),
        const SizedBox(height: walletGap),
        Expanded(
          child: SailPageWithPanel(
            narrowWidth: walletNarrowWidth,
            panel: selected == null
                ? null
                : TransactionSidePanel(
                    tx: selected,
                    model: model,
                    onClose: () async => setState(() => _selectedTxid = null),
                  ),
            child: TransactionTable(
              model: model,
              searchWidget: WalletSearchField(controller: model.searchController, hintText: _searchHint),
              selectedTxid: selected?.txid,
              onRowTap: (txid) => setState(() => _selectedTxid = txid == _selectedTxid ? null : txid),
            ),
          ),
        ),
      ],
    );
  }
}

/// The top strip of the Overview: the balance, the wallet stats, and Send and Receive.
class WalletBalanceStrip extends StatelessWidget {
  final OverviewViewModel model;

  const WalletBalanceStrip({super.key, required this.model});

  @override
  Widget build(BuildContext context) {
    final balance = GetIt.I<BalanceProvider>();
    final conf = GetIt.I<BitcoinConfProvider>();
    final formatter = GetIt.I<FormatterProvider>();
    final stats = model.stats;
    // A failed read must not leave the last numbers up as if they were new.
    final failed = model.statsError != null;
    String value(String text) => failed ? '-' : text;
    final balanceSats = btcToSatoshi(balance.balance);

    return SailSkeletonizer(
      description: _loadingDescription,
      enabled: model.loading,
      child: SailStrip(
        lead: WalletAmountBlock(
          label: 'Balance',
          amount: formatter.formatSats(balanceSats),
          sats: '${formatWithThousandSpacers(balanceSats)} sats',
        ),
        stats: [
          SailStat(label: 'Unconfirmed', value: walletAmountText(btcToSatoshi(balance.pendingBalance))),
          SailStat(label: 'Lifetime fees', value: value(walletAmountText(stats?.totalFeesSats.toInt() ?? 0))),
          SailStat(label: 'UTXOs', value: value(utxoStatText(stats))),
          SailTooltip(
            message: conf.networkSupportsSidechains ? '' : 'Sidechains require eCash or Signet network',
            child: Opacity(
              opacity: conf.networkSupportsSidechains ? 1.0 : 0.4,
              child: SailStat(
                label: 'Sidechain deposits, 30 days',
                value: conf.networkSupportsSidechains
                    ? value(walletAmountText(stats?.sidechainDepositVolumeLast30Days.toInt() ?? 0))
                    : '-',
              ),
            ),
          ),
          SailStat(
            label: 'Last activity',
            value: value(
              stats?.hasLastTxAt() ?? false ? _formatTimeAgo(stats!.lastTxAt.toDateTime().toLocal()) : 'No activity',
            ),
          ),
        ],
        actions: [
          SailButton(label: 'Send', onPressed: () async => WalletPage.openSubtab('Send')),
          SailButton(
            label: 'Receive',
            variant: ButtonVariant.secondary,
            onPressed: () async => WalletPage.openSubtab('Receive'),
          ),
        ],
      ),
    );
  }
}

/// The title of a history row: its note, else Received or Sent.
String transactionTitle(WalletTransaction tx) {
  if (tx.note.isNotEmpty) {
    return tx.note;
  }
  return walletNetSats(tx) > 0 ? 'Received' : 'Sent';
}

/// The second line of the status of a history row.
String transactionStatusDetail(WalletTransaction tx) {
  if (tx.abandoned) {
    return '';
  }
  if (tx.immature) {
    final left = coinbaseMaturity - tx.confirmations;
    return '$left block${left == 1 ? '' : 's'} left';
  }
  return confirmationsText(tx.confirmations);
}

/// The dot color of a transaction status.
SailStatusTone transactionTone(WalletTransaction tx) {
  if (tx.abandoned || canCancelBid(tx)) {
    return SailStatusTone.neutral;
  }
  if (tx.immature) {
    return SailStatusTone.info;
  }
  return tx.confirmations == 0 ? SailStatusTone.warning : SailStatusTone.success;
}

/// The one main action of a transaction panel, or null.
enum TransactionPrimary { cancelBid, bumpFee, accelerate }

TransactionPrimary? transactionPrimary(WalletTransaction tx) {
  if (canCancelBid(tx)) {
    return TransactionPrimary.cancelBid;
  }
  if (canBumpFee(tx)) {
    return TransactionPrimary.bumpFee;
  }
  if (canAccelerate(tx)) {
    return TransactionPrimary.accelerate;
  }
  return null;
}

/// The row menu of a transaction, without [skip], the action the panel shows as its button.
List<SailMenuEntity> transactionMenuItems(
  BuildContext context,
  OverviewViewModel model,
  WalletTransaction entry, {
  TransactionPrimary? skip,
  bool copyTxid = false,
}) {
  return [
    if (copyTxid)
      SailMenuItem(
        onSelected: () async {
          await Clipboard.setData(ClipboardData(text: entry.txid));
          if (context.mounted) {
            showSailToast(context, 'TXID copied to clipboard');
          }
        },
        child: SailText.primary12('Copy TXID'),
      ),
    SailMenuItem(
      onSelected: () async {
        await showTransactionDetails(context, entry.txid);
      },
      child: SailText.primary12('Show Details'),
    ),
    SailMenuItem(
      onSelected: () async {
        await Future.microtask(() async {
          if (!context.mounted) {
            return;
          }
          await showNoteDialog(context, model, entry);
        });
      },
      child: SailText.primary12(entry.note.isEmpty ? 'Add Note' : 'Update Note'),
    ),
    if (canCancelBid(entry) && skip != TransactionPrimary.cancelBid)
      SailMenuItem(
        onSelected: () async {
          await model.cancelBid(context, entry);
        },
        child: SailText.primary12('Cancel bid'),
      ),
    if (canBumpFee(entry) && skip != TransactionPrimary.bumpFee)
      SailMenuItem(
        onSelected: () async {
          await model.openBumpFee(context, entry);
        },
        child: SailText.primary12('Bump fee'),
      ),
    // CPFP - accelerate an unconfirmed incoming tx whose
    // output this wallet can spend (RBF can't bump it).
    if (canAccelerate(entry) && skip != TransactionPrimary.accelerate)
      SailMenuItem(
        onSelected: () async {
          await model.accelerateCpfp(context, entry);
        },
        child: SailText.primary12('Accelerate (CPFP)'),
      ),
    MempoolMenuItem(txid: entry.txid),
  ];
}

Future<void> showNoteDialog(BuildContext context, OverviewViewModel model, WalletTransaction entry) {
  return showThemedDialog(
    context: context,
    builder: (context) => SailModal(
      constraints: const BoxConstraints(maxWidth: 400),
      child: SailCardEditValues(
        title: entry.note.isEmpty ? 'Add Note' : 'Edit Note',
        subtitle: "${entry.note.isEmpty ? "Set a" : "Update the"} note and click Save when you're done",
        fields: [
          EditField(name: 'Note', currentValue: entry.note),
        ],
        onSave: (updatedFields) async {
          final newNote = updatedFields.firstWhere((f) => f.name == 'Note').currentValue;
          await model.saveNote(context, entry.txid, newNote);
          return null;
        },
      ),
    ),
  );
}

/// The side panel of one transaction: amount, status, the one main action and the details.
class TransactionSidePanel extends StatelessWidget {
  final WalletTransaction tx;
  final OverviewViewModel model;
  final Future<void> Function() onClose;

  const TransactionSidePanel({super.key, required this.tx, required this.model, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    final formatter = GetIt.I<FormatterProvider>();
    final net = walletNetSats(tx);
    final primary = transactionPrimary(tx);
    final time = tx.confirmationTime.timestamp.toDateTime().toLocal();
    final detail = transactionStatusDetail(tx);
    final addresses = transactionAddresses(tx);

    return SailSidePanel(
      title: transactionTitle(tx),
      menuItems: () => transactionMenuItems(context, model, tx, skip: primary, copyTxid: true),
      onClose: onClose,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WalletAmountBlock(
            amount: '${net > 0 ? '+' : '-'}${formatter.formatSats(net.abs())}',
            sats: '${formatWithThousandSpacers(net.abs())} sats',
            color: tx.abandoned ? theme.colors.textSecondary : null,
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: SailStatusPill(
              label: detail.isEmpty ? transactionStatus(tx) : '${transactionStatus(tx)} \u00b7 $detail',
              tone: transactionTone(tx),
            ),
          ),
          if (tx.abandoned) ...[
            const SizedBox(height: 8),
            SailText.secondary13(abandonedHint),
          ],
          if (tx.warningMessage.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            SailText.primary13(tx.warningMessage, color: theme.colors.orange, overflow: TextOverflow.visible),
          ],
          if (primary != null) ...[
            const SizedBox(height: 16),
            SailButton(
              label: switch (primary) {
                TransactionPrimary.cancelBid => 'Cancel bid',
                TransactionPrimary.bumpFee => 'Bump fee',
                TransactionPrimary.accelerate => 'Accelerate (CPFP)',
              },
              loadingLabel: 'Wait',
              onPressed: () async => switch (primary) {
                TransactionPrimary.cancelBid => model.cancelBid(context, tx),
                TransactionPrimary.bumpFee => model.openBumpFee(context, tx),
                TransactionPrimary.accelerate => model.accelerateCpfp(context, tx),
              },
            ),
          ],
          const SizedBox(height: 16),
          SailDetailGroup(
            title: 'Details',
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            children: [
              SailDetailLine(label: 'Date', value: walletDetailDate(time), wrap: true, gap: 16),
              if (addresses.isNotEmpty)
                SailDetailLine(
                  label: net > 0 ? 'Address' : 'To',
                  value: addresses.map(middleEllipsisAddress).join('\n'),
                  wrap: true,
                  gap: 16,
                ),
              SailDetailLine(label: 'TXID', value: walletShortId(tx.txid), wrap: true, gap: 16),
              if (tx.feeSats > 0)
                SailDetailLine(label: 'Fee', value: formatter.formatSats(tx.feeSats.toInt()), wrap: true, gap: 16),
              if (tx.confirmations > 0)
                SailDetailLine(
                  label: 'Block',
                  value: formatWithThousandSpacers(tx.confirmationTime.height),
                  wrap: true,
                  gap: 16,
                ),
            ],
          ),
          if (tx.note.isNotEmpty || tx.addressLabel.isNotEmpty) ...[
            const SizedBox(height: 16),
            SailDetailGroup(
              title: 'Note',
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              children: [
                if (tx.note.isNotEmpty) SailDetailLine(label: 'Note', value: tx.note, wrap: true, gap: 16),
                if (tx.addressLabel.isNotEmpty)
                  SailDetailLine(label: 'Address label', value: tx.addressLabel, wrap: true, gap: 16),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

String middleEllipsisAddress(String address) => middleEllipsis(address, keep: 10);

/// Column keys of the transaction table, in the order the table draws them.
/// The last column holds the row actions and does not sort.
const List<String> transactionColumns = ['date', 'txid', 'address', 'note', 'status', 'amount', ''];

/// Column keys of the desktop transaction table, in the order the table draws them.
const List<String> desktopTransactionColumns = ['title', 'status', 'address', 'date', 'amount'];

/// Width of the action column, so its button never widens the table.
const double bumpFeeColumnWidth = 104;

const _cellPadding = EdgeInsets.symmetric(horizontal: SailStyleValues.padding08);
const _phoneCellPadding = EdgeInsets.symmetric(horizontal: SailStyleValues.padding04);

/// The date of a history row on a phone, on one line.
String phoneHistoryDate(DateTime time) => DateFormat('yyyy-MM-dd HH:mm').format(time);

/// The amount of a history row on a phone, with no unit.
String phoneHistoryAmount(int sats, BitcoinUnit unit) =>
    unit == BitcoinUnit.btc ? formatBitcoin(satoshiToBTC(sats), symbol: '') : formatWithThousandSpacers(sats);

const String _loadingDescription = 'Waiting for enforcer to boot and wallet to sync..';

/// The phone form of the loading transaction table: grey bars in a panel, and what the table waits for.
class OverviewLoadingSkeleton extends StatelessWidget {
  final String description;

  const OverviewLoadingSkeleton({super.key, required this.description});

  static const int barCount = 6;
  static const double barHeight = 24;

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colors.border),
        borderRadius: theme.chrome.radiusLarge,
        color: theme.chrome.panel(theme.colors).color,
      ),
      child: Padding(
        padding: const EdgeInsets.all(SailStyleValues.padding16),
        child: SailColumn(
          spacing: SailStyleValues.padding08,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < barCount; i++)
              Container(
                key: ValueKey('overview_skeleton_bar_$i'),
                height: barHeight,
                decoration: BoxDecoration(color: theme.colors.divider, borderRadius: theme.chrome.radiusSmall),
              ),
            SailText.secondary13(description),
          ],
        ),
      ),
    );
  }
}

/// Only a transaction that waits for a block can carry a replacement. Whether
/// this wallet signs its inputs comes from the backend preview, because a
/// self-send and a consolidation both read as amount zero here.
bool canBumpFee(WalletTransaction tx) => tx.confirmations == 0 && !tx.abandoned && !canCancelBid(tx);

/// A lost bid names a mainchain block the chain already built past, so no miner
/// can take it. A replacement is the only way back to the coins.
bool canCancelBid(WalletTransaction tx) => tx.hasBmmBid() && tx.bmmBid.lost && !tx.abandoned;

/// An unconfirmed payment to this wallet can pay for its own confirmation with a child.
bool canAccelerate(WalletTransaction tx) =>
    tx.confirmations == 0 && !tx.abandoned && tx.receivedSatoshi > tx.sentSatoshi;

/// What the status cell of an abandoned transaction tells on hover.
const String abandonedHint = 'The chain dropped this transaction. It does not count in your balance.';

/// Confirmations a coinbase output needs before it can be spent.
const int coinbaseMaturity = 100;

/// What the status column says about one transaction.
String transactionStatus(WalletTransaction tx) {
  if (tx.abandoned) {
    return 'Abandoned';
  }
  if (tx.hasBmmBid()) {
    return tx.bmmBid.lost ? 'BMM bid \u00b7 lost' : 'BMM bid \u00b7 slot ${tx.bmmBid.slot}';
  }
  if (tx.hasDepositRequest()) {
    final state = tx.confirmations == 0 ? 'unconfirmed' : 'confirmed';
    return 'Deposit \u00b7 slot ${tx.depositRequest.slot} \u00b7 $state';
  }
  if (tx.immature) {
    return 'Maturing (${tx.confirmations}/$coinbaseMaturity)';
  }
  return tx.confirmations == 0 ? 'Unconfirmed' : 'Confirmed';
}

/// [net] sats with its sign, as the history shows an amount.
String signedAmount(int net, String Function(int sats) format) => '${net > 0 ? '+' : '-'}${format(net.abs())}';

/// What [tx] did to this wallet, as label and value rows.
List<(String, String)> walletTransactionRows(WalletTransaction tx, FormatterProvider formatter) {
  final addresses = transactionAddresses(tx);
  return [
    ('Date', formatDate(tx.confirmationTime.timestamp.toDateTime().toLocal())),
    ('Status', transactionStatus(tx)),
    ('Amount', signedAmount(walletNetSats(tx), formatter.formatSats)),
    if (addresses.isNotEmpty) (addresses.length == 1 ? 'Address' : 'Addresses', addresses.join('\n')),
    if (tx.note.isNotEmpty) ('Note', tx.note),
  ];
}

/// The history as CSV, one row per transaction.
String transactionsCsv(List<WalletTransaction> transactions) {
  final headers = [
    'Date',
    'TXID',
    'Type',
    'Address',
    'Label',
    'Amount (BTC)',
    'Amount (sats)',
    'Fee (sats)',
    'Note',
    'Block Height',
  ];

  final rows = <List<String>>[headers];

  for (final tx in transactions) {
    final netAmount = walletNetSats(tx);
    final type = tx.abandoned
        ? 'Abandoned'
        : netAmount > 0
        ? 'Received'
        : 'Sent';
    final amountBTC = (netAmount / 100000000).toStringAsFixed(8);
    final date = DateFormat('yyyy-MM-dd HH:mm:ss').format(tx.confirmationTime.timestamp.toDateTime().toLocal());

    rows.add([
      date,
      tx.txid,
      type,
      transactionAddresses(tx).join('; '),
      tx.addressLabel,
      amountBTC,
      netAmount.toString(),
      tx.feeSats.toString(),
      tx.note,
      tx.confirmations == 0 ? '' : tx.confirmationTime.height.toString(),
    ]);
  }

  return encodeCsv(rows);
}

/// What the history says when it shows no row.
String historyEmptyText({required bool filtered}) => filtered ? 'No transactions match' : 'No transactions yet';

/// The address cell of a history row: a short address, the label where it has
/// one, and the count of the other addresses.
String historyAddressText(WalletTransaction tx) {
  final address = middleEllipsis(tx.address, keep: 10);
  final labelled = tx.addressLabel.isEmpty ? address : '$address (${tx.addressLabel})';
  final others = tx.payments.map((payment) => payment.address).toSet().length - 1;
  return others > 0 ? '$labelled +$others' : labelled;
}

/// [rows] with the address book label of each address. A row the book holds no label for keeps its own.
List<WalletTransaction> withBookLabels(List<WalletTransaction> rows, Map<String, String> labels) => [
  for (final tx in rows)
    switch (labels[tx.address]) {
      final label? when label != tx.addressLabel => tx.deepCopy()..addressLabel = label,
      _ => tx,
    },
];

class TransactionTable extends StatefulWidget {
  final Widget searchWidget;
  final OverviewViewModel model;

  /// The row the side panel shows. Desktop only.
  final String? selectedTxid;
  final ValueChanged<String>? onRowTap;

  const TransactionTable({
    super.key,
    required this.model,
    required this.searchWidget,
    this.selectedTxid,
    this.onRowTap,
  });

  @override
  State<TransactionTable> createState() => _TransactionTableState();
}

class _TransactionTableState extends State<TransactionTable> {
  String sortColumn = 'date';
  bool sortAscending = false;

  List<WalletTransaction> get sortedEntries {
    final entries = List<WalletTransaction>.from(widget.model.entries);
    entries.sort((a, b) {
      dynamic aValue, bValue;
      switch (sortColumn) {
        case 'date':
          return sortAscending ? newestTransactionFirst(b, a) : newestTransactionFirst(a, b);
        case 'txid':
          aValue = a.txid;
          bValue = b.txid;
          break;
        case 'address':
          aValue = a.address;
          bValue = b.address;
          break;
        case 'note':
          aValue = a.note;
          bValue = b.note;
          break;
        case 'title':
          aValue = transactionTitle(a);
          bValue = transactionTitle(b);
          break;
        case 'status':
          aValue = a.confirmations;
          bValue = b.confirmations;
          break;
        case 'amount':
          aValue = walletNetSats(a).abs();
          bValue = walletNetSats(b).abs();
          break;
        default:
          aValue = a.confirmationTime.timestamp.seconds;
          bValue = b.confirmationTime.timestamp.seconds;
      }
      aValue ??= '';
      bValue ??= '';
      return sortAscending ? aValue.compareTo(bValue) : bValue.compareTo(aValue);
    });
    return entries;
  }

  void onSort(String column) {
    setState(() {
      if (sortColumn == column) {
        sortAscending = !sortAscending;
      } else {
        sortColumn = column;
        sortAscending = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!SailStyleValues.phoneLayout(context)) {
      final theme = SailTheme.of(context);
      final model = widget.model;
      final entries = sortedEntries;
      return WalletTableCard(
        title: 'Transactions',
        error: model.historyError,
        toolbar: [
          widget.searchWidget,
          WalletDateRangeButton(range: model.dateRange, onChanged: model.setDateRange),
          SailButton(
            label: 'Export CSV',
            variant: ButtonVariant.ghost,
            small: true,
            onPressed: () async {
              await model.exportTransactionsToCSV(context, entries);
            },
          ),
        ],
        child: SailSkeletonizer(
          description: _loadingDescription,
          enabled: model.loading,
          child: SailTable(
            getRowId: (index) => entries[index].txid,
            selectedRowId: widget.selectedTxid,
            onRowTap: widget.onRowTap,
            cellHeight: 52,
            headerBuilder: (context) => [
              SailTableHeaderCell(name: 'Transaction', padding: _cellPadding, onSort: () => onSort('title')),
              SailTableHeaderCell(name: 'Status', padding: _cellPadding, onSort: () => onSort('status')),
              SailTableHeaderCell(name: 'Address', padding: _cellPadding, onSort: () => onSort('address')),
              SailTableHeaderCell(name: 'Date', padding: _cellPadding, onSort: () => onSort('date')),
              SailTableHeaderCell(
                name: 'Amount',
                padding: _cellPadding,
                alignment: Alignment.centerRight,
                onSort: () => onSort('amount'),
              ),
            ],
            rowBuilder: (context, row, selected) {
              final entry = entries[row];
              final muted = entry.abandoned ? theme.colors.textSecondary : null;
              final net = walletNetSats(entry);
              final time = entry.confirmationTime.timestamp.toDateTime().toLocal();
              final status = transactionStatus(entry);
              final detail = transactionStatusDetail(entry);
              final statusCell = WalletStatusCell(
                tone: transactionTone(entry),
                status: status,
                detail: detail,
                color: muted,
                marks: [
                  if (entry.warningMessage.trim().isNotEmpty)
                    SailTooltip(
                      message: entry.warningMessage,
                      maxWidth: 320,
                      child: Semantics(
                        label: entry.warningMessage,
                        child: SailSVG.icon(SailSVGAsset.triangleAlert, width: 14, color: theme.colors.orange),
                      ),
                    ),
                  if (entry.immature) SailSVG.icon(SailSVGAsset.hourglass, width: 14, color: theme.colors.orange),
                ],
              );
              return [
                SailTableCell(
                  value: transactionTitle(entry),
                  secondaryValue: walletShortId(entry.txid),
                  copyValue: entry.txid,
                  textColor: muted,
                  padding: _cellPadding,
                ),
                SailTableCell(
                  value: '$status  ',
                  padding: _cellPadding,
                  child: entry.abandoned
                      ? SailTooltip(message: abandonedHint, maxWidth: 320, child: statusCell)
                      : statusCell,
                ),
                SailTableCell(
                  value: historyAddressText(entry),
                  padding: _cellPadding,
                  copyValue: transactionAddresses(entry).join('\n'),
                  textColor: muted,
                ),
                SailTableCell(
                  value: walletRowDate(time),
                  secondaryValue: walletRowTime(time),
                  padding: _cellPadding,
                  textColor: muted,
                ),
                SailTableCell(
                  value: '${net > 0 ? '+' : '-'}${walletAmountText(net.abs())}',
                  secondaryValue: walletUnitText(),
                  alignment: Alignment.centerRight,
                  textColor: muted ?? (net > 0 ? theme.colors.success : null),
                  padding: _cellPadding,
                ),
              ];
            },
            contextMenuItems: (rowId) {
              final entry = entries.firstWhere((e) => e.txid == rowId);
              return transactionMenuItems(context, model, entry);
            },
            rowCount: entries.length,
            emptyPlaceholder: historyEmptyText(filtered: model.filtered),
            sortColumnIndex: desktopTransactionColumns.indexOf(sortColumn),
            sortAscending: sortAscending,
            onSort: (columnIndex, ascending) => onSort(desktopTransactionColumns[columnIndex]),
          ),
        ),
      );
    }
    final formatter = GetIt.I<FormatterProvider>();
    final entries = sortedEntries;
    final phone = SailStyleValues.phoneLayout(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return SailCard(
          title: 'Wallet Transaction History',
          error: widget.model.historyError,
          titleTooltip: 'This transaction list contains all your wallet transactions. Sends, receives, and sidechain-interaction transactions.',
          bottomPadding: false,
          widgetHeaderEnd: SailButton(
            label: 'Export CSV',
            variant: ButtonVariant.secondary,
            small: true,
            icon: SailSVGAsset.iconDownload,
            onPressed: () async {
              await widget.model.exportTransactionsToCSV(context, entries);
            },
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: SailStyleValues.padding16,
                ),
                child: widget.searchWidget,
              ),
              SizedBox(
                height: 300,
                child: phone && widget.model.loading
                    ? const Align(
                        alignment: Alignment.topCenter,
                        child: OverviewLoadingSkeleton(description: _loadingDescription),
                      )
                    : SailSkeletonizer(
                        description: _loadingDescription,
                        enabled: widget.model.loading,
                        child: ListenableBuilder(
                          listenable: formatter,
                          builder: (context, child) => SailTable(
                            getRowId: (index) => entries[index].txid,
                            phoneColumns: const [0, 4, 5],
                            headerBuilder: (context) => [
                              SailTableHeaderCell(
                                name: 'Date',
                                padding: phone ? _phoneCellPadding : _cellPadding,
                                onSort: () => onSort('date'),
                                filterWidget: SailTooltip(
                                  message: 'Filter by date range',
                                  child: DateFilter(
                                    range: widget.model.dateRange,
                                    onChanged: widget.model.setDateRange,
                                  ),
                                ),
                              ),
                              SailTableHeaderCell(
                                name: 'TXID',
                                padding: _cellPadding,
                                onSort: () => onSort('txid'),
                              ),
                              SailTableHeaderCell(
                                name: 'Address',
                                padding: _cellPadding,
                                onSort: () => onSort('address'),
                              ),
                              SailTableHeaderCell(
                                name: 'Note',
                                padding: _cellPadding,
                                onSort: () => onSort('note'),
                              ),
                              SailTableHeaderCell(
                                name: 'Status',
                                padding: phone ? _phoneCellPadding : _cellPadding,
                                onSort: () => onSort('status'),
                              ),
                              SailTableHeaderCell(
                                name: 'Amount',
                                padding: phone ? _phoneCellPadding : _cellPadding,
                                onSort: () => onSort('amount'),
                              ),
                              const SailTableHeaderCell(
                                name: '',
                                alignment: Alignment.centerRight,
                              ),
                            ],
                            rowBuilder: (context, row, selected) {
                              final entry = entries[row];
                              final unconfirmed = entry.confirmations == 0;
                              final mutedColor = entry.abandoned ? context.sailTheme.colors.textSecondary : null;
                              final statusColor =
                                  mutedColor ??
                                  (unconfirmed || entry.immature ? context.sailTheme.colors.orange : null);
                              final replaceable = canBumpFee(entry);
                              final cancellable = canCancelBid(entry);

                              final net = walletNetSats(entry);
                              final formattedAmount = phone
                                  ? signedAmount(net, (sats) => phoneHistoryAmount(sats, formatter.currentUnit))
                                  : signedAmount(net, formatter.formatSats);
                              final time = entry.confirmationTime.timestamp.toDateTime().toLocal();

                              return [
                                SailTableCell(
                                  value: phone ? phoneHistoryDate(time) : formatDate(time),
                                  hugContent: phone,
                                  padding: phone ? _phoneCellPadding : _cellPadding,
                                ),
                                SailTableCell(
                                  value: '${entry.txid.substring(0, 10)}..',
                                  padding: _cellPadding,
                                  copyValue: entry.txid,
                                ),
                                SailTableCell(
                                  value: historyAddressText(entry),
                                  padding: _cellPadding,
                                  copyValue: transactionAddresses(entry).join('\n'),
                                ),
                                SailTableCell(
                                  value: entry.note,
                                  padding: _cellPadding,
                                ),
                                SailTableCell(
                                  value: transactionStatus(entry),
                                  textColor: statusColor,
                                  fill: phone,
                                  padding: phone ? _phoneCellPadding : _cellPadding,
                                  child: entry.abandoned
                                      ? SailTooltip(
                                          message: abandonedHint,
                                          maxWidth: 320,
                                          child: SailText.primary13(
                                            transactionStatus(entry),
                                            color: statusColor,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        )
                                      : entry.warningMessage.trim().isEmpty && !entry.immature
                                      ? (phone
                                            ? SailText.primary13(
                                                transactionStatus(entry),
                                                color: statusColor,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              )
                                            : null)
                                      : Row(
                                          children: [
                                            if (entry.warningMessage.trim().isNotEmpty) ...[
                                              SailTooltip(
                                                message: entry.warningMessage,
                                                maxWidth: 320,
                                                child: Semantics(
                                                  label: entry.warningMessage,
                                                  child: SailSVG.icon(
                                                    SailSVGAsset.triangleAlert,
                                                    width: 14,
                                                    color: context.sailTheme.colors.orange,
                                                  ),
                                                ),
                                              ),
                                              const SailSpacing(SailStyleValues.padding04),
                                            ],
                                            if (entry.immature) ...[
                                              SailSVG.icon(
                                                SailSVGAsset.hourglass,
                                                width: 14,
                                                color: context.sailTheme.colors.orange,
                                              ),
                                              const SailSpacing(SailStyleValues.padding08),
                                            ],
                                            Flexible(
                                              child: SailText.primary13(
                                                transactionStatus(entry),
                                                color: statusColor,
                                                maxLines: phone ? 1 : null,
                                                overflow: phone ? TextOverflow.ellipsis : null,
                                              ),
                                            ),
                                          ],
                                        ),
                                ),
                                SailTableCell(
                                  value: formattedAmount,
                                  textColor: mutedColor,
                                  monospace: !phone,
                                  hugContent: phone,
                                  padding: phone ? _phoneCellPadding : _cellPadding,
                                ),
                                SailTableCell(
                                  value: cancellable
                                      ? 'Cancel bid'
                                      : replaceable
                                      ? 'Bump fee'
                                      : '',
                                  width: bumpFeeColumnWidth,
                                  padding: _cellPadding,
                                  alignment: Alignment.centerRight,
                                  child: cancellable
                                      ? SailButton(
                                          label: 'Cancel bid',
                                          loadingLabel: 'Wait',
                                          onPressed: () async => widget.model.cancelBid(context, entry),
                                          insideTable: true,
                                        )
                                      : replaceable
                                      ? SailButton(
                                          label: 'Bump fee',
                                          loadingLabel: 'Wait',
                                          onPressed: () async => widget.model.openBumpFee(context, entry),
                                          insideTable: true,
                                        )
                                      : const SizedBox.shrink(),
                                ),
                              ];
                            },
                            contextMenuItems: (rowId) {
                              final entry = entries.firstWhere((e) => e.txid == rowId);
                              return transactionMenuItems(context, widget.model, entry);
                            },
                            rowCount: entries.length,
                            emptyPlaceholder: historyEmptyText(filtered: widget.model.filtered),
                            drawGrid: !phone,
                            resizableColumns: !phone,
                            sortColumnIndex: transactionColumns.indexOf(sortColumn),
                            sortAscending: sortAscending,
                            onSort: (columnIndex, ascending) {
                              final column = transactionColumns[columnIndex];
                              if (column.isEmpty) {
                                return;
                              }
                              onSort(column);
                            },
                            onDoubleTap: (rowId) => showTransactionDetails(context, rowId),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Orchestrator migration status:
/// - Balance: routed via BalanceProvider (now on orchestrator)
/// - Transactions: routed via TransactionProvider (already on orchestrator)
/// - getStats: STAYS on bitwindowd — BW-only aggregate stats from SQLite
/// - bumpFee: routed via orchestrator
/// - saveNote: STAYS on bitwindowd — transaction notes live in BW SQLite
class OverviewViewModel extends BaseViewModel with ChangeTrackingMixin {
  final TransactionProvider _txProvider = GetIt.I<TransactionProvider>();
  final BitwindowRPC _bitwindowRPC = GetIt.I<BitwindowRPC>();
  final OrchestratorWalletRPC _orchestratorWallet = GetIt.I<OrchestratorRPC>().wallet;
  final OrchestratorBmmRPC _orchestratorBmm = GetIt.I<OrchestratorRPC>().bmm;
  final EnforcerRPC _enforcerRPC = GetIt.I<EnforcerRPC>();
  final BalanceProvider _balanceProvider = GetIt.I<BalanceProvider>();
  final AddressBookProvider _addressBook = GetIt.I<AddressBookProvider>();
  WalletReaderProvider get _walletReader => GetIt.I<WalletReaderProvider>();

  ({DateTime start, DateTime end})? dateRange;

  List<WalletTransaction> get entries {
    if (loading) {
      return [
        WalletTransaction(
          txid: 'dummy_tx_1',
          feeSats: Int64(1000),
          receivedSatoshi: Int64(50000000), // 0.5 BTC
          sentSatoshi: Int64(0),
          address: 'bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh',
          addressLabel: 'Main Wallet',
          note: 'Received payment',
          confirmations: 1,
          confirmationTime: Confirmation(
            height: 800000,
            timestamp: Timestamp.fromDateTime(DateTime(2024)),
          ),
        ),
        WalletTransaction(
          txid: 'dummy_tx_2',
          feeSats: Int64(2000),
          receivedSatoshi: Int64(0),
          sentSatoshi: Int64(100000000), // 1 BTC
          address: 'bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh',
          addressLabel: 'Exchange',
          note: 'Sent to exchange',
          confirmations: 1,
          confirmationTime: Confirmation(
            height: 800001,
            timestamp: Timestamp.fromDateTime(DateTime(2024)),
          ),
        ),
        WalletTransaction(
          txid: 'dummy_tx_3',
          feeSats: Int64(1500),
          receivedSatoshi: Int64(25000000), // 0.25 BTC
          sentSatoshi: Int64(0),
          address: 'bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh',
          addressLabel: 'Mining Pool',
          note: 'Mining reward',
          confirmations: 1,
          confirmationTime: Confirmation(
            height: 800002,
            timestamp: Timestamp.fromDateTime(DateTime(2024)),
          ),
        ),
      ];
    }

    final labels = labelsByAddress([..._addressBook.receiveEntries, ..._addressBook.sendEntries]);
    return withBookLabels(_txProvider.walletTransactions, labels).where((tx) {
      if (!transactionMatchesSearch(tx, searchController.text)) {
        return false;
      }

      if (dateRange != null && !isInDateRange(tx.confirmationTime.timestamp.toDateTime(), dateRange!)) {
        return false;
      }

      return true;
    }).toList();
  }

  /// A search or a date range hides rows.
  bool get filtered => normalizeSearchText(searchController.text).isNotEmpty || dateRange != null;

  String sortColumn = 'date';
  bool sortAscending = true;
  GetStatsResponse? stats;

  @override
  String? modelError;
  String? transactionsError;

  /// The last stats read failed, so the tiles show no numbers.
  String? statsError;

  /// Why the overview could not read the wallet, or null.
  String? get readError {
    final error = _txProvider.error ?? statsError;
    return error == null ? null : 'Could not read the wallet: $error';
  }

  /// The error line of the history card.
  String? get historyError => transactionsError ?? readError;

  final TextEditingController searchController = TextEditingController();

  bool get loading => _enforcerRPC.initializingBinary;

  Timer? _refreshTimer;
  String? _statsWalletId;
  int _statsRead = 0;

  OverviewViewModel() {
    initChangeTracker();
    searchController.addListener(_onChange);
    _txProvider.addListener(_onChange);
    _txProvider.addListener(_debouncedGetStats);
    _balanceProvider.addListener(_onChange);
    _balanceProvider.addListener(_debouncedGetStats);
    _enforcerRPC.addListener(_onChange);
    _addressBook.addListener(_onChange);
    _statsWalletId = _walletReader.activeWalletId;
    _walletReader.addListener(_onWalletChanged);
    getStats();
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) => getStats());
  }

  void _onChange() {
    track('entries', entries);
    track('searchText', searchController.text);
    track('dateRange', dateRange);
    track('loading', loading);
    track('stats', stats);
    track('readError', readError);
    notifyIfChanged();
  }

  void setDateRange(({DateTime start, DateTime end})? range) {
    dateRange = range;
    notifyListeners();
  }

  // Debounce stats fetching
  Timer? _statsTimer;
  void _debouncedGetStats() {
    _statsTimer?.cancel();
    _statsTimer = Timer(const Duration(milliseconds: 100), () {
      getStats();
    });
  }

  void _onWalletChanged() {
    final walletId = _walletReader.activeWalletId;
    if (_statsWalletId == walletId) {
      return;
    }
    _statsWalletId = walletId;
    stats = null;
    statsError = null;
    track('stats', stats);
    notifyListeners();
    unawaited(getStats());
  }

  Future<void> getStats() async {
    final read = ++_statsRead;
    final walletId = _walletReader.activeWalletId;
    if (walletId == null) {
      return;
    }

    try {
      final newStats = await _bitwindowRPC.wallet.getStats(walletId);
      if (read != _statsRead) {
        return;
      }
      final errorChanged = statsError != null;
      statsError = null;
      if (track('stats', newStats) || errorChanged) {
        stats = newStats;
        notifyListeners();
      }
    } catch (e) {
      if (read != _statsRead) {
        return;
      }
      if (statsError != e.toString()) {
        statsError = e.toString();
        notifyListeners();
      }
    }
  }

  Future<void> saveNote(BuildContext context, String txid, String note) async {
    try {
      setBusy(true);
      await _txProvider.saveNote(txid, note);

      if (context.mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (error.toString() != modelError) {
        modelError = error.toString();
        notifyListeners();
      }
    } finally {
      setBusy(false);
    }
  }

  Future<void> exportTransactionsToCSV(BuildContext context, List<WalletTransaction> transactions) async {
    transactionsError = null;
    try {
      setBusy(true);

      if (transactions.isEmpty) {
        if (context.mounted) {
          showSailToast(context, 'No transactions to export');
        }
        return;
      }

      final defaultFileName = 'bitwindow-transactions-${DateFormat('yyyy-MM-dd').format(DateTime.now())}.csv';

      final csvData = transactionsCsv(transactions);

      final result = await FilePicker.saveFile(
        dialogTitle: 'Export Transactions to CSV',
        fileName: defaultFileName,
        bytes: Uint8List.fromList(utf8.encode(csvData)),
      );

      if (result == null) {
        return;
      }

      if (context.mounted) {
        showSailToast(context, 'Transactions exported successfully to ${result.toFilePath()}');
      }
    } catch (error) {
      transactionsError = 'Export failed: $error';
      notifyListeners();
    } finally {
      setBusy(false);
    }
  }

  /// Opens the fee bump. A transaction with no change output has no
  /// replacement to build, so the dialog offers CPFP and hands it back here.
  Future<void> openBumpFee(BuildContext context, WalletTransaction tx) async {
    final outcome = await showThemedDialog<BumpFeeOutcome>(
      context: context,
      builder: (context) => BumpFeeDialog(txid: tx.txid),
    );
    if (outcome == BumpFeeOutcome.accelerate && context.mounted) {
      await accelerateCpfp(context, tx);
    }
  }

  /// Replaces a lost bid with a payment back to this wallet.
  Future<void> cancelBid(BuildContext context, WalletTransaction tx) async {
    final log = GetIt.I<Logger>();
    transactionsError = null;
    notifyListeners();
    try {
      final result = await _orchestratorBmm.cancelBid(
        txid: tx.txid,
        walletId: _walletReader.activeWalletId,
      );
      log.i('cancelled bid ${tx.txid} with ${result.replacementTxid}');
      if (context.mounted) {
        showSailToast(
          context,
          'Cancelled. ${result.recoveredSats} sats come back in ${result.replacementTxid}',
          variant: SailToastVariant.success,
        );
      }
      // The network holds the replacement already. A refresh that fails changes
      // nothing about that.
      unawaited(_txProvider.fetch());
    } catch (e) {
      log.e('failed to cancel bid ${tx.txid}: $e');
      transactionsError = 'Failed to cancel the bid: $e';
      notifyListeners();
    }
  }

  Future<void> accelerateCpfp(BuildContext context, WalletTransaction tx) async {
    await showThemedDialog(
      context: context,
      builder: (context) => SailModal(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SailCardEditValues(
          title: 'Accelerate (CPFP)',
          subtitle: 'Spend this unconfirmed output with a child tx so the package reaches your target fee rate.',
          fields: [
            EditField(name: 'Target fee rate (${activeTicker.feeRate})', currentValue: ''),
          ],
          saveLabel: 'Accelerate',
          onSave: (updatedFields) async {
            final raw = updatedFields
                .firstWhere((f) => f.name == 'Target fee rate (${activeTicker.feeRate})')
                .currentValue;
            return _createCpfp(context, tx, raw);
          },
        ),
      ),
    );
  }

  /// Returns the error to show in the dialog, or null on success.
  Future<String?> _createCpfp(BuildContext context, WalletTransaction tx, String rawRate) async {
    final log = GetIt.I<Logger>();

    try {
      final targetRate = int.tryParse(rawRate.trim());
      if (targetRate == null || targetRate <= 0) {
        throw Exception('Enter a positive fee rate in ${activeTicker.feeRate}');
      }

      final walletId = _walletReader.activeWalletId;
      if (walletId == null) {
        throw Exception('No active wallet');
      }

      final unspent = await _orchestratorWallet.listUnspent(walletId);
      final parent = unspent.utxos.firstWhereOrNull(
        (u) => u.txid == tx.txid && u.confirmations == 0,
      );
      if (parent == null) {
        throw Exception('No spendable unconfirmed output found for this transaction');
      }

      final result = await _orchestratorWallet.createCpfp(
        walletId: walletId,
        parentTxid: parent.txid,
        parentVout: parent.vout,
        targetFeeRate: targetRate,
      );

      log.i('CPFP child broadcast: ${result.childTxid} (parent ${tx.txid})');
      if (context.mounted) {
        showSailToast(context, 'Accelerated! Child txid: ${result.childTxid}');
        Navigator.of(context).pop();
      }
      // The network holds the child already. A refresh that fails changes
      // nothing about that.
      unawaited(_txProvider.fetch());
      return null;
    } catch (e) {
      log.e('Failed to accelerate (CPFP): $e');
      if (isExpectedBootError(e)) {
        return 'Could not accelerate the transaction. Check Daemon Status, then try again.';
      }
      return 'Failed to accelerate: $e';
    }
  }

  @override
  void dispose() {
    _statsRead++;
    _statsTimer?.cancel();
    _refreshTimer?.cancel();
    searchController.removeListener(_onChange);
    _txProvider.removeListener(_onChange);
    _txProvider.removeListener(_debouncedGetStats);
    _balanceProvider.removeListener(_onChange);
    _balanceProvider.removeListener(_debouncedGetStats);
    _enforcerRPC.removeListener(_onChange);
    _addressBook.removeListener(_onChange);
    _walletReader.removeListener(_onWalletChanged);
    super.dispose();
  }
}

class WalletStats extends ViewModelWidget<OverviewViewModel> {
  final String title;
  final String subtitle;
  final String value;
  final SailSVGAsset icon;
  final bool bitcoinAmount;

  /// A shorter title for the phone row, where the title shares its line with the value.
  final String? phoneTitle;

  const WalletStats({
    super.key,
    required this.title,
    this.phoneTitle,
    required this.subtitle,
    required this.value,
    required this.icon,
    this.bitcoinAmount = false,
  });

  @override
  Widget build(BuildContext context, OverviewViewModel viewModel) {
    final loading = LoadingDetails(
      enabled: viewModel.loading,
      description: 'Waiting for enforcer to boot and wallet to sync..',
    );
    // A failed read must not leave the last numbers up as if they were new.
    final failed = viewModel.statsError != null;
    final value = failed ? '-' : this.value;
    final subtitle = failed ? '' : this.subtitle;
    if (SailStyleValues.phoneLayout(context)) {
      return SailStatRow(title: phoneTitle ?? title, subtitle: subtitle, value: value, loading: loading);
    }
    return SailCardStats(
      title: title,
      subtitle: subtitle,
      value: value,
      icon: icon,
      loading: loading,
    );
  }
}

/// The wallet stats: one row of cards on the desktop, one list panel on a phone.
class _StatsGrid extends StatelessWidget {
  final bool phone;
  final List<Widget> stats;

  const _StatsGrid({required this.phone, required this.stats});

  @override
  Widget build(BuildContext context) {
    if (phone) {
      return SailStatList(children: stats);
    }
    return SailRow(
      mainAxisSize: MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.start,
      spacing: 16,
      children: [for (final stat in stats) Expanded(child: stat)],
    );
  }
}
