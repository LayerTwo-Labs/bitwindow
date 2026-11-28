import 'dart:async';

import 'package:bitwindow/pages/explorer/block_explorer_dialog.dart';
import 'package:bitwindow/pages/wallet/denial_dialog.dart';
import 'package:bitwindow/providers/transactions_provider.dart';
import 'package:bitwindow/widgets/v2_details.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:sidechain_core/gen/wallet/v1/wallet.pb.dart';
import 'package:sail_ui/sail_ui.dart' hide DetailRow;

/// True when the denial schedule still has a future execution to run. The
/// proto sets `nextExecutionTime` to the epoch-zero default when the schedule
/// is exhausted, so we treat that as "no scheduled next execution" rather
/// than rendering it as a 1969 timestamp.
bool denialHasScheduledNextExecution(DenialInfo info) {
  if (!info.hasNextExecutionTime()) {
    return false;
  }
  return info.nextExecutionTime.toDateTime().millisecondsSinceEpoch != 0;
}

enum DenialStatus {
  none('-'),
  ongoing('Ongoing'),
  paused('Paused'),
  completed('Completed'),
  cancelled('Cancelled');

  const DenialStatus(this.label);

  final String label;
}

/// The state of the denial of a UTXO. Each screen reads the state here.
DenialStatus denialStatus(UnspentOutput utxo) {
  if (!utxo.hasDenialInfo()) {
    return DenialStatus.none;
  }
  final info = utxo.denialInfo;
  // A later pause or cancel of the plan does not apply to the change of a hop.
  if (info.isChange) {
    return DenialStatus.completed;
  }
  if (info.hasCancelTime()) {
    return DenialStatus.cancelled;
  }
  if (info.hasPausedAt()) {
    return DenialStatus.paused;
  }
  return denialHasScheduledNextExecution(info) ? DenialStatus.ongoing : DenialStatus.completed;
}

/// The denial state of a UTXO with its hops, such as "Paused (1/3)".
String denialStatusWithHops(UnspentOutput utxo) {
  final hops = utxo.denialInfo.hopsCompleted;
  final totalHops = utxo.denialInfo.numHops;

  return switch (denialStatus(utxo)) {
    DenialStatus.none => '-',
    DenialStatus.completed => 'Done ($hops)',
    DenialStatus.cancelled => 'Cancelled ($hops)',
    DenialStatus.paused => 'Paused ($hops/$totalHops)',
    DenialStatus.ongoing => 'Active ($hops/$totalHops)',
  };
}

/// True when the user can pause, resume or cancel the denial from this UTXO.
bool denialCanControl(UnspentOutput utxo) {
  final status = denialStatus(utxo);
  return !utxo.denialInfo.isChange && (status == DenialStatus.ongoing || status == DenialStatus.paused);
}

/// Hops of a UTXO as done/total, or '0' when the UTXO has no denial.
String denialHopsLabel(UnspentOutput utxo) {
  if (!utxo.hasDenialInfo()) {
    return '0';
  }
  return '${utxo.denialInfo.hopsCompleted}/${utxo.denialInfo.numHops}';
}

/// Time until the next hop, such as "in 2 hours", or '-' when no hop is scheduled.
String denialNextExecutionLabel(DenialInfo info, DateTime now) {
  if (!denialHasScheduledNextExecution(info)) {
    return '-';
  }
  final seconds = info.nextExecutionTime.toDateTime().difference(now).inSeconds;
  if (seconds <= 0) {
    return 'now';
  }
  final minutes = (seconds + 59) ~/ 60;
  if (minutes < 60) {
    return 'in $minutes min';
  }
  final hours = minutes ~/ 60;
  if (hours < 48) {
    return 'in $hours ${hours == 1 ? 'hour' : 'hours'}';
  }
  return 'in ${hours ~/ 24} days';
}

class DeniabilityTab extends StatelessWidget {
  final SailWindow? newWindowButton;

  const DeniabilityTab({super.key, required this.newWindowButton});

  /// Narrower pages show the UTXO details in a dialog, not in the side panel.
  static const double panelMinWidth = 900;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return ViewModelBuilder<DeniabilityViewModel>.reactive(
          viewModelBuilder: () => DeniabilityViewModel(),
          onViewModelReady: (model) => WidgetsBinding.instance.addPostFrameCallback((_) => model.postInit()),
          builder: (context, model, child) {
            final error = model.actionError ?? model.error('deniability');
            final phone = SailStyleValues.phoneLayout(context);
            final withPanel = !phone && constraints.maxWidth >= panelMinWidth;
            final selected = withPanel ? model.selectedUtxo : null;

            return SailColumn(
              spacing: SailStyleValues.padding12,
              children: [
                if (!phone)
                  DenyAllButton(
                    onPressed: () => model.showDenyAllDialog(context),
                    utxoCount: model.utxosWithoutDenial.length,
                  ),
                Expanded(
                  child: SailPageWithPanel(
                    panel: selected == null
                        ? null
                        : DenialUtxoPanel(
                            utxo: selected,
                            onClose: () async => model.selectUtxo(null),
                            onDeny: (output, valueSats) => model.showDenyDialog(context, output, valueSats),
                            onCancel: model.cancelDenial,
                            onPause: model.pauseDenial,
                            onResume: model.resumeDenial,
                          ),
                    child: DeniabilityTable(
                      newWindowButton: newWindowButton,
                      error: error,
                      utxos: model.utxos,
                      model: model,
                      onDenyAll: phone ? () => model.showDenyAllDialog(context) : null,
                      denyAllCount: model.utxosWithoutDenial.length,
                      onDeny: (output, valueSats) => model.showDenyDialog(context, output, valueSats),
                      onCancel: model.cancelDenial,
                      onPause: model.pauseDenial,
                      onResume: model.resumeDenial,
                      selectedOutput: selected?.output,
                      onSelect: withPanel ? model.selectUtxo : null,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// The top strip with the one Deny All button.
class DenyAllButton extends StatelessWidget {
  final VoidCallback onPressed;
  final int utxoCount;

  const DenyAllButton({super.key, required this.onPressed, required this.utxoCount});

  @override
  Widget build(BuildContext context) {
    return SailStrip(
      stats: [
        SailText.primary13(
          utxoCount > 0
              ? 'Click here to start deniability on all $utxoCount UTXOs'
              : 'All UTXOs already have active deniability',
          bold: true,
        ),
      ],
      actions: [
        SailButton(
          label: 'Deny All',
          disabled: utxoCount == 0,
          onPressed: () async => onPressed(),
        ),
      ],
    );
  }
}

class DeniabilityTable extends StatefulWidget {
  final SailWindow? newWindowButton;
  final String? error;
  final List<UnspentOutput> utxos;
  final void Function(String output, int valueSats) onDeny;
  final void Function(Int64) onCancel;
  final void Function(Int64) onPause;
  final void Function(Int64) onResume;
  final DeniabilityViewModel model;

  /// Shows a small Deny All button in the card head. The phone layout uses it in place of [DenyAllButton].
  final VoidCallback? onDenyAll;
  final int denyAllCount;

  /// The output of the UTXO in the side panel.
  final String? selectedOutput;

  /// Opens a UTXO in the side panel, or closes it with null. Null opens the details in a dialog.
  final ValueChanged<UnspentOutput?>? onSelect;

  const DeniabilityTable({
    super.key,
    required this.error,
    required this.utxos,
    required this.model,
    required this.onDeny,
    required this.onCancel,
    required this.onPause,
    required this.onResume,
    required this.newWindowButton,
    this.onDenyAll,
    this.denyAllCount = 0,
    this.selectedOutput,
    this.onSelect,
  });

  @override
  State<DeniabilityTable> createState() => _DeniabilityTableState();
}

class _DeniabilityTableState extends State<DeniabilityTable> {
  static const _sortColumns = ['txid', 'id', 'status', 'hops', 'next', 'timestamp', 'amount'];

  String sortColumn = 'txid';
  bool sortAscending = true;
  late final Timer _clock;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 30), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _clock.cancel();
    super.dispose();
  }

  String _rowId(UnspentOutput utxo) => '${utxo.output}:${utxo.denialInfo.executions.length}';

  List<UnspentOutput> get _sortedUtxos {
    final utxos = [...widget.utxos];
    utxos.sort((a, b) => sortAscending ? _compare(a, b) : _compare(b, a));
    return utxos;
  }

  @override
  Widget build(BuildContext context) {
    final formatter = GetIt.I<FormatterProvider>();
    final utxos = _sortedUtxos;

    return SailCard(
      title: 'Your UTXOs with denial info',
      subtitle: 'List of your UTXOs with information about their deniability status.',
      error: widget.error,
      bottomPadding: false,
      newWindow: widget.newWindowButton,
      widgetHeaderEnd: widget.onDenyAll == null
          ? null
          : SailButton(
              label: 'Deny All',
              small: true,
              disabled: widget.denyAllCount == 0,
              onPressed: () async => widget.onDenyAll!(),
            ),
      child: Column(
        children: [
          SailSpacing(SailStyleValues.padding16),
          Expanded(
            child: ListenableBuilder(
              listenable: formatter,
              builder: (context, child) => SailStyleValues.phoneLayout(context)
                  ? _PhoneDenialList(
                      utxos: utxos,
                      onDeny: widget.onDeny,
                      onCancel: widget.onCancel,
                      onPause: widget.onPause,
                      onResume: widget.onResume,
                    )
                  : SailTable(
                      getRowId: (index) => utxos.isEmpty ? '0' : _rowId(utxos[index]),
                      selectedRowId: _selectedRowId(utxos),
                      onSelectedRow: widget.onSelect == null
                          ? null
                          : (rowId) => widget.onSelect!(rowId == null ? null : _byRowId(utxos, rowId)),
                      headerBuilder: (context) => [
                        const SailTableHeaderCell(name: 'UTXO'),
                        const SailTableHeaderCell(name: 'Denial ID'),
                        const SailTableHeaderCell(name: 'Status'),
                        const SailTableHeaderCell(name: 'Hops'),
                        const SailTableHeaderCell(name: 'Next Execution'),
                        const SailTableHeaderCell(name: 'Timestamp'),
                        const SailTableHeaderCell(name: 'Amount', alignment: Alignment.centerRight),
                      ],
                      cellHeight: 48.0,
                      rowBuilder: (context, row, selected) {
                        final utxo = utxos[row];
                        final hasDenialInfo = utxo.hasDenialInfo();

                        final status = denialStatus(utxo);
                        final nextExecution = hasDenialInfo
                            ? denialNextExecutionLabel(utxo.denialInfo, DateTime.now())
                            : '-';
                        final (amount, unit) = splitAmountUnit(formatter.formatSats(utxo.valueSats.toInt()));

                        return [
                          SailTableCell(
                            value: '${utxo.output.substring(0, 6)}..:${utxo.output.split(':').last}',
                            copyValue: utxo.output,
                          ),
                          SailTableCell(
                            value: '${utxo.denialInfo.id == 0 ? '-' : utxo.denialInfo.id}',
                            copyValue: utxo.denialInfo.id.toString(),
                          ),
                          SailTableCell(
                            value: status.label,
                            child: SailTooltip(
                              message: utxo.denialInfo.cancelReason,
                              child: StatusDotLabel(label: status.label, tone: denialStatusTone(status)),
                            ),
                          ),
                          SailTableCell(value: denialHopsLabel(utxo)),
                          SailTableCell(
                            value: nextExecution,
                            copyValue: denialHasScheduledNextExecution(utxo.denialInfo)
                                ? formatDate(utxo.denialInfo.nextExecutionTime.toDateTime())
                                : null,
                          ),
                          SailTableCell(value: utxo.hasReceivedAt() ? formatDate(utxo.receivedAt.toDateTime()) : '—'),
                          SailTableCell(
                            value: amount,
                            secondaryValue: unit,
                            monospace: true,
                            alignment: Alignment.centerRight,
                          ),
                        ];
                      },
                      contextMenuItems: (rowId) {
                        if (utxos.isEmpty) {
                          return [];
                        }
                        return denialMenuItems(
                          context,
                          _byRowId(utxos, rowId),
                          onDeny: widget.onDeny,
                          onCancel: widget.onCancel,
                          onPause: widget.onPause,
                          onResume: widget.onResume,
                          onShowDetails: (utxo) => _openDetails(context, utxo),
                        );
                      },
                      rowCount: utxos.length,
                      emptyPlaceholder: 'No UTXOs available',
                      drawGrid: true,
                      sortColumnIndex: _sortColumns.indexOf(sortColumn),
                      sortAscending: sortAscending,
                      onSort: (columnIndex, ascending) => setState(() {
                        sortColumn = _sortColumns[columnIndex];
                        sortAscending = ascending;
                      }),
                      onDoubleTap: (rowId) {
                        if (utxos.isEmpty) {
                          return;
                        }
                        _openDetails(context, _byRowId(utxos, rowId));
                      },
                    ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  UnspentOutput _byRowId(List<UnspentOutput> utxos, String rowId) => utxos.firstWhere((u) => _rowId(u) == rowId);

  String? _selectedRowId(List<UnspentOutput> utxos) {
    final output = widget.selectedOutput;
    if (output == null) {
      return null;
    }
    for (final utxo in utxos) {
      if (utxo.output == output) {
        return _rowId(utxo);
      }
    }
    return null;
  }

  void _openDetails(BuildContext context, UnspentOutput utxo) {
    final select = widget.onSelect;
    if (select != null) {
      select(utxo);
      return;
    }
    _showUtxoDetails(context, utxo);
  }

  int _compare(UnspentOutput a, UnspentOutput b) {
    switch (sortColumn) {
      case 'id':
        return a.denialInfo.id.compareTo(b.denialInfo.id);
      case 'hops':
        return _missingLast(a.hasDenialInfo(), b.hasDenialInfo()) ??
            a.denialInfo.executions.length.compareTo(b.denialInfo.executions.length);
      case 'txid':
        return a.output.compareTo(b.output);
      case 'amount':
        return a.valueSats.compareTo(b.valueSats);
      case 'next':
        return _missingLast(a.hasDenialInfo(), b.hasDenialInfo()) ??
            _missingLast(a.denialInfo.hasNextExecutionTime(), b.denialInfo.hasNextExecutionTime()) ??
            a.denialInfo.nextExecutionTime.toDateTime().compareTo(b.denialInfo.nextExecutionTime.toDateTime());
      case 'status':
        return _missingLast(a.hasDenialInfo(), b.hasDenialInfo()) ??
            denialStatus(a).label.compareTo(denialStatus(b).label);
      case 'timestamp':
        return _missingLast(a.hasReceivedAt(), b.hasReceivedAt()) ??
            a.receivedAt.toDateTime().compareTo(b.receivedAt.toDateTime());
      default:
        return 0;
    }
  }

  /// Null when both values exist; otherwise puts the missing one last.
  int? _missingLast(bool aHas, bool bHas) {
    if (aHas && bHas) {
      return null;
    }
    if (aHas == bHas) {
      return 0;
    }
    return aHas ? -1 : 1;
  }

  void _showUtxoDetails(BuildContext context, UnspentOutput utxo) {
    final formatter = GetIt.I<FormatterProvider>();

    showThemedDialog(
      context: context,
      builder: (context) => SailModal(
        constraints: const BoxConstraints(maxWidth: 800),
        child: SailCard(
          title: 'UTXO Details',
          subtitle: 'UTXO and Deniability Information',
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DetailRow(label: 'TxID', value: utxo.output.split(':').first),
                DetailRow(label: 'Output Index', value: utxo.output.split(':').last),
                DetailRow(label: 'Amount', value: formatter.formatSats(utxo.valueSats.toInt())),
                if (utxo.hasDenialInfo()) ...[
                  const SailSpacing(SailStyleValues.padding16),
                  BorderedSection(
                    title: 'Deniability Info',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DetailRow(label: 'Status', value: _getDeniabilityStatus(utxo)),
                        DetailRow(label: 'Completed Hops', value: '${utxo.denialInfo.executions.length}'),
                        DetailRow(label: 'Total Hops', value: '${utxo.denialInfo.numHops}'),
                        if (denialHasScheduledNextExecution(utxo.denialInfo))
                          DetailRow(
                            label: 'Next Execution',
                            value: formatDate(utxo.denialInfo.nextExecutionTime.toDateTime()),
                          ),
                        if (utxo.denialInfo.hasCancelTime())
                          DetailRow(label: 'Cancel Reason', value: utxo.denialInfo.cancelReason),
                      ],
                    ),
                  ),
                  if (utxo.denialInfo.executions.isNotEmpty) ...[
                    const SailSpacing(SailStyleValues.padding16),
                    SailText.primary13('Deniability Transactions:'),
                    const SailSpacing(SailStyleValues.padding08),
                    SizedBox(
                      height: 300,
                      child: SelectionContainer.disabled(
                        child: TXIDTransactionTable(
                          transactions: utxo.denialInfo.executions
                              .map((e) => e.fromTxid)
                              .where((txid) => txid.isNotEmpty)
                              .toList(),
                          onTransactionSelected: (txid) => _showTransactionDetails(context, txid),
                        ),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showTransactionDetails(BuildContext context, String txid) {
    showThemedDialog(
      context: context,
      builder: (context) => TransactionDetailsDialog(txid: txid),
    );
  }

  String _getDeniabilityStatus(UnspentOutput utxo) => denialDetailStatus(utxo);
}

/// The status line of the UTXO details, such as "Ongoing (1/3 hops)".
String denialDetailStatus(UnspentOutput utxo) {
  final status = denialStatus(utxo);
  return switch (status) {
    DenialStatus.none => 'No deniability',
    DenialStatus.ongoing => 'Ongoing (${utxo.denialInfo.executions.length}/${utxo.denialInfo.numHops} hops)',
    _ => status.label,
  };
}

SailStatusTone denialStatusTone(DenialStatus status) => switch (status) {
  DenialStatus.none => SailStatusTone.neutral,
  DenialStatus.ongoing => SailStatusTone.info,
  DenialStatus.paused => SailStatusTone.warning,
  DenialStatus.completed => SailStatusTone.success,
  DenialStatus.cancelled => SailStatusTone.error,
};

/// The first action of a UTXO: Pause, Resume or Deny.
({String label, Future<void> Function() run}) denialPrimaryAction(
  UnspentOutput utxo, {
  required void Function(String output, int valueSats) onDeny,
  required void Function(Int64) onPause,
  required void Function(Int64) onResume,
}) {
  if (!denialCanControl(utxo)) {
    return (label: 'Deny', run: () async => onDeny(utxo.output, utxo.valueSats.toInt()));
  }
  if (denialStatus(utxo) == DenialStatus.paused) {
    return (label: 'Resume', run: () async => onResume(utxo.denialInfo.id));
  }
  return (label: 'Pause', run: () async => onPause(utxo.denialInfo.id));
}

/// The row "…" of a UTXO: its first action, Cancel when the denial runs, and Show Details.
List<SailMenuEntity> denialMenuItems(
  BuildContext context,
  UnspentOutput utxo, {
  required void Function(String output, int valueSats) onDeny,
  required void Function(Int64) onCancel,
  required void Function(Int64) onPause,
  required void Function(Int64) onResume,
  required void Function(UnspentOutput utxo) onShowDetails,
}) {
  final primary = denialPrimaryAction(utxo, onDeny: onDeny, onPause: onPause, onResume: onResume);
  return [
    SailMenuItem(onSelected: primary.run, child: SailText.primary12(primary.label)),
    if (denialCanControl(utxo))
      SailMenuItem(
        onSelected: () => onCancel(utxo.denialInfo.id),
        child: SailText.primary12('Cancel'),
      ),
    SailMenuItem(onSelected: () => onShowDetails(utxo), child: SailText.primary12('Show Details')),
  ];
}

/// The side panel of one UTXO and its denial.
class DenialUtxoPanel extends StatelessWidget {
  final UnspentOutput utxo;
  final Future<void> Function() onClose;
  final void Function(String output, int valueSats) onDeny;
  final void Function(Int64) onCancel;
  final void Function(Int64) onPause;
  final void Function(Int64) onResume;

  const DenialUtxoPanel({
    super.key,
    required this.utxo,
    required this.onClose,
    required this.onDeny,
    required this.onCancel,
    required this.onPause,
    required this.onResume,
  });

  @override
  Widget build(BuildContext context) {
    final formatter = GetIt.I<FormatterProvider>();
    final theme = SailTheme.of(context);
    final primary = denialPrimaryAction(utxo, onDeny: onDeny, onPause: onPause, onResume: onResume);
    final info = utxo.denialInfo;
    final txids = info.executions.map((e) => e.fromTxid).where((txid) => txid.isNotEmpty).toList();

    return SailSidePanel(
      title: 'UTXO Details',
      onClose: onClose,
      menuItems: denialCanControl(utxo)
          ? () => [
              SailMenuItem(onSelected: () => onCancel(info.id), child: SailText.primary12('Cancel')),
            ]
          : null,
      child: SailColumn(
        spacing: SailStyleValues.padding12,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SailText.primary13('UTXO and Deniability Information', color: theme.colors.textSecondary),
          PanelHeadline(value: formatter.formatSats(utxo.valueSats.toInt())),
          Align(
            alignment: Alignment.centerLeft,
            child: SailStatusPill(label: denialDetailStatus(utxo), tone: denialStatusTone(denialStatus(utxo))),
          ),
          SailButton(label: primary.label, onPressed: primary.run),
          SailDetailGroup(
            fill: SailDetailFill.canvas,
            children: [
              SailStackedDetail(monospace: false, label: 'TxID', value: utxo.output.split(':').first),
              SailDetailLine(wrap: true, label: 'Output Index', value: utxo.output.split(':').last),
              SailDetailLine(wrap: true, label: 'Amount', value: formatter.formatSats(utxo.valueSats.toInt())),
            ],
          ),
          if (utxo.hasDenialInfo()) ...[
            const SailDetailHeading('Deniability Info'),
            SailDetailGroup(
              fill: SailDetailFill.canvas,
              children: [
                SailDetailLine(wrap: true, label: 'Status', value: denialDetailStatus(utxo)),
                SailDetailLine(wrap: true, label: 'Completed Hops', value: '${info.executions.length}'),
                SailDetailLine(wrap: true, label: 'Total Hops', value: '${info.numHops}'),
                if (denialHasScheduledNextExecution(info))
                  SailDetailLine(
                    wrap: true,
                    label: 'Next Execution',
                    value: formatDate(info.nextExecutionTime.toDateTime()),
                  ),
                if (info.hasCancelTime()) SailDetailLine(wrap: true, label: 'Cancel Reason', value: info.cancelReason),
              ],
            ),
            if (txids.isNotEmpty) ...[
              const SailDetailHeading('Deniability Transactions:'),
              SailDetailGroup(
                fill: SailDetailFill.canvas,
                children: [
                  for (final txid in txids)
                    SailTappable(
                      onTap: () async => showThemedDialog(
                        context: context,
                        builder: (context) => TransactionDetailsDialog(txid: txid),
                      ),
                      child: SailText.primary13(shortHash(txid), color: theme.colors.textSecondary),
                    ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _PhoneDenialList extends StatelessWidget {
  final List<UnspentOutput> utxos;
  final void Function(String output, int valueSats) onDeny;
  final void Function(Int64) onCancel;
  final void Function(Int64) onPause;
  final void Function(Int64) onResume;

  const _PhoneDenialList({
    required this.utxos,
    required this.onDeny,
    required this.onCancel,
    required this.onPause,
    required this.onResume,
  });

  @override
  Widget build(BuildContext context) {
    if (utxos.isEmpty) {
      return Center(child: SailText.secondary13('No UTXOs available'));
    }
    final formatter = GetIt.I<FormatterProvider>();
    return SailDividedList(
      itemCount: utxos.length,
      itemBuilder: (context, index) {
        final utxo = utxos[index];
        final info = utxo.denialInfo;
        final isPaused = denialStatus(utxo) == DenialStatus.paused;
        final canControl = denialCanControl(utxo);
        return SailListRow(
          title: formatter.formatSats(utxo.valueSats.toInt()),
          subtitle: 'Denial ID ${info.id == 0 ? '-' : info.id}',
          trailing: canControl
              ? SailRow(
                  spacing: SailStyleValues.padding04,
                  children: [
                    SailButton(
                      label: isPaused ? 'Resume' : 'Pause',
                      onPressed: () async => isPaused ? onResume(info.id) : onPause(info.id),
                      insideTable: true,
                      variant: ButtonVariant.outline,
                    ),
                    SailButton(
                      label: 'Cancel',
                      onPressed: () async => onCancel(info.id),
                      insideTable: true,
                      variant: ButtonVariant.outline,
                    ),
                  ],
                )
              : SailButton(
                  label: 'Deny',
                  onPressed: () async => onDeny(utxo.output, utxo.valueSats.toInt()),
                  insideTable: true,
                  variant: ButtonVariant.outline,
                ),
        );
      },
    );
  }
}

class DeniabilityViewModel extends BaseViewModel {
  final BitwindowRPC api = GetIt.I.get<BitwindowRPC>();
  final TransactionProvider transactionProvider = GetIt.I.get<TransactionProvider>();

  List<UnspentOutput> get utxos => transactionProvider.utxos;

  List<UnspentOutput> get utxosWithoutDenial => utxos.where((u) {
    if (!u.hasDenialInfo()) {
      return true;
    }
    final info = u.denialInfo;
    return info.hasCancelTime() || (!denialHasScheduledNextExecution(info) && (info.isChange || !info.hasPausedAt()));
  }).toList();

  String? _selectedOutput;

  /// The UTXO in the side panel, or null when it is gone from the wallet.
  UnspentOutput? get selectedUtxo {
    final output = _selectedOutput;
    if (output == null) {
      return null;
    }
    for (final utxo in utxos) {
      if (utxo.output == output) {
        return utxo;
      }
    }
    return null;
  }

  void selectUtxo(UnspentOutput? utxo) {
    _selectedOutput = utxo?.output;
    notifyListeners();
  }

  DeniabilityViewModel() {
    transactionProvider.addListener(notifyListeners);
    transactionProvider.addListener(errorListener);
  }

  @override
  void dispose() {
    transactionProvider.removeListener(notifyListeners);
    transactionProvider.removeListener(errorListener);
    super.dispose();
  }

  void init() {
    // Set busy state to show loading indicator
    setBusy(true);
  }

  // Post-frame initialization for async operations
  Future<void> postInit() async {
    await transactionProvider.fetch();
  }

  void errorListener() {
    setErrorForObject('deniability', transactionProvider.error);
  }

  void showDenyDialog(BuildContext context, String output, int valueSats) {
    showThemedDialog(
      context: context,
      builder: (context) => DenialDialog(output: output, valueSats: valueSats),
    );
  }

  void showDenyAllDialog(BuildContext context) {
    showThemedDialog(
      context: context,
      builder: (context) => DenialDialog(utxos: utxosWithoutDenial),
    );
  }

  /// Why the last pause, resume or cancel failed, or null.
  String? actionError;

  Future<void> cancelDenial(Int64 id) => _act(() => api.bitwindowd.cancelDenial(id));

  Future<void> pauseDenial(Int64 id) => _act(() => api.bitwindowd.pauseDenial(id));

  Future<void> resumeDenial(Int64 id) => _act(() => api.bitwindowd.resumeDenial(id));

  // A failed action reads the list again, because the row that failed can be old.
  Future<void> _act(Future<void> Function() action) async {
    try {
      await action();
      actionError = null;
    } catch (e) {
      actionError = e.toString();
    }
    notifyListeners();
    await transactionProvider.fetch();
  }
}
