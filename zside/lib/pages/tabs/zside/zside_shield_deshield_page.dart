import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:zside/providers/zside_provider.dart';
import 'package:zside/widgets/containers/tabs/zside_tab_widgets.dart';

@RoutePage()
class ZSideShieldDeshieldTabPage extends StatelessWidget {
  const ZSideShieldDeshieldTabPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder.reactive(
      viewModelBuilder: () => ZSideShieldTabViewModel(),
      builder: ((context, model, child) {
        final phone = SailStyleValues.phoneLayout(context);
        final tables = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SailCard(
                bottomPadding: false,
                title: 'Transparent UTXOs ${model.unshieldedUTXOs.length}',
                subtitle: 'View and shield your transparent UTXOs',
                error: model.loadError,
                widgetHeaderEnd: SailToggle(
                  label: 'Hide dust UTXOs',
                  value: model.hideDust,
                  onChanged: (to) => model.setShowAll(to),
                ),
                child: UnshieldedUTXOTable(
                  entries: model.unshieldedUTXOs,
                  selectedTxid: phone ? null : model.selectedTransparent?.txid,
                  onSelect: (utxo) => phone ? model.shield(context, utxo) : model.selectTransparent(utxo),
                  onShield: (utxo) => phone ? model.shield(context, utxo) : model.selectTransparent(utxo),
                  onMeltSingle: (utxo) => model.meltSingle(context, utxo),
                ),
              ),
            ),
            const SizedBox(height: SailStyleValues.padding12),
            Expanded(
              child: SailCard(
                title: 'Private UTXOs ${model.shieldedUTXOs.length}',
                subtitle: 'View and deshield your private UTXOs',
                error: model.loadError,
                bottomPadding: false,
                child: ShieldedUTXOTable(
                  entries: model.shieldedUTXOs,
                  selectedTxid: phone ? null : model.selectedPrivate?.txid,
                  onSelect: (utxo) => phone ? model.deshield(context, utxo) : model.selectPrivate(utxo),
                  onDeshield: (utxo) => phone ? model.deshield(context, utxo) : model.selectPrivate(utxo),
                  onCastSingle: (utxo) => model.castSingle(context, utxo),
                ),
              ),
            ),
          ],
        );

        return QtPage(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: tables),
              if (!phone && model.selectedTransparent != null) ...[
                const SizedBox(width: SailStyleValues.padding12),
                SailSidePanel(
                  key: const ValueKey('shield-panel'),
                  title: 'Shield coins',
                  onClose: () async => model.clearSelection(),
                  child: ShieldUTXOForm(utxo: model.selectedTransparent!, onDone: model.clearSelection),
                ),
              ],
              if (!phone && model.selectedPrivate != null) ...[
                const SizedBox(width: SailStyleValues.padding12),
                SailSidePanel(
                  key: const ValueKey('deshield-panel'),
                  title: 'Deshield coins',
                  onClose: () async => model.clearSelection(),
                  child: DeshieldUTXOForm(utxo: model.selectedPrivate!, onDone: model.clearSelection),
                ),
              ],
            ],
          ),
        );
      }),
    );
  }
}

class ZSideShieldTabViewModel extends BaseViewModel {
  final log = Logger(level: Level.debug);
  ZSideProvider get _zsideProvider => GetIt.I.get<ZSideProvider>();
  SidechainBalanceProvider get _balanceProvider => GetIt.I.get<SidechainBalanceProvider>();

  String get zsideAddress => _zsideProvider.zsideAddress;
  List<UnshieldedUTXO> get unshieldedUTXOs =>
      _zsideProvider.unshieldedUTXOs.where((u) => !hideDust || u.amount > zsideFee).toList();
  List<ShieldedUTXO> get shieldedUTXOs => _zsideProvider.shieldedUTXOs;
  String? get loadError => _zsideProvider.error;

  double get balance => _balanceProvider.balance + _balanceProvider.pendingBalance;

  bool hideDust = false;

  UnshieldedUTXO? selectedTransparent;
  ShieldedUTXO? selectedPrivate;

  void setShowAll(bool to) {
    hideDust = to;
    notifyListeners();
  }

  void selectTransparent(UnshieldedUTXO? utxo) {
    selectedTransparent = utxo;
    selectedPrivate = null;
    notifyListeners();
  }

  void selectPrivate(ShieldedUTXO? utxo) {
    selectedPrivate = utxo;
    selectedTransparent = null;
    notifyListeners();
  }

  void clearSelection() {
    selectedTransparent = null;
    selectedPrivate = null;
    notifyListeners();
  }

  ZSideShieldTabViewModel() {
    _zsideProvider.addListener(notifyListeners);
    _balanceProvider.addListener(notifyListeners);
  }

  void melt(BuildContext context) async {
    await showThemedDialog(
      context: context,
      builder: (BuildContext context) {
        return const MeltAction(
          doEverythingMode: false,
        );
      },
    );
  }

  void cast(BuildContext context) async {
    await showThemedDialog(
      context: context,
      builder: (BuildContext context) {
        return const CastAction();
      },
    );
  }

  void meltSingle(BuildContext context, UnshieldedUTXO unshieldedUTXO) async {
    await showThemedDialog(
      context: context,
      builder: (BuildContext context) {
        return MeltSingleUTXOAction(utxo: unshieldedUTXO);
      },
    );
  }

  void castSingle(BuildContext context, ShieldedUTXO shieldedUTXO) async {
    await showThemedDialog(
      context: context,
      builder: (BuildContext context) {
        return CastSingleUTXOAction(utxo: shieldedUTXO);
      },
    );
  }

  void shield(BuildContext context, UnshieldedUTXO unshieldedUTXO) async {
    await showThemedDialog(
      context: context,
      builder: (BuildContext context) {
        return ShieldUTXOAction(utxo: unshieldedUTXO);
      },
    );
  }

  void deshield(BuildContext context, ShieldedUTXO shieldedUTXO) async {
    await showThemedDialog(
      context: context,
      builder: (BuildContext context) {
        return DeshieldUTXOAction(utxo: shieldedUTXO);
      },
    );
  }

  @override
  void dispose() {
    super.dispose();
    _zsideProvider.removeListener(notifyListeners);
    _balanceProvider.removeListener(notifyListeners);
  }
}

class UnshieldedUTXOTable extends StatefulWidget {
  final List<UnshieldedUTXO> entries;
  final String? selectedTxid;
  final void Function(UnshieldedUTXO) onSelect;
  final void Function(UnshieldedUTXO) onShield;
  final void Function(UnshieldedUTXO) onMeltSingle;

  const UnshieldedUTXOTable({
    super.key,
    required this.entries,
    this.selectedTxid,
    required this.onSelect,
    required this.onShield,
    required this.onMeltSingle,
  });

  @override
  State<UnshieldedUTXOTable> createState() => _UnshieldedUTXOTableState();
}

class _UnshieldedUTXOTableState extends State<UnshieldedUTXOTable> {
  String sortColumn = 'amount';
  bool sortAscending = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    onSort(sortColumn);
  }

  void onSort(String column) {
    if (sortColumn == column) {
      sortAscending = !sortAscending;
    } else {
      sortColumn = column;
      sortAscending = true;
    }
    sortEntries();
    setState(() {});
  }

  void sortEntries() {
    widget.entries.sort((a, b) {
      dynamic aValue = '';
      dynamic bValue = '';

      switch (sortColumn) {
        case 'amount':
          aValue = a.amount;
          bValue = b.amount;
          break;
        case 'txid':
          aValue = a.txid;
          bValue = b.txid;
          break;
      }

      return sortAscending ? aValue.compareTo(bValue) : bValue.compareTo(aValue);
    });
  }

  @override
  Widget build(BuildContext context) {
    final formatter = GetIt.I<FormatterProvider>();

    return ListenableBuilder(
      listenable: formatter,
      builder: (context, child) => SailTable(
        getRowId: (index) => widget.entries[index].txid,
        headerBuilder: (context) => [
          SailTableHeaderCell(name: 'Amount', onSort: () => onSort('amount')),
          SailTableHeaderCell(name: 'TxID', onSort: () => onSort('txid')),
        ],
        selectedRowId: widget.selectedTxid,
        onRowTap: (txid) => widget.onSelect(widget.entries.firstWhere((e) => e.txid == txid)),
        contextMenuItems: (txid) {
          final entry = widget.entries.firstWhere((e) => e.txid == txid);
          return [
            SailMenuItem(onSelected: () => widget.onShield(entry), child: SailText.primary12('Shield')),
            SailMenuItem(onSelected: () => widget.onMeltSingle(entry), child: SailText.primary12('Melt single UTXO')),
          ];
        },
        rowBuilder: (context, row, selected) {
          final entry = widget.entries[row];
          return [
            SailTableCell(value: formatter.formatBTC(entry.amount), monospace: true),
            SailTableCell(value: entry.txid),
          ];
        },
        rowCount: widget.entries.length,
      ),
    );
  }
}

class ShieldedUTXOTable extends StatefulWidget {
  final List<ShieldedUTXO> entries;
  final String? selectedTxid;
  final void Function(ShieldedUTXO) onSelect;
  final void Function(ShieldedUTXO) onDeshield;
  final void Function(ShieldedUTXO) onCastSingle;

  const ShieldedUTXOTable({
    super.key,
    required this.entries,
    this.selectedTxid,
    required this.onSelect,
    required this.onDeshield,
    required this.onCastSingle,
  });

  @override
  State<ShieldedUTXOTable> createState() => _ShieldedUTXOTableState();
}

class _ShieldedUTXOTableState extends State<ShieldedUTXOTable> {
  String sortColumn = 'amount';
  bool sortAscending = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    onSort(sortColumn);
  }

  void onSort(String column) {
    if (sortColumn == column) {
      sortAscending = !sortAscending;
    } else {
      sortColumn = column;
      sortAscending = true;
    }
    sortEntries();
    setState(() {});
  }

  void sortEntries() {
    widget.entries.sort((a, b) {
      dynamic aValue = '';
      dynamic bValue = '';

      switch (sortColumn) {
        case 'amount':
          aValue = a.amount;
          bValue = b.amount;
          break;
        case 'txid':
          aValue = a.txid;
          bValue = b.txid;
          break;
      }

      return sortAscending ? aValue.compareTo(bValue) : bValue.compareTo(aValue);
    });
  }

  @override
  Widget build(BuildContext context) {
    final formatter = GetIt.I<FormatterProvider>();

    return ListenableBuilder(
      listenable: formatter,
      builder: (context, child) => SailTable(
        getRowId: (index) => widget.entries[index].txid,
        headerBuilder: (context) => [
          SailTableHeaderCell(name: 'Amount', onSort: () => onSort('amount')),
          SailTableHeaderCell(name: 'TxID', onSort: () => onSort('txid')),
        ],
        selectedRowId: widget.selectedTxid,
        onRowTap: (txid) => widget.onSelect(widget.entries.firstWhere((e) => e.txid == txid)),
        contextMenuItems: (txid) {
          final entry = widget.entries.firstWhere((e) => e.txid == txid);
          return [
            SailMenuItem(onSelected: () => widget.onDeshield(entry), child: SailText.primary12('Deshield')),
            SailMenuItem(onSelected: () => widget.onCastSingle(entry), child: SailText.primary12('Cast single UTXO')),
          ];
        },
        rowBuilder: (context, row, selected) {
          final entry = widget.entries[row];
          return [
            SailTableCell(value: formatter.formatBTC(entry.amount), monospace: true),
            SailTableCell(value: entry.txid),
          ];
        },
        rowCount: widget.entries.length,
      ),
    );
  }
}
