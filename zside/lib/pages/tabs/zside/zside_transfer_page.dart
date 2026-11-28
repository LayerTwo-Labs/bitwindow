import 'dart:math';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart' as foundation;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sail_ui/shell/shell.dart';
import 'package:zside/providers/transactions_provider.dart';
import 'package:zside/providers/zside_provider.dart';
import 'package:zside/widgets/containers/tabs/dashboard_tab_widgets.dart';
import 'package:zside/widgets/containers/tabs/zside_tab_widgets.dart';
import 'package:zside/zside_module.dart';

@RoutePage()
class ZSideTransferTabPage extends StatelessWidget {
  const ZSideTransferTabPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder.reactive(
      viewModelBuilder: () => ZSideTransferTabViewModel(),
      builder: ((context, model, child) {
        final tabsRouter = AutoTabsRouter.of(context);
        final phone = SailStyleValues.phoneLayout(context);

        final transparent = TransparentUTXOTable(
          entries: model.transparentUTXOs,
          searchWidget: UTXOSearchField(controller: model.searchController),
          onSend: () async => model.sendTransparent(context),
          menuItems: () => [
            SailMenuItem(
              onSelected: () => model.receiveTransparent(context),
              child: SailText.primary12('Receive transparent coins'),
            ),
            SailMenuItem(
              onSelected: () => model.copyTransparentAddress(context),
              child: SailText.primary12('Copy address'),
            ),
          ],
        );
        final private = PrivateUTXOTable(
          entries: model.shieldedUTXOs,
          searchWidget: UTXOSearchField(controller: model.privateSearchController),
          onSend: () async => model.sendPrivate(context),
          menuItems: () => [
            SailMenuItem(
              onSelected: () => model.receivePrivate(context),
              child: SailText.primary12('Receive private coins'),
            ),
            SailMenuItem(
              onSelected: () => model.copyPrivateAddress(context),
              child: SailText.primary12('Copy address'),
            ),
          ],
        );

        final title = ZSideWidgetTitle(
          depositNudgeAction: () => tabsRouter.setActiveIndex(ShellTabIndex.of(ZSideModule()).parentChain),
        );

        if (phone) {
          return QtPage(
            child: TransferPhoneLayout(title: title, transparent: transparent, private: private),
          );
        }

        return QtPage(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              title,
              const SizedBox(height: SailStyleValues.padding12),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: transparent),
                    const SizedBox(width: SailStyleValues.padding12),
                    Expanded(child: private),
                  ],
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

/// The phone Transfer page: both cards at a fixed height in one vertical scroll.
class TransferPhoneLayout extends StatelessWidget {
  final Widget title;
  final Widget transparent;
  final Widget private;

  const TransferPhoneLayout({super.key, required this.title, required this.transparent, required this.private});

  static const double cardHeight = 420;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          title,
          const SizedBox(height: SailStyleValues.padding12),
          SizedBox(height: cardHeight, child: transparent),
          const SizedBox(height: SailStyleValues.padding12),
          SizedBox(height: cardHeight, child: private),
        ],
      ),
    );
  }
}

/// The search box over a UTXO table.
class UTXOSearchField extends StatelessWidget {
  final TextEditingController controller;

  const UTXOSearchField({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return SailTextField(
      controller: controller,
      hintText: 'Search UTXOs...',
      prefixIcon: Padding(
        padding: const EdgeInsets.only(left: SailStyleValues.padding10),
        child: SailSVG.fromAsset(SailSVGAsset.search, width: 14, height: 14, color: SailTheme.of(context).colors.icon),
      ),
      prefixIconConstraints: const BoxConstraints(minWidth: 28, minHeight: 14),
    );
  }
}

/// The head of a Transfer card: a grey kind label over the title, the send button and the "…" menu.
class _TransferCardHead extends StatelessWidget {
  final String kind;
  final String title;
  final String subtitle;
  final String sendLabel;
  final Future<void> Function() onSend;
  final List<SailMenuEntity> Function() menuItems;

  const _TransferCardHead({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.sendLabel,
    required this.onSend,
    required this.menuItems,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SailText.secondary12(kind),
        const SizedBox(height: SailStyleValues.padding04),
        Row(
          children: [
            Expanded(child: SailText.primary16(title, bold: true)),
            SailButton(label: sendLabel, onPressed: onSend),
            const SizedBox(width: SailStyleValues.padding08),
            SailRowMenuButton(items: menuItems),
          ],
        ),
        const SizedBox(height: SailStyleValues.padding08),
        SailText.secondary13(subtitle),
      ],
    );
  }
}

class ZSideTransferTabViewModel extends BaseViewModel {
  final log = Logger(level: Level.debug);
  ZSideProvider get _zsideProvider => GetIt.I.get<ZSideProvider>();
  SidechainBalanceProvider get _balanceProvider => GetIt.I.get<SidechainBalanceProvider>();
  TransactionsProvider get _transactionsProvider => GetIt.I.get<TransactionsProvider>();

  String get zsideAddress => _zsideProvider.zsideAddress;
  final TextEditingController searchController = TextEditingController();
  final TextEditingController privateSearchController = TextEditingController();

  List<UnshieldedUTXO> get transparentUTXOs => _zsideProvider.unshieldedUTXOs
      .where(
        (utxo) =>
            (!hideDust || utxo.amount > zsideFee) &&
            (searchController.text.isEmpty ||
                utxo.txid.contains(searchController.text) ||
                utxo.address.contains(searchController.text)),
      )
      .toList();
  List<ShieldedUTXO> get shieldedUTXOs => _zsideProvider.shieldedUTXOs
      .where(
        (utxo) => privateSearchController.text.isEmpty || utxo.txid.contains(privateSearchController.text),
      )
      .toList();

  double get balance => _balanceProvider.balance + _balanceProvider.pendingBalance;

  bool hideDust = false;

  void setHideDust(bool to) {
    hideDust = to;
    notifyListeners();
  }

  ZSideTransferTabViewModel() {
    searchController.addListener(notifyListeners);
    privateSearchController.addListener(notifyListeners);
    _zsideProvider.addListener(notifyListeners);
    _balanceProvider.addListener(notifyListeners);
    _transactionsProvider.addListener(notifyListeners);
  }

  Future<void> sendPrivate(BuildContext context) async {
    final privateBalance = satoshiToBTC(_zsideProvider.shieldedSats);

    await showThemedDialog(
      context: context,
      builder: (BuildContext context) {
        return SendOnSidechainAction(
          maxAmount: max(privateBalance - _zsideProvider.sideFee, 0),
          customSendAction: (address, amount) async {
            return await _zsideProvider.rpc.sendShielded(
              address,
              btcToSatoshi(amount).toDouble(),
              btcToSatoshi(await _zsideProvider.rpc.sideEstimateFee()).toDouble(),
            );
          },
        );
      },
    );
  }

  void receivePrivate(BuildContext context) async {
    final provider = GetIt.I.get<ZSideProvider>();

    await showThemedDialog(
      context: context,
      builder: (BuildContext context) {
        return ReceiveAction(
          customTitle: 'Receive private coins',
          customReceiveAction: () => provider.rpc.getNewShieldedAddress(),
          initialAddress: provider.zsideAddress,
        );
      },
    );
  }

  void sendTransparent(BuildContext context) async {
    final transparentBalance = transparentUTXOs.fold(0.0, (sum, elem) => sum + elem.amount);

    await showThemedDialog(
      context: context,
      builder: (BuildContext context) {
        return SendOnSidechainAction(
          maxAmount: max(transparentBalance - _zsideProvider.sideFee, 0),
          customSendAction: (address, amount) async {
            return await _zsideProvider.rpc.sendTransparent(
              address,
              btcToSatoshi(amount).toDouble(),
              btcToSatoshi(await _zsideProvider.rpc.sideEstimateFee()).toDouble(),
            );
          },
        );
      },
    );
  }

  Future<void> copyTransparentAddress(BuildContext context) async {
    try {
      final address = await _zsideProvider.rpc.getSideAddress();
      await Clipboard.setData(ClipboardData(text: address));
      if (!context.mounted) {
        return;
      }
      showSnackBar(context, 'Copied $address');
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      await errorDialog(
        context: context,
        action: 'Copy address',
        title: 'Could not get a transparent address',
        subtitle: error.toString(),
      );
    }
  }

  Future<void> copyPrivateAddress(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: zsideAddress));
    if (!context.mounted) {
      return;
    }
    showSnackBar(context, 'Copied $zsideAddress');
  }

  void receiveTransparent(BuildContext context) async {
    await showThemedDialog(
      context: context,
      builder: (BuildContext context) {
        return ReceiveAction(
          customReceiveAction: () async {
            return await _zsideProvider.rpc.getSideAddress();
          },
        );
      },
    );
  }

  @override
  void dispose() {
    searchController.removeListener(notifyListeners);
    privateSearchController.removeListener(notifyListeners);
    super.dispose();
    _zsideProvider.removeListener(notifyListeners);
    _balanceProvider.removeListener(notifyListeners);
    _transactionsProvider.removeListener(notifyListeners);
  }
}

class ZSideWidgetTitle extends StatelessWidget {
  final VoidCallback depositNudgeAction;

  const ZSideWidgetTitle({
    super.key,
    required this.depositNudgeAction,
  });

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder.reactive(
      viewModelBuilder: () => ZSideWidgetTitleViewModel(),
      builder: ((context, model, child) {
        if (model.balance != 0) {
          return SailCard(
            child: Row(
              children: [
                Expanded(child: SailText.primary13('Your ZSide-address: ${model.zsideAddress}')),
                const SizedBox(width: SailStyleValues.padding08),
                SailIconBoxButton(
                  icon: SailSVGAsset.iconCopy,
                  tooltip: 'Copy address',
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: model.zsideAddress));
                    if (!context.mounted) {
                      return;
                    }
                    showSnackBar(context, 'Copied ${model.zsideAddress}');
                  },
                ),
              ],
            ),
          );
        }

        return SailRow(
          spacing: SailStyleValues.padding08,
          children: [
            SailButton(
              label: 'Deposit coins',
              variant: ButtonVariant.primary,
              onPressed: () async {
                try {
                  depositNudgeAction();
                } catch (err) {
                  if (!context.mounted) {
                    return;
                  }

                  await errorDialog(
                    context: context,
                    action: 'Deposit coins',
                    title: 'Could not move to deposit tab',
                    subtitle: err.toString(),
                  );
                }
              },
              loading: model.isBusy,
            ),
            SailText.secondary12(
              'To get started, you must deposit coins to your sidechain. Deposit on the Parent Chain tab',
            ),
            Expanded(child: Container()),
          ],
        );
      }),
    );
  }
}

class ZSideWidgetTitleViewModel extends BaseViewModel {
  final log = Logger(level: Level.debug);
  ZSideProvider get _zsideProvider => GetIt.I.get<ZSideProvider>();
  SidechainBalanceProvider get _balanceProvider => GetIt.I.get<SidechainBalanceProvider>();

  String get zsideAddress => _zsideProvider.zsideAddress;
  double get balance => _balanceProvider.balance + _balanceProvider.pendingBalance;

  bool showAll = false;

  ZSideWidgetTitleViewModel() {
    _zsideProvider.addListener(notifyListeners);
    _balanceProvider.addListener(notifyListeners);
  }

  @override
  void dispose() {
    super.dispose();
    _zsideProvider.removeListener(notifyListeners);
    _balanceProvider.removeListener(notifyListeners);
  }
}

class TransparentUTXOTable extends StatefulWidget {
  final List<UnshieldedUTXO> entries;
  final Widget searchWidget;
  final Future<void> Function() onSend;
  final List<SailMenuEntity> Function() menuItems;

  const TransparentUTXOTable({
    super.key,
    required this.entries,
    required this.searchWidget,
    required this.onSend,
    required this.menuItems,
  });

  @override
  State<TransparentUTXOTable> createState() => _TransparentUTXOTableState();
}

class _TransparentUTXOTableState extends State<TransparentUTXOTable> {
  String sortColumn = 'amount';
  bool sortAscending = true;
  List<UnshieldedUTXO> entries = [];

  @override
  void initState() {
    super.initState();
    entries = widget.entries;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!foundation.listEquals(entries, widget.entries)) {
      entries = List.from(widget.entries);
      sortEntries();
    }
  }

  void onSort(String column) {
    setState(() {
      if (sortColumn == column) {
        sortAscending = !sortAscending;
      } else {
        sortColumn = column;
        sortAscending = true;
      }
      sortEntries();
    });
  }

  void sortEntries() {
    entries.sort((a, b) {
      dynamic aValue;
      dynamic bValue;

      switch (sortColumn) {
        case 'confirmations':
          aValue = a.confirmations;
          bValue = b.confirmations;
          break;
        case 'amount':
          aValue = a.amount;
          bValue = b.amount;
          break;
        case 'address':
          aValue = a.address;
          bValue = b.address;
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
      builder: (context, child) => LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          return SailCard(
            bottomPadding: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TransferCardHead(
                  kind: 'Transparent coins',
                  title: 'Transparent UTXOs',
                  subtitle: 'List of unspent transaction outputs in your transparent address',
                  sendLabel: 'Send transparent coins',
                  onSend: widget.onSend,
                  menuItems: widget.menuItems,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: SailStyleValues.padding12),
                  child: widget.searchWidget,
                ),
                Expanded(
                  child: SailTable(
                    getRowId: (index) => widget.entries[index].txid,
                    headerBuilder: (context) => [
                      SailTableHeaderCell(
                        name: 'Confirmations',
                        onSort: () => onSort('confirmations'),
                      ),
                      SailTableHeaderCell(
                        name: 'Amount',
                        onSort: () => onSort('amount'),
                      ),
                      SailTableHeaderCell(
                        name: 'Address',
                        onSort: () => onSort('address'),
                      ),
                      SailTableHeaderCell(
                        name: 'TxID',
                        onSort: () => onSort('txid'),
                      ),
                    ],
                    rowBuilder: (context, row, selected) {
                      final entry = widget.entries[row];
                      return [
                        SailTableCell(
                          value: entry.confirmations.toString(),
                        ),
                        SailTableCell(
                          value: formatter.formatBTC(entry.amount),
                          monospace: true,
                        ),
                        SailTableCell(
                          value: entry.address,
                        ),
                        SailTableCell(
                          value: entry.txid,
                          copyValue: entry.txid,
                        ),
                      ];
                    },
                    rowCount: widget.entries.length,
                    sortColumnIndex: [
                      'confirmations',
                      'amount',
                      'address',
                      'txid',
                    ].indexOf(sortColumn),
                    sortAscending: sortAscending,
                    onSort: (columnIndex, ascending) {
                      onSort(['confirmations', 'amount', 'address', 'txid'][columnIndex]);
                    },
                    onDoubleTap: (rowId) {
                      final utxo = widget.entries.firstWhere(
                        (u) => u.txid == rowId,
                      );
                      _showUtxoDetails(context, utxo);
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showUtxoDetails(BuildContext context, UnshieldedUTXO utxo) {
    final formatter = GetIt.I<FormatterProvider>();
    showThemedDialog(
      context: context,
      builder: (context) => SailModal(
        constraints: const BoxConstraints(maxWidth: 800),
        child: SailCard(
          title: 'UTXO Details',
          withCloseButton: true,
          subtitle: 'Details of the selected UTXO',
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DetailRow(label: 'TxID', value: utxo.txid),
                DetailRow(label: 'Amount', value: formatter.formatBTC(utxo.amount)),
                DetailRow(label: 'Address', value: utxo.address),
                DetailRow(label: 'Confirmations', value: utxo.confirmations.toString()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PrivateUTXOTable extends StatefulWidget {
  final List<ShieldedUTXO> entries;
  final Widget searchWidget;
  final Future<void> Function() onSend;
  final List<SailMenuEntity> Function() menuItems;

  const PrivateUTXOTable({
    super.key,
    required this.entries,
    required this.searchWidget,
    required this.onSend,
    required this.menuItems,
  });

  @override
  State<PrivateUTXOTable> createState() => _PrivateUTXOTableState();
}

class _PrivateUTXOTableState extends State<PrivateUTXOTable> {
  String sortColumn = 'amount';
  bool sortAscending = true;
  List<ShieldedUTXO> entries = [];

  @override
  void initState() {
    super.initState();
    entries = widget.entries;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!foundation.listEquals(entries, widget.entries)) {
      entries = List.from(widget.entries);
      sortEntries();
    }
  }

  void onSort(String column) {
    setState(() {
      if (sortColumn == column) {
        sortAscending = !sortAscending;
      } else {
        sortColumn = column;
        sortAscending = true;
      }
      sortEntries();
    });
  }

  void sortEntries() {
    entries.sort((a, b) {
      dynamic aValue;
      dynamic bValue;

      switch (sortColumn) {
        case 'confirmations':
          aValue = a.confirmations;
          bValue = b.confirmations;
          break;
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
      builder: (context, child) => LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          return SailCard(
            bottomPadding: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TransferCardHead(
                  kind: 'Private coins',
                  title: 'Private UTXOs',
                  subtitle: 'List of unspent transaction outputs in your private address',
                  sendLabel: 'Send private coins',
                  onSend: widget.onSend,
                  menuItems: widget.menuItems,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: SailStyleValues.padding12),
                  child: widget.searchWidget,
                ),
                Expanded(
                  child: SailTable(
                    getRowId: (index) => widget.entries[index].txid,
                    headerBuilder: (context) => [
                      SailTableHeaderCell(
                        name: 'Confirmations',
                        onSort: () => onSort('confirmations'),
                      ),
                      SailTableHeaderCell(
                        name: 'Amount',
                        onSort: () => onSort('amount'),
                      ),
                      SailTableHeaderCell(
                        name: 'TxID',
                        onSort: () => onSort('txid'),
                      ),
                    ],
                    rowBuilder: (context, row, selected) {
                      final entry = widget.entries[row];
                      return [
                        SailTableCell(
                          value: entry.confirmations.toString(),
                        ),
                        SailTableCell(
                          value: formatter.formatBTC(entry.amount),
                          monospace: true,
                          textColor: getCastColor(entry.amount, SailTheme.of(context).colors),
                        ),
                        SailTableCell(
                          value: entry.txid,
                          copyValue: entry.txid,
                        ),
                      ];
                    },
                    rowCount: widget.entries.length,
                    sortColumnIndex: [
                      'confirmations',
                      'amount',
                      'txid',
                    ].indexOf(sortColumn),
                    sortAscending: sortAscending,
                    onSort: (columnIndex, ascending) {
                      onSort(['confirmations', 'amount', 'txid'][columnIndex]);
                    },
                    onDoubleTap: (rowId) {
                      final utxo = widget.entries.firstWhere(
                        (u) => u.txid == rowId,
                      );
                      _showUtxoDetails(context, utxo);
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showUtxoDetails(BuildContext context, ShieldedUTXO utxo) {
    final formatter = GetIt.I<FormatterProvider>();
    showThemedDialog(
      context: context,
      builder: (context) => SailModal(
        constraints: const BoxConstraints(maxWidth: 800),
        child: SailCard(
          title: 'UTXO Details',
          withCloseButton: true,
          subtitle: 'Details of the selected UTXO',
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DetailRow(label: 'TxID', value: utxo.txid),
                DetailRow(label: 'Amount', value: formatter.formatBTC(utxo.amount)),
                DetailRow(label: 'Confirmations', value: utxo.confirmations.toString()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
