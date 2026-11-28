import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:auto_route/auto_route.dart';
import 'package:bitwindow/pages/wallet/wallet_overview.dart' show phoneHistoryAmount;
import 'package:bitwindow/log_window.dart';
import 'package:bitwindow/utils/deposit_fee.dart';
import 'package:bitwindow/pages/explorer/block_explorer_dialog.dart';
import 'package:bitwindow/pages/sidechain_activation_management_page.dart';
import 'package:bitwindow/pages/sidechain_host_page.dart';
import 'package:bitwindow/providers/sidechain_provider.dart';
import 'package:bitwindow/providers/transactions_provider.dart';
import 'package:bitwindow/sidechains/hosted_modules.dart';
import 'package:bitwindow/widgets/fast_withdrawal_tab.dart';
import 'package:bitwindow/widgets/network_unavailable_body.dart';
import 'package:bitwindow/widgets/starters_tab.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:sidechain_core/gen/wallet/v1/wallet.pb.dart';
import 'package:sidechain_core/providers/binaries/app_run_host.dart';
import 'package:sail_ui/sail_ui.dart';

/// The Sidechains tab: the slot table, or one chain inside BitWindow.
@RoutePage()
class SidechainsPage extends StatelessWidget {
  const SidechainsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AutoRouter();
  }
}

@RoutePage()
class SidechainSlotsPage extends StatelessWidget {
  const SidechainSlotsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return QtPage(
      child: ViewModelBuilder.reactive(
        viewModelBuilder: () => SidechainsViewModel(),
        builder: (context, model, child) {
          return InlineTabBar(
            key: ValueKey('sidechains_page'),
            tabs: [
              TabItem(label: 'Overview', child: SidechainsTab()),
              TabItem(label: 'Fast Withdrawal', child: FastWithdrawalTab()),
              TabItem(label: 'Starters', child: StartersTab()),
            ],
            initialIndex: 0,
          );
        },
      ),
    );
  }
}

class SidechainsTab extends ViewModelWidget<SidechainsViewModel> {
  const SidechainsTab({super.key});

  @override
  Widget build(BuildContext context, SidechainsViewModel viewModel) {
    final hashWarning = viewModel.hashMismatchWarning;

    final gated = viewModel.networkSupportsSidechains && viewModel.l1Gate != L1Gate.ready;

    final Widget mainContent = gated
        ? const _L1RequiredCard()
        : SailStyleValues.phoneLayout(context)
        ? SingleChildScrollView(
            child: SailColumn(
              spacing: SailStyleValues.padding12,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SidechainsList(smallVersion: false),
                const SizedBox(height: _phoneDepositsHeight, child: DepositWithdrawView()),
              ],
            ),
          )
        : const SidechainsOverview();

    if (hashWarning == null) {
      return mainContent;
    }

    // A possibly-tampered binary outranks the gate: the warning stays up through
    // an hours-long sync rather than being hidden behind it.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HashMismatchBanner(names: hashWarning),
        Expanded(child: mainContent),
      ],
    );
  }
}

/// The slot table, and the panel of the selected sidechain at its right.
class SidechainsOverview extends ViewModelWidget<SidechainsViewModel> {
  const SidechainsOverview({super.key});

  @override
  Widget build(BuildContext context, SidechainsViewModel viewModel) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Expanded(child: SidechainsList(smallVersion: false)),
        if (viewModel.selectedSidechain != null) ...[
          const SizedBox(width: SailStyleValues.padding12),
          const SidechainPanel(),
        ],
      ],
    );
  }
}

/// Why the sidechains tab can't do anything yet.
enum L1Gate { ready, unavailable, stopped, starting, syncing }

/// The enforcer must connect and complete its sync before the tab opens.
@visibleForTesting
L1Gate resolveL1Gate({
  required bool walletNeedsBackends,
  required bool remoteEnforcerAvailable,
  required bool coreConnected,
  required bool enforcerConnected,
  required bool coming,
  required bool synced,
  required bool chainIsEmpty,
}) {
  if (!walletNeedsBackends && !remoteEnforcerAvailable) {
    return L1Gate.unavailable;
  }
  if ((walletNeedsBackends && !coreConnected) || !enforcerConnected) {
    return coming ? L1Gate.starting : L1Gate.stopped;
  }
  // A fresh regtest node sits at 0/0 with nothing to sync from, and isSynced
  // needs a non-zero goal — waiting for it would block the tab until someone
  // mines. The orchestrator calls that steady state too (health.go). Once the
  // chain has any height this no longer applies: catching up is real syncing.
  if (chainIsEmpty) {
    return L1Gate.ready;
  }
  return synced ? L1Gate.ready : L1Gate.syncing;
}

/// Names the networks that serve sidechains in light mode.
@visibleForTesting
String lightSidechainNetworksLine(List<String> networks) {
  if (networks.isEmpty) {
    return 'No network hosts an enforcer yet, so light mode serves sidechains nowhere.';
  }
  return 'Light mode serves sidechains on ${networks.join(', ')}.';
}

/// Stands in for the whole tab while the L1 stack is missing, and in full mode
/// doubles as the place to start it — the same daemons the bottom nav reports on.
class _L1RequiredCard extends ViewModelWidget<SidechainsViewModel> {
  const _L1RequiredCard();

  @override
  Widget build(BuildContext context, SidechainsViewModel viewModel) {
    final gate = viewModel.l1Gate;

    if (gate == L1Gate.unavailable) {
      return SailCard(
        title: 'Sidechains are unavailable in light mode',
        child: Padding(
          padding: const EdgeInsets.all(SailStyleValues.padding12),
          child: SailColumn(
            spacing: SailStyleValues.padding08,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SailText.secondary13(
                'This network hosts no enforcer. Select full mode in Settings to use sidechains here.',
              ),
              SailText.secondary13(lightSidechainNetworksLine(viewModel.remoteEnforcerNetworks)),
              SailText.secondary13('Your Bitcoin wallet still uses Electrum.'),
            ],
          ),
        ),
      );
    }

    return SailCard(
      title: switch (gate) {
        L1Gate.stopped => 'The enforcer connection is not ready',
        L1Gate.starting => 'The enforcer connection starts',
        _ => 'The enforcer sync is not complete',
      },
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: SailStyleValues.padding12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 820,
              child: SailText.secondary13(
                switch (gate) {
                  L1Gate.stopped =>
                    'The enforcer must connect and complete its sync before this tab can show sidechain data.',
                  // One string for both: the enforcer drops in and out while it
                  // catches up, and a per-state string reflows the page each time.
                  _ => 'The slot list and balances stay empty until the enforcer reaches the chain tip.',
                },
              ),
            ),
            const SailSpacing(SailStyleValues.padding16),
            // The same cards the bottom nav shows, so status, sync progress and
            // the per-daemon restart/logs controls stay in one implementation.
            if (NodeModeProvider.runsLocalBackends)
              DaemonConnectionCard(
                connection: viewModel.mainchainConnection,
                syncInfo: viewModel.mainchainSyncInfo,
                infoMessage: null,
                restartDaemon: () => viewModel.restartDaemon(BitcoinCore()),
                stopDaemon: () => viewModel.stopDaemon(BitcoinCore()),
                navigateToLogs: viewModel.navigateToLogs,
              ),
            DaemonConnectionCard(
              connection: viewModel.enforcerConnection,
              syncInfo: viewModel.enforcerSyncInfo,
              infoMessage: viewModel.enforcerInfoMessage,
              remote: !NodeModeProvider.runsLocalBackends,
              restartDaemon: NodeModeProvider.runsLocalBackends ? () => viewModel.restartDaemon(Enforcer()) : null,
              stopDaemon: NodeModeProvider.runsLocalBackends ? () => viewModel.stopDaemon(Enforcer()) : null,
              navigateToLogs: viewModel.navigateToLogs,
            ),
            if (gate == L1Gate.stopped &&
                NodeModeProvider.runsLocalBackends &&
                SailStyleValues.phoneLayout(context)) ...[
              const SailSpacing(SailStyleValues.padding16),
              SailButton(label: 'Start Bitcoin Core + Enforcer', onPressed: viewModel.startL1),
              const SailSpacing(SailStyleValues.padding12),
              SailText.secondary12('The first start must download and check the chain.'),
            ] else if (gate == L1Gate.stopped && NodeModeProvider.runsLocalBackends) ...[
              const SailSpacing(SailStyleValues.padding16),
              Row(
                children: [
                  SailButton(
                    label: 'Start Bitcoin Core + Enforcer',
                    onPressed: viewModel.startL1,
                  ),
                  const SizedBox(width: SailStyleValues.padding12),
                  Flexible(
                    child: SailText.secondary12('The first start must download and check the chain.'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HashMismatchBanner extends StatelessWidget {
  final String names;

  const _HashMismatchBanner({required this.names});

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);

    return SailTooltip(
      message:
          'The downloaded binaries do not match the expected hashes from the release server.\n'
          'This could indicate the binaries were tampered with or the download was corrupted.\n'
          'Re-download these sidechains to resolve.',
      child: Container(
        padding: const EdgeInsets.all(SailStyleValues.padding12),
        margin: const EdgeInsets.only(bottom: SailStyleValues.padding08),
        decoration: BoxDecoration(
          color: theme.colors.error.withValues(alpha: 0.1),
          borderRadius: context.sailTheme.chrome.radius,
          border: Border.all(color: theme.colors.error.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            SailSVG.fromAsset(SailSVGAsset.triangleAlert, width: 18, color: theme.colors.error),
            const SizedBox(width: SailStyleValues.padding08),
            Expanded(
              child: SailText.primary13(
                'Hash mismatch detected for $names',
                color: theme.colors.error,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SidechainsList extends ViewModelWidget<SidechainsViewModel> {
  final bool smallVersion;

  const SidechainsList({super.key, required this.smallVersion});

  @override
  Widget build(BuildContext context, SidechainsViewModel viewModel) {
    if (!viewModel.networkSupportsSidechains) {
      return SailCard(
        title: 'Sidechains',
        subtitle: 'Not available on this network',
        child: const NetworkUnavailableBody(
          heading: 'Unlock Sidechains with BIP300',
          intro:
              'Sidechains are only available on Drivechain-enabled networks (eCash and Signet). '
              'These networks implement BIP300, which enables trustless two-way pegged sidechains.',
          sections: [
            (
              'What are Sidechains?',
              'Sidechains allow you to move your Bitcoin to separate blockchains with different features, '
                  'while maintaining the security and scarcity of Bitcoin. Think of them as Bitcoin-backed '
                  'altcoins that you can freely move between.',
            ),
            (
              'How to Enable Sidechains',
              '1. Go to Settings\n'
                  '2. Switch to "eCash" or "Signet" network\n'
                  '3. Restart BitWindow\n'
                  '4. Return to this tab to activate sidechains',
            ),
            (
              'Learn More',
              'BIP300 (Hashrate Escrows) and BIP301 (Blind Merged Mining) enable true sidechain functionality. '
                  'Visit drivechain.info to learn more about how Drivechain works and why it matters for Bitcoin.',
            ),
          ],
        ),
      );
    }

    final error = viewModel.error('sidechain');
    final phone = SailStyleValues.phoneLayout(context);
    final search = SailTextField(
      key: const ValueKey('sidechains_search'),
      hintText: 'Search sidechains',
      controller: viewModel.searchController,
      prefixIcon: Padding(
        padding: const EdgeInsets.only(left: 12, right: 8),
        child: SailSVG.fromAsset(
          SailSVGAsset.search,
          width: 20,
          height: 20,
          color: context.sailTheme.colors.textTertiary,
        ),
      ),
      prefixIconConstraints: const BoxConstraints(maxHeight: 20, maxWidth: 40),
    );
    final addRemove = SailButton(
      label: 'Add or remove',
      variant: ButtonVariant.ghost,
      onPressed: viewModel.sidechainManagementUnavailable
          ? null
          : () => showSidechainActivationManagementModal(context),
    );
    final table = SailSkeletonizer(
      description: 'Waiting for enforcer to become available..',
      enabled: viewModel.loading,
      child: const SidechainsTable(),
    );

    return SailCard(
      title: 'Sidechains',
      titleTooltip: 'List of all active sidechains with accompanying balance, and all empty slots where future sidechains will be added',
      subtitle: viewModel._enforcerRPC.initializingBinary
          ? 'Enforcer is initializing...'
          : viewModel.canStartSidechains
          ? null
          : 'This platform has no sidechain build.',
      error: viewModel._enforcerRPC.initializingBinary ? null : error,
      bottomPadding: false,
      widgetHeaderEnd: smallVersion || phone
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(width: 200, child: search),
                const SizedBox(width: SailStyleValues.padding12),
                addRemove,
              ],
            ),
      child: phone && !smallVersion
          ? SailColumn(
              spacing: SailStyleValues.padding12,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                SailRow(
                  spacing: SailStyleValues.padding12,
                  children: [
                    Expanded(child: search),
                    addRemove,
                  ],
                ),
                table,
              ],
            )
          : table,
    );
  }
}

/// The rows of the sidechains table, in order.
@visibleForTesting
List<SidechainTableRow> sidechainTableRows({
  required List<SidechainOverview?> sidechains,
  required bool Function(int slot) isYours,
  required bool emptySlotsOpen,
  required String query,
}) {
  final needle = query.trim().toLowerCase();
  bool matches(int slot) {
    if (needle.isEmpty) {
      return true;
    }
    final title = sidechains[slot]?.info.title.toLowerCase() ?? '';
    return '$slot'.contains(needle) || title.contains(needle);
  }

  final filled = [
    for (var slot = 0; slot < sidechains.length; slot++)
      if (sidechains[slot] != null && matches(slot)) slot,
  ];
  final empty = [
    for (var slot = 0; slot < sidechains.length; slot++)
      if (sidechains[slot] == null && matches(slot)) slot,
  ];
  final yours = filled.where(isYours).toList();
  final others = filled.where((slot) => !isYours(slot)).toList();

  return [
    if (yours.isNotEmpty) ...[
      const GroupLabelRow('Your sidechains'),
      for (final slot in yours) SlotRow(slot),
      if (others.isNotEmpty) const GroupLabelRow('Other slots'),
    ],
    for (final slot in others) SlotRow(slot),
    if (empty.isNotEmpty) ...[
      EmptySlotsRow(empty, open: emptySlotsOpen),
      if (emptySlotsOpen)
        for (final slot in empty) SlotRow(slot),
    ],
  ];
}

/// Slot numbers with each run of three or more as a range, such as "0, 1, 3, 5–8".
@visibleForTesting
String slotRanges(List<int> slots) {
  final parts = <String>[];
  var start = 0;
  while (start < slots.length) {
    var end = start;
    while (end + 1 < slots.length && slots[end + 1] == slots[end] + 1) {
      end++;
    }
    if (end - start >= 2) {
      parts.add('${slots[start]}–${slots[end]}');
    } else {
      for (var i = start; i <= end; i++) {
        parts.add('${slots[i]}');
      }
    }
    start = end + 1;
  }
  return parts.join(', ');
}

/// One row of the sidechains table.
sealed class SidechainTableRow {
  const SidechainTableRow();

  String get id;
}

/// The row of one slot, filled or empty.
class SlotRow extends SidechainTableRow {
  final int slot;

  const SlotRow(this.slot);

  @override
  String get id => '$slot';
}

/// A group title, such as "Your sidechains".
class GroupLabelRow extends SidechainTableRow {
  final String title;

  const GroupLabelRow(this.title);

  @override
  String get id => 'group:$title';
}

/// The one row that stands for every empty slot. A tap shows or hides them.
class EmptySlotsRow extends SidechainTableRow {
  static const String rowId = 'empty';

  final List<int> slots;
  final bool open;

  const EmptySlotsRow(this.slots, {required this.open});

  @override
  String get id => rowId;
}

const double _tileSize = 28;
const double _slotColumnWidth = SailStyleValues.padding08 + _tileSize + SailStyleValues.padding12 + 40;
const double _phoneSlotColumnWidth = 48;
const EdgeInsets _slotHeaderPadding = EdgeInsets.only(left: SailStyleValues.padding08 + _tileSize + 12, right: 8);
const EdgeInsets _cellPadding = EdgeInsets.symmetric(horizontal: SailStyleValues.padding08);

/// Height of the deposits and withdrawals tabs under the slot table on a phone.
const double _phoneDepositsHeight = 280;

/// The slot table. A row click selects the sidechain for the panel.
class SidechainsTable extends ViewModelWidget<SidechainsViewModel> {
  const SidechainsTable({super.key});

  @override
  Widget build(BuildContext context, SidechainsViewModel viewModel) {
    final formatter = GetIt.I<FormatterProvider>();
    final rows = sidechainTableRows(
      sidechains: viewModel.sidechains,
      isYours: viewModel.isYourSidechain,
      emptySlotsOpen: !viewModel.showOnlyFilled,
      query: viewModel.searchController.text,
    );
    final phone = SailStyleValues.phoneLayout(context);
    final textScale = max(1.0, MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 2).scale(12) / 12);
    final rowHeight = 48 * textScale;
    final walletHeaderWidth = _walletHeaderWidth(context, viewModel.loadedWallet);

    final table = ListenableBuilder(
      listenable: formatter,
      builder: (context, child) => SailTable(
        getRowId: (index) => rows[index].id,
        cellHeight: rowHeight,
        shrinkWrap: phone,
        phoneColumns: const [0, 1, 3],
        resizableColumns: false,
        minColumnWidths: {4: walletHeaderWidth},
        headerBuilder: (context) => [
          SailTableHeaderCell(
            name: 'Slot',
            padding: phone ? _cellPadding : _slotHeaderPadding,
            sortable: false,
          ),
          const SailTableHeaderCell(name: 'Sidechain', padding: _cellPadding, sortable: false),
          const SailTableHeaderCell(name: 'Status', padding: _cellPadding, sortable: false),
          const SailTableHeaderCell(
            name: 'Sidechain balance',
            padding: _cellPadding,
            alignment: Alignment.centerRight,
            sortable: false,
          ),
          _LoadedWalletHeader(wallet: viewModel.loadedWallet),
        ],
        rowBuilder: (context, row, selected) => switch (rows[row]) {
          SlotRow(:final slot) => _slotCells(context, viewModel, formatter, slot),
          final GroupLabelRow label => _labelCells(context, label),
          final EmptySlotsRow empty => _emptySlotsCells(context, empty),
        },
        rowCount: rows.length,
        emptyPlaceholder: 'No active sidechains',
        selectedRowId: viewModel.selectedIndex?.toString(),
        onSelectedRow: (rowId) {
          if (rowId == EmptySlotsRow.rowId) {
            viewModel.setShowOnlyFilled(!viewModel.showOnlyFilled);
            return;
          }
          if (rowId == null) {
            viewModel.clearSelection();
            return;
          }
          final slot = int.tryParse(rowId);
          if (slot == null || viewModel.sidechains[slot] == null) {
            viewModel.restoreSelection();
            return;
          }
          viewModel.selectSlot(slot);
        },
        onRowTap: phone
            ? (rowId) {
                final slot = int.tryParse(rowId);
                final sidechain = slot == null ? null : viewModel.sidechains[slot];
                if (slot != null && sidechain != null) {
                  unawaited(showDepositModal(context, slot, sidechain.info.title));
                }
              }
            : null,
        onDoubleTap: (rowId) {
          final slot = int.tryParse(rowId);
          final sidechain = slot == null ? null : viewModel.sidechains[slot];
          if (sidechain == null || sidechain.info.chaintipTxid == '') {
            return;
          }
          showTransactionDetails(context, sidechain.info.chaintipTxid);
        },
        rowHasMenu: (rowId) {
          final slot = int.tryParse(rowId);
          return slot != null && viewModel.sidechains[slot] != null;
        },
        contextMenuItems: (rowId) {
          final slot = int.tryParse(rowId);
          if (slot == null) {
            return [];
          }
          return viewModel.menuItems(context, slot);
        },
      ),
    );
    return table;
  }

  double _walletHeaderWidth(BuildContext context, WalletData? wallet) {
    final painter = TextPainter(
      text: TextSpan(
        text: wallet?.name ?? 'Your balance',
        style: SailStyleValues.twelve.copyWith(
          fontFamily: context.sailTheme.chrome.textFamily(),
          fontWeight: SailStyleValues.boldWeight,
        ),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 2),
    )..layout();
    final width = painter.width + _cellPadding.horizontal + (wallet == null ? 0 : 18) + 12;
    painter.dispose();
    return min(width, 200);
  }

  List<Widget> _slotCells(BuildContext context, SidechainsViewModel viewModel, FormatterProvider formatter, int slot) {
    final colors = context.sailTheme.colors;
    final phone = SailStyleValues.phoneLayout(context);
    final overview = viewModel.sidechains[slot];
    final binary = viewModel.sidechainForSlot(slot);
    final slotCell = SailTableCell(
      value: '$slot',
      width: phone ? _phoneSlotColumnWidth : _slotColumnWidth,
      padding: _cellPadding,
      textColor: colors.textSecondary,
      child: phone
          ? null
          : Row(
              children: [
                if (overview == null) const SizedBox(width: _tileSize) else SidechainIconTile(chain: binary),
                const SizedBox(width: SailStyleValues.padding12),
                SailText.primary13('$slot', color: overview == null ? colors.textSecondary : colors.text),
              ],
            ),
    );

    if (overview == null) {
      return [
        slotCell,
        const SailTableCell(value: '', padding: _cellPadding, fill: true),
        const SailTableCell(value: '', padding: _cellPadding, hugContent: true),
        const SailTableCell(value: '', padding: _cellPadding, hugContent: true),
        const SailTableCell(value: '', padding: _cellPadding, hugContent: true),
      ];
    }

    final version = binary == null ? null : sidechainVersionLabel(binary);
    final status = viewModel.statusFor(slot);
    final balanceSats = overview.info.balanceSatoshi.toInt();
    final unit = formatter.currentUnit;
    final yourBalance = viewModel.yourBalance(slot);
    final yourAmount = yourBalance == null ? null : phoneHistoryAmount(btcToSatoshi(yourBalance.confirmed), unit);

    return [
      slotCell,
      SailTableCell(
        value: overview.info.title,
        secondaryValue: phone ? null : version,
        padding: _cellPadding,
        fill: true,
        child: viewModel.hasExternalWallet(slot)
            ? Row(
                children: [
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SailText.primary13(overview.info.title, maxLines: 1),
                        if (version != null && !phone) SailText.secondary12(version),
                      ],
                    ),
                  ),
                  const SizedBox(width: SailStyleValues.padding08),
                  const _ExternalWalletBadge(),
                ],
              )
            : null,
      ),
      SailTableCell(
        value: status == null ? '' : '${status.label}  ${status.detail ?? ''}',
        padding: _cellPadding,
        hugContent: true,
        child: status == null ? null : SidechainStatusCell(status: status),
      ),
      SailTableCell(
        value: phoneHistoryAmount(balanceSats, unit),
        secondaryValue: phone ? null : unit.symbol,
        padding: _cellPadding,
        hugContent: !phone,
        fill: phone,
        alignment: Alignment.centerRight,
        child: switch (phone ? viewModel.appRunButton(slot) : null) {
          final button? => Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Flexible(child: SailText.primary13(phoneHistoryAmount(balanceSats, unit), maxLines: 1)),
              const SizedBox(width: SailStyleValues.padding08),
              SailButton(
                label: button.label,
                variant: ButtonVariant.secondary,
                small: true,
                insideTable: true,
                loading: button.run == null,
                onPressed: button.run,
              ),
            ],
          ),
          null => null,
        },
      ),
      SailTableCell(
        value: yourAmount ?? '—',
        secondaryValue: yourAmount == null ? null : unit.symbol,
        padding: _cellPadding,
        hugContent: true,
        alignment: Alignment.centerRight,
        textColor: yourAmount == null ? colors.textSecondary : colors.text,
        child: yourBalance == null || yourBalance.pending == 0
            ? null
            : SailTooltip(
                message: 'Pending ${formatter.formatBTC(yourBalance.pending)}',
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    SailText.primary13(yourAmount!, color: colors.text),
                    SailText.secondary12(unit.symbol),
                  ],
                ),
              ),
      ),
    ];
  }

  List<Widget> _labelCells(BuildContext context, GroupLabelRow label) => [
    SailTableCell(
      value: '',
      width: SailStyleValues.phoneLayout(context) ? _phoneSlotColumnWidth : _slotColumnWidth,
      padding: _cellPadding,
      // The label spans the row, past the narrow slot column.
      child: OverflowBox(
        alignment: Alignment.bottomLeft,
        maxWidth: double.infinity,
        child: Padding(
          padding: const EdgeInsets.only(bottom: SailStyleValues.padding08),
          child: SailText.primary12(label.title, bold: true, color: context.sailTheme.colors.textSecondary),
        ),
      ),
    ),
    const SailTableCell(value: '', padding: _cellPadding, fill: true),
    const SailTableCell(value: '', padding: _cellPadding, hugContent: true),
    const SailTableCell(value: '', padding: _cellPadding, hugContent: true),
    const SailTableCell(value: '', padding: _cellPadding, hugContent: true),
  ];

  List<Widget> _emptySlotsCells(BuildContext context, EmptySlotsRow row) {
    final colors = context.sailTheme.colors;
    final phone = SailStyleValues.phoneLayout(context);
    final count = row.slots.length;
    return [
      SailTableCell(
        value: '',
        width: phone ? _phoneSlotColumnWidth : _slotColumnWidth,
        padding: _cellPadding,
        child: Row(
          children: [
            if (!phone) ...[const SidechainIconTile.emptySlots(), const SizedBox(width: SailStyleValues.padding12)],
            Expanded(
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                maxWidth: double.infinity,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SailText.primary13(count == 1 ? '1 empty slot' : '$count empty slots'),
                    SailText.secondary12(slotRanges(row.slots)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      const SailTableCell(value: '', padding: _cellPadding, fill: true),
      const SailTableCell(value: '', padding: _cellPadding, hugContent: true),
      const SailTableCell(value: '', padding: _cellPadding, hugContent: true),
      SailTableCell(
        value: '',
        padding: _cellPadding,
        hugContent: true,
        alignment: Alignment.centerRight,
        child: KeyedSubtree(
          key: const ValueKey('empty_slots_chevron'),
          child: SailSVG.fromAsset(
            row.open ? SailSVGAsset.chevronDown : SailSVGAsset.chevronRight,
            width: 14,
            height: 14,
            color: colors.textSecondary,
          ),
        ),
      ),
    ];
  }
}

/// The version of [chain] as the table shows it, or null when the release has no number.
String? sidechainVersionLabel(Binary chain) {
  final version = chain.version;
  if (version.isEmpty || int.tryParse(version[0]) == null) {
    return null;
  }
  return 'v$version';
}

/// A square in the brand color of [chain] with its icon. A null chain, as in a slot with no binary, draws a grey tile.
class SidechainIconTile extends StatelessWidget {
  final Binary? chain;
  final double size;

  /// True draws the tile of the empty slots row.
  final bool emptySlots;

  const SidechainIconTile({super.key, required this.chain, this.size = _tileSize}) : emptySlots = false;

  const SidechainIconTile.emptySlots({super.key, this.size = _tileSize}) : chain = null, emptySlots = true;

  static SailSVGAsset iconFor(Binary? chain) => switch (chain) {
    Thunder() => SailSVGAsset.zap,
    BitNames() => SailSVGAsset.atSign,
    BitAssets() => SailSVGAsset.gem,
    Truthcoin() => SailSVGAsset.scale,
    ZSide() => SailSVGAsset.shield,
    Photon() => SailSVGAsset.layers,
    CoinShift() => SailSVGAsset.arrowRightLeft,
    Sidepot() => SailSVGAsset.spade,
    _ => SailSVGAsset.blocks,
  };

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    final chain = this.chain;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: chain == null ? theme.colors.secondaryButtonBackground : chain.color,
        borderRadius: theme.chrome.radius,
      ),
      child: SailSVG.fromAsset(
        emptySlots ? SailSVGAsset.boxes : iconFor(chain),
        width: size / 2,
        height: size / 2,
        color: chain == null ? theme.colors.text : const Color(0xFFFFFFFF),
      ),
    );
  }
}

/// The state of a sidechain node, for the Status column and the panel.
class SidechainStatus {
  final String label;
  final String? detail;
  final SailStatusTone tone;

  const SidechainStatus(this.label, {this.detail, this.tone = SailStatusTone.neutral});

  String get pillLabel => detail == null ? label : '$label · $detail';
}

/// A status dot, the state and its detail under it.
class SidechainStatusCell extends StatelessWidget {
  final SidechainStatus status;

  const SidechainStatusCell({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final detail = status.detail;
    final cell = Row(
      crossAxisAlignment: detail == null ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: detail == null ? 0 : 6),
          child: SailStatusDot(tone: status.tone),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SailText.primary13(status.label, maxLines: 1),
              if (detail != null) SailText.secondary12(detail),
            ],
          ),
        ),
      ],
    );
    return detail != null && status.tone == SailStatusTone.error ? SailTooltip(message: detail, child: cell) : cell;
  }
}

/// The detail card of the selected sidechain.
class SidechainPanel extends ViewModelWidget<SidechainsViewModel> {
  const SidechainPanel({super.key});

  @override
  Widget build(BuildContext context, SidechainsViewModel viewModel) {
    final slot = viewModel.selectedIndex;
    final overview = slot == null ? null : viewModel.sidechains[slot];
    if (slot == null || overview == null) {
      return const SizedBox.shrink();
    }
    final formatter = GetIt.I<FormatterProvider>();
    final binary = viewModel.sidechainForSlot(slot);
    final title = overview.info.title;
    final wallet = viewModel.loadedWallet;
    final balance = viewModel.yourBalance(slot);
    final status = viewModel.statusFor(slot);
    final primary = viewModel.primaryAction(context, slot);
    final version = binary == null ? null : sidechainVersionLabel(binary);
    final bundle = overview.withdrawals.firstOrNull;

    return SailSidePanel(
      key: ValueKey('sidechain_panel_$slot'),
      title: title,
      lead: SidechainIconTile(chain: binary),
      menuItems: () => viewModel.menuItems(context, slot),
      onClose: () async => viewModel.clearSelection(),
      child: ListenableBuilder(
        listenable: formatter,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SailText.secondary12(wallet == null ? 'In $title' : 'In $title, ${wallet.name}'),
            const SizedBox(height: 2),
            SailText.primary24(balance == null ? '—' : formatter.formatBTC(balance.confirmed), bold: true),
            if (balance != null && balance.pending != 0)
              SailText.secondary13('Pending ${formatter.formatBTC(balance.pending)}'),
            if (status != null) ...[
              const SizedBox(height: SailStyleValues.padding12),
              Align(
                alignment: Alignment.centerLeft,
                child: SailStatusPill(label: status.pillLabel, tone: status.tone),
              ),
            ],
            const SizedBox(height: SailStyleValues.padding16),
            SailButton(
              key: ValueKey('sidechain_panel_primary_$slot'),
              label: primary.label,
              loading: primary.loading,
              onPressed: primary.run,
            ),
            const SizedBox(height: SailStyleValues.padding20),
            SailText.primary13('Details', bold: true),
            const SizedBox(height: SailStyleValues.padding08),
            SailDetailGroup(
              children: [
                SailDetailLine(label: 'Slot', value: '$slot'),
                if (version != null) SailDetailLine(label: 'Version', value: version),
                SailDetailLine(
                  label: 'Sidechain balance',
                  value: formatter.formatSats(overview.info.balanceSatoshi.toInt()),
                ),
                SailDetailLine(label: 'Withdrawal bundle', value: bundle == null ? 'None pending' : bundle.status),
              ],
            ),
            const SizedBox(height: SailStyleValues.padding20),
            SidechainActivity(key: ValueKey('sidechain_activity_$slot'), overview: overview),
          ],
        ),
      ),
    );
  }
}

/// The deposits and the withdrawal bundles of one sidechain.
class SidechainActivity extends StatefulWidget {
  final SidechainOverview overview;

  const SidechainActivity({super.key, required this.overview});

  @override
  State<SidechainActivity> createState() => _SidechainActivityState();
}

class _SidechainActivityState extends State<SidechainActivity> {
  var _withdrawals = false;

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    final formatter = GetIt.I<FormatterProvider>();
    final deposits = widget.overview.deposits;
    final bundles = widget.overview.withdrawals;

    final rows = _withdrawals
        ? [
            for (final bundle in bundles)
              _ActivityLine(
                title: shortId(bundle.m6id),
                subtitle: 'Block ${bundle.blockHeight}',
                value: bundle.status,
                valueSubtitle: bundle.sequenceNumber.toInt() > 0 ? 'Sequence # ${bundle.sequenceNumber}' : null,
              ),
          ]
        : [
            for (final deposit in deposits)
              _ActivityLine(
                title: shortId(deposit.txid),
                subtitle: 'Fee ${formatter.formatSats(deposit.fee.toInt())}',
                value: formatter.formatSats(deposit.amount.toInt()),
                valueSubtitle: deposit.dropped ? 'Dropped — deposit again' : '${deposit.confirmations} conf.',
                onTap: () => showTransactionDetails(context, deposit.txid),
              ),
          ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: SailText.primary13('Activity', bold: true)),
            SidechainSegments(
              labels: const ['Deposits', 'Withdrawals'],
              activeIndex: _withdrawals ? 1 : 0,
              onSelect: (index) => setState(() => _withdrawals = index == 1),
            ),
          ],
        ),
        const SizedBox(height: SailStyleValues.padding08),
        SailDetailGroup(
          children: rows.isEmpty
              ? [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: SailStyleValues.padding08),
                    child: SailText.secondary13(
                      _withdrawals ? 'No withdrawal bundles found for this sidechain' : 'No deposits yet',
                    ),
                  ),
                ]
              : [
                  for (final (index, row) in rows.indexed) ...[
                    if (index > 0) Container(height: 1, color: theme.colors.divider),
                    row,
                  ],
                ],
        ),
      ],
    );
  }
}

/// A segmented control: one segment per label, the active one raised.
class SidechainSegments extends StatelessWidget {
  final List<String> labels;
  final int activeIndex;
  final void Function(int index) onSelect;

  const SidechainSegments({super.key, required this.labels, required this.activeIndex, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(color: theme.colors.formField, borderRadius: theme.chrome.radius),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (index, label) in labels.indexed)
              SailTappable(
                onTap: () async => onSelect(index),
                borderRadius: theme.chrome.radiusSmall,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: SailStyleValues.padding12, vertical: 6),
                  decoration: BoxDecoration(
                    color: index == activeIndex ? theme.colors.backgroundSecondary : null,
                    borderRadius: theme.chrome.radiusSmall,
                  ),
                  child: SailText.primary13(
                    label,
                    bold: index == activeIndex,
                    color: index == activeIndex ? theme.colors.text : theme.colors.textSecondary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The first and last four characters of a txid or an M6 id.
@visibleForTesting
String shortId(String id) => id.length <= 11 ? id : '${id.substring(0, 4)}…${id.substring(id.length - 4)}';

class _ActivityLine extends StatelessWidget {
  final String title;
  final String subtitle;
  final String value;
  final String? valueSubtitle;
  final VoidCallback? onTap;

  const _ActivityLine({
    required this.title,
    required this.subtitle,
    required this.value,
    this.valueSubtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final valueSubtitle = this.valueSubtitle;
    final line = Padding(
      padding: const EdgeInsets.symmetric(vertical: SailStyleValues.padding08),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [SailText.primary13(title), SailText.secondary12(subtitle)],
            ),
          ),
          const SizedBox(width: SailStyleValues.padding12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [SailText.primary13(value), if (valueSubtitle != null) SailText.secondary12(valueSubtitle)],
          ),
        ],
      ),
    );
    if (onTap == null) {
      return line;
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: line),
    );
  }
}

Future<void> _togglePin(BuildContext context, SidechainsViewModel viewModel, int slot) async {
  try {
    await viewModel.togglePin(slot);
  } catch (error) {
    if (context.mounted) {
      showSailToast(context, 'Could not save the pin: $error', variant: SailToastVariant.destructive);
    }
  }
}

/// The balance column header: the wallet the sidechains hold.
class _LoadedWalletHeader extends StatelessWidget {
  final WalletData? wallet;

  const _LoadedWalletHeader({required this.wallet});

  @override
  Widget build(BuildContext context) {
    final wallet = this.wallet;
    return Container(
      width: double.infinity,
      padding: _cellPadding,
      alignment: Alignment.centerRight,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (wallet != null) ...[
            WalletBlobAvatar(gradient: wallet.gradient, size: 12),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: SailText.primary12(
              wallet?.name ?? 'Your balance',
              bold: true,
              color: context.sailTheme.colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Marks a sidechain that keeps aside a wallet no BitWindow wallet made.
class _ExternalWalletBadge extends StatelessWidget {
  static const label = 'External wallet';
  static const padding = EdgeInsets.symmetric(horizontal: 6, vertical: 2);

  const _ExternalWalletBadge();

  @override
  Widget build(BuildContext context) {
    return SailTooltip(
      message: 'This sidechain keeps a wallet that BitWindow did not make. It stays on disk.',
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          border: Border.all(color: context.sailTheme.colors.border),
          borderRadius: context.sailTheme.chrome.radiusSmall,
        ),
        child: SailText.secondary12(label),
      ),
    );
  }
}

/// One way to start a sidechain, in the row menu.
class _StartOption {
  final String title;
  final Future<void> Function() onSelected;

  const _StartOption({required this.title, required this.onSelected});
}

/// Whole percent done, never 100% before the goal; a dash when the goal is unknown.
@visibleForTesting
String progressPercent(double current, double goal) {
  if (goal <= 0) {
    return '—';
  }
  final percent = min((current * 100 / goal).floor(), 100);
  return current < goal ? '${min(percent, 99)}%' : '$percent%';
}

/// Slot numbers the user pinned to the top of the sidechains table.
class PinnedSidechainsSetting extends SettingValue<List<int>> {
  @override
  String get key => 'pinned_sidechain_slots';

  PinnedSidechainsSetting({super.newValue});

  @override
  List<int> defaultValue() => [];

  @override
  List<int>? fromJson(String jsonString) {
    try {
      return [for (final slot in json.decode(jsonString) as List) slot as int];
    } catch (e) {
      return null;
    }
  }

  @override
  String toJson() => json.encode(value);

  @override
  SettingValue<List<int>> withValue([List<int>? value]) => PinnedSidechainsSetting(newValue: value);
}

class SidechainsViewModel extends BaseViewModel with ChangeTrackingMixin {
  final ClientSettings _settings = GetIt.I.get<ClientSettings>();
  final SettingsProvider _settingsProvider = GetIt.I.get<SettingsProvider>();

  /// Opens a sidechain inside BitWindow.
  final Future<void> Function(Sidechain chain) openHere;
  final BalanceProvider _balanceProvider = GetIt.I.get<BalanceProvider>();
  final SidechainProvider _sidechainProvider = GetIt.I.get<SidechainProvider>();
  final EnforcerRPC _enforcerRPC = GetIt.I.get<EnforcerRPC>();
  final BinaryProvider _binaryProvider = GetIt.I.get<BinaryProvider>();
  final BitcoinConfProvider _confProvider = GetIt.I.get<BitcoinConfProvider>();
  final SyncProvider _syncProvider = GetIt.I.get<SyncProvider>();
  final NodeModeProvider? _nodeMode = GetIt.I.isRegistered<NodeModeProvider>() ? GetIt.I.get<NodeModeProvider>() : null;
  DownloadProvider? get _downloadProvider =>
      GetIt.I.isRegistered<DownloadProvider>() ? GetIt.I.get<DownloadProvider>() : null;
  WalletReaderProvider get _walletReader => GetIt.I<WalletReaderProvider>();

  // Resolve a Sidechain Binary to its SidechainType enum (key into
  // SyncProvider.sidechains). bitwindowd is intentionally absent — the
  // orchestrator doesn't manage it, so it never shows up there.
  SidechainType? _sidechainType(Binary b) => switch (b) {
    Thunder() => SidechainType.SIDECHAIN_TYPE_THUNDER,
    ZSide() => SidechainType.SIDECHAIN_TYPE_ZSIDE,
    BitNames() => SidechainType.SIDECHAIN_TYPE_BITNAMES,
    BitAssets() => SidechainType.SIDECHAIN_TYPE_BITASSETS,
    Truthcoin() => SidechainType.SIDECHAIN_TYPE_TRUTHCOIN,
    Photon() => SidechainType.SIDECHAIN_TYPE_PHOTON,
    CoinShift() => SidechainType.SIDECHAIN_TYPE_COINSHIFT,
    Sidepot() => SidechainType.SIDECHAIN_TYPE_SIDEPOT,
    _ => null,
  };

  DownloadProgress? _downloadProgressFor(Binary b) => _downloadProvider?.statusFor(b.type);

  bool _isDownloadingFor(Binary b) => _downloadProgressFor(b) != null;

  SyncInfo? _syncInfoFor(Binary b) {
    final type = _sidechainType(b);
    if (type == null) {
      return null;
    }
    return _syncProvider.sidechains[type];
  }

  SidechainsViewModel({this.openHere = openSidechainHere}) {
    initChangeTracker();
    searchController.addListener(notifyListeners);
    _settingsProvider.addListener(notifyListeners);
    unawaited(_loadPinnedSlots());

    _sidechainProvider.addListener(_onChange);
    _sidechainProvider.fetch();

    _walletReader.addListener(_onChange);
    _nodeMode?.addListener(_onChange);
    _balanceProvider.addListener(notifyListeners);

    _binaryProvider.addListener(_onChange);
    _binaryProvider.addListener(notifyListeners);
    _syncProvider.addListener(_onChange);
    _syncProvider.addListener(notifyListeners);
    // DownloadProvider polls every 100ms while downloads are active. Without
    // this listener the table never rebuilds during a download, so progress
    // never advances and the button doesn't flip from "Download" → "Start"
    // until the user touches the row.
    _downloadProvider?.addListener(_onChange);
    // _onChange only fires notifyListeners on start/stop transitions because
    // mbDownloaded isn't in the tracked binaryStates map — so without this
    // direct hook the in-flight progress bar never repaints (#1728). Cheap:
    // active downloads only, and the rebuild reads o(1) provider state.
    _downloadProvider?.addListener(notifyListeners);
  }

  bool get loading => _enforcerRPC.initializingBinary;

  bool get localBuildsAvailable => _nodeMode?.localBuildsAvailable ?? true;

  /// True when this device can start a sidechain, from a local build or in the app process.
  bool get canStartSidechains =>
      localBuildsAvailable || _binaryProvider.binaries.whereType<Sidechain>().any(_runsInApp);

  /// Networks that serve sidechains in light mode.
  List<String> get remoteEnforcerNetworks => _nodeMode?.remoteEnforcerNetworks ?? const [];

  /// The connection state before the tab can read BIP300 data.
  L1Gate get l1Gate => resolveL1Gate(
    walletNeedsBackends: NodeModeProvider.runsLocalBackends,
    remoteEnforcerAvailable: _nodeMode?.remoteEnforcerAvailable ?? false,
    coreConnected: _binaryProvider.isConnected(BitcoinCore()),
    enforcerConnected: _binaryProvider.isConnected(Enforcer()),
    coming:
        _binaryProvider.isInitializing(BitcoinCore()) ||
        _binaryProvider.isInitializing(Enforcer()) ||
        _isDownloadingFor(BitcoinCore()) ||
        _isDownloadingFor(Enforcer()),
    synced: NodeModeProvider.runsLocalBackends
        ? _syncProvider.isSynced
        : (_syncProvider.enforcerSyncInfo?.isSynced ?? false),
    chainIsEmpty: _regtestChainIsEmpty,
  );

  /// Regtest alone can legitimately sit at height 0 with nothing to sync from.
  /// Any reported height means it is catching up like any other chain — and an
  /// absent or failed sample is unknown, not empty, so it never opens the tab.
  bool get _regtestChainIsEmpty {
    if (_confProvider.network != BitcoinNetwork.BITCOIN_NETWORK_REGTEST) {
      return false;
    }
    if (_syncProvider.mainchainError != null || _syncProvider.enforcerError != null) {
      return false;
    }
    final mainchain = _syncProvider.mainchainSyncInfo;
    final enforcer = _syncProvider.enforcerSyncInfo;
    if (mainchain == null || enforcer == null) {
      return false;
    }
    return mainchain.progressGoal == 0 &&
        mainchain.progressCurrent == 0 &&
        enforcer.progressGoal == 0 &&
        enforcer.progressCurrent == 0;
  }

  RPCConnection get mainchainConnection => GetIt.I.get<BitcoindConnection>();
  RPCConnection get enforcerConnection => _enforcerRPC;

  SyncInfo? get mainchainSyncInfo => _syncProvider.mainchainSyncInfo;
  SyncInfo? get enforcerSyncInfo => _syncProvider.enforcerSyncInfo;

  /// The enforcer boots behind Core and reports 0/0 until headers land, which
  /// reads as a fault unless we say what it is waiting for.
  String? get enforcerInfoMessage {
    if (mainchainConnection.initializingBinary) {
      return 'Waiting for mainchain to finish initializing';
    }
    if (_syncProvider.inHeaderSync) {
      return 'Waiting for L1 to sync headers...';
    }
    return null;
  }

  Binary _binaryFor(Binary binary) =>
      _binaryProvider.binaries.firstWhere((b) => b.name == binary.name, orElse: () => binary);

  Future<void> restartDaemon(Binary binary) => _binaryProvider.restart(_binaryFor(binary));

  Future<void> stopDaemon(Binary binary) => _binaryProvider.stop(_binaryFor(binary));

  Future<void> startL1() async {
    // Starting the enforcer boots the whole L1 chain: Core first, then this.
    await _binaryProvider.start(_binaryFor(Enforcer()));
  }

  /// The daemon cards enable "View logs" on their own and then call this
  /// unconditionally, so it has to be supplied wherever a card is rendered.
  void navigateToLogs(String title, String logPath, BinaryType binaryType) =>
      unawaited(openLogWindow(title, logPath, binaryType));

  /// Check if current network supports sidechains (L2L networks only)
  bool get networkSupportsSidechains {
    final network = _confProvider.network;
    return network == BitcoinNetwork.BITCOIN_NETWORK_ECASH ||
        network == BitcoinNetwork.BITCOIN_NETWORK_SIGNET ||
        network == BitcoinNetwork.BITCOIN_NETWORK_REGTEST;
  }

  /// True when no local enforcer runs, so nothing can add, remove or withdraw.
  /// Reading chains, chain settings and deposits all work without one.
  bool get sidechainManagementUnavailable => !NodeModeProvider.runsLocalBackends;

  List<SidechainOverview?> get sidechains => _sidechainProvider.sidechains;

  /// True folds the empty slots into one row.
  bool showOnlyFilled = true;

  final TextEditingController searchController = TextEditingController();
  void setShowOnlyFilled(bool value) {
    showOnlyFilled = value;
    notifyListeners();
  }

  Set<int> _pinnedSlots = {};

  bool isPinned(int slot) => _pinnedSlots.contains(slot);

  /// True when [slot] holds a sidechain that the user pinned, or that holds coins of the loaded wallet.
  bool isYourSidechain(int slot) {
    if (sidechains[slot] == null) {
      return false;
    }
    if (isPinned(slot)) {
      return true;
    }
    final balance = yourBalance(slot);
    return balance != null && (balance.confirmed > 0 || balance.pending > 0);
  }

  Future<void> _loadPinnedSlots() async {
    final setting = await _settings.getValue(PinnedSidechainsSetting());
    _pinnedSlots = setting.value.toSet();
    notifyListeners();
  }

  Future<void> togglePin(int slot) async {
    final setting = await _settings.mergeValue(
      PinnedSidechainsSetting(),
      (current) => current.contains(slot) ? [...current.where((pinned) => pinned != slot)] : [...current, slot],
    );
    _pinnedSlots = setting.value.toSet();
    notifyListeners();
  }

  Sidechain? sidechainForSlot(int slot) {
    return _binaryProvider.binaries.firstWhereOrNull((b) => b is Sidechain && b.slot == slot) as Sidechain?;
  }

  RPCConnection? rpcForSlot(int slot) {
    final sidechain = sidechainForSlot(slot);
    if (sidechain == null) {
      return null;
    }

    // Check if binary is running
    final rpc = switch (sidechain) {
      var b when b is BitcoinCore =>
        GetIt.I.isRegistered<BitcoindConnection>() ? GetIt.I.get<BitcoindConnection>() : null,
      var b when b is Enforcer => GetIt.I.isRegistered<EnforcerRPC>() ? GetIt.I.get<EnforcerRPC>() : null,
      var b when b is BitWindow => GetIt.I.isRegistered<BitwindowRPC>() ? GetIt.I.get<BitwindowRPC>() : null,
      var b when b is Thunder => GetIt.I.isRegistered<ThunderRPC>() ? GetIt.I.get<ThunderRPC>() : null,
      var b when b is BitNames => GetIt.I.isRegistered<BitnamesRPC>() ? GetIt.I.get<BitnamesRPC>() : null,
      var b when b is BitAssets => GetIt.I.isRegistered<BitAssetsRPC>() ? GetIt.I.get<BitAssetsRPC>() : null,
      var b when b is ZSide => GetIt.I.isRegistered<ZSideRPC>() ? GetIt.I.get<ZSideRPC>() : null,
      var b when b is Truthcoin => GetIt.I.isRegistered<TruthcoinRPC>() ? GetIt.I.get<TruthcoinRPC>() : null,
      var b when b is Photon => GetIt.I.isRegistered<PhotonRPC>() ? GetIt.I.get<PhotonRPC>() : null,
      var b when b is CoinShift => GetIt.I.isRegistered<CoinShiftRPC>() ? GetIt.I.get<CoinShiftRPC>() : null,
      var b when b is Sidepot => GetIt.I.isRegistered<SidepotRPC>() ? GetIt.I.get<SidepotRPC>() : null,
      _ => null,
    };

    return rpc;
  }

  /// Returns names of sidechains with hash mismatches, formatted for display.
  String? get hashMismatchWarning {
    final mismatched = <String>[];
    for (final binary in _binaryProvider.binaries) {
      if (binary.downloadInfo.hashMatch == false) {
        mismatched.add(binary.name);
      }
    }
    if (mismatched.isEmpty) {
      return null;
    }
    if (mismatched.length == 1) {
      return mismatched.first;
    }
    final last = mismatched.removeLast();
    return '${mismatched.join(', ')} and $last';
  }

  /// The user's wallet balance in BTC on the chain in [slot], or null while the chain does not run.
  ({double confirmed, double pending})? yourBalance(int slot) {
    final rpc = _sidechainRPC(slot);
    if (rpc == null || !rpc.connected || !_balanceProvider.connections.contains(rpc)) {
      return null;
    }
    final (confirmed, pending) = _balanceProvider.balanceFor(rpc);
    return (confirmed: confirmed, pending: pending);
  }

  bool isSidechainRunning(int slot) => _sidechainRPC(slot)?.connected ?? false;

  /// The wallet the running sidechains hold, else the active wallet. A stopped
  /// sidechain still names the wallet it held, but adds no balance. Null when no
  /// one BitWindow wallet holds the running balances: the sidechains hold
  /// different wallets, or one runs a wallet of its own and reports none.
  WalletData? get loadedWallet {
    final loadedIds = sidechains
        .whereType<SidechainOverview>()
        .map((s) => _sidechainRPC(s.info.slot))
        .where((rpc) => rpc != null && rpc.connected)
        .map((rpc) => rpc!.loadedWalletId)
        .toSet();
    if (loadedIds.isEmpty) {
      return _walletReader.activeWallet;
    }
    if (loadedIds.length > 1 || loadedIds.single.isEmpty) {
      return null;
    }
    return _walletReader.wallets.firstWhereOrNull((w) => w.id == loadedIds.single);
  }

  bool hasExternalWallet(int slot) => _sidechainRPC(slot)?.hasExternalWallet ?? false;

  /// The RPC connection for a slot, or null when this build has none.
  RPCConnection? _sidechainRPC(int slot) {
    final sidechain = sidechainForSlot(slot);
    if (sidechain == null) {
      return null;
    }

    return switch (sidechain) {
      var b when b is Thunder => (GetIt.I.isRegistered<ThunderRPC>() ? GetIt.I.get<ThunderRPC>() : null),
      var b when b is BitNames => (GetIt.I.isRegistered<BitnamesRPC>() ? GetIt.I.get<BitnamesRPC>() : null),
      var b when b is BitAssets => (GetIt.I.isRegistered<BitAssetsRPC>() ? GetIt.I.get<BitAssetsRPC>() : null),
      var b when b is ZSide => (GetIt.I.isRegistered<ZSideRPC>() ? GetIt.I.get<ZSideRPC>() : null),
      var b when b is Truthcoin => (GetIt.I.isRegistered<TruthcoinRPC>() ? GetIt.I.get<TruthcoinRPC>() : null),
      var b when b is Photon => (GetIt.I.isRegistered<PhotonRPC>() ? GetIt.I.get<PhotonRPC>() : null),
      var b when b is CoinShift => (GetIt.I.isRegistered<CoinShiftRPC>() ? GetIt.I.get<CoinShiftRPC>() : null),
      var b when b is Sidepot => (GetIt.I.isRegistered<SidepotRPC>() ? GetIt.I.get<SidepotRPC>() : null),
      _ => null,
    };
  }

  // Third-party sidechains aren't vetted by Layer Two Labs, so make the user
  // accept the risk before the download starts.
  Future<bool> _confirmUntrustedDownload(BuildContext context, Sidechain sidechain) async {
    final confirmed = await showThemedDialog<bool>(
      context: context,
      builder: (dialogContext) => SailAlertCard(
        title: 'Download ${sidechain.name}?',
        subtitle:
            'This sidechain was not developed by Layer Two Labs, has not been audited for security '
            'issues, and can introduce dangerous code at any time. Run this sidechain at your own risk.',
        confirmText: 'Download anyway',
        confirmButtonVariant: ButtonVariant.destructive,
        onConfirm: () async => Navigator.of(dialogContext).pop(true),
        onCancel: () async => Navigator.of(dialogContext).pop(false),
      ),
    );
    return confirmed == true;
  }

  /// The state of the node in [slot], or null when this build has no binary for it.
  SidechainStatus? statusFor(int slot) {
    final sidechain = sidechainForSlot(slot);
    if (sidechain == null) {
      return null;
    }
    final progress = _downloadProgressFor(sidechain);
    if (progress != null) {
      return SidechainStatus(
        sidechain.isDownloaded ? 'Updating' : 'Downloading',
        detail: progressPercent(
          progress.mbDownloaded.toDouble(),
          progress.mbTotal > 0 ? progress.mbTotal.toDouble() : 0,
        ),
        tone: SailStatusTone.warning,
      );
    }
    if (_binaryProvider.isStopping(sidechain)) {
      return const SidechainStatus('Stopping', tone: SailStatusTone.warning);
    }
    if (_binaryProvider.isSidechainUp(sidechain)) {
      final sync = _syncInfoFor(sidechain);
      if (sync != null && sync.mainchainSyncing) {
        final (label, _) = mainchainSyncText(sync.mainchainSyncPhase);
        final done = sync.progressCurrent;
        final total = sync.progressGoal;
        final fraction = total > 0 ? (done / total).clamp(0.0, 1.0) : 0.0;
        final percent = done < total ? min(fraction * 100, 99.9) : fraction * 100;
        return SidechainStatus(label, detail: '${percent.toStringAsFixed(1)}%', tone: SailStatusTone.warning);
      }
      if (sync != null && !sync.isSynced && sync.progressGoal > 0) {
        return SidechainStatus(
          'Syncing',
          detail: progressPercent(sync.progressCurrent, sync.progressGoal),
          tone: SailStatusTone.warning,
        );
      }
      return SidechainStatus(
        'Running',
        detail: sync != null && sync.progressCurrent > 0
            ? 'block ${formatProgress(sync.progressCurrent, false)}'
            : null,
        tone: SailStatusTone.success,
      );
    }
    if (_binaryProvider.isInitializing(sidechain)) {
      return const SidechainStatus('Starting', tone: SailStatusTone.warning);
    }
    final error = _binaryProvider.connectionError(sidechain) ?? rpcForSlot(slot)?.startupError;
    if (error != null) {
      return SidechainStatus('Not running', detail: error, tone: SailStatusTone.error);
    }
    if (!sidechain.isDownloaded) {
      return const SidechainStatus('Not downloaded');
    }
    return const SidechainStatus('Not running', detail: 'Downloaded');
  }

  /// The one main action of the panel: Deposit, Start or Download. A null run waits for the node.
  ({String label, Future<void> Function()? run, bool loading}) primaryAction(BuildContext context, int slot) {
    final title = sidechains[slot]?.info.title ?? '';
    final deposit = (label: 'Deposit', run: () => showDepositModal(context, slot, title), loading: false);
    final sidechain = sidechainForSlot(slot);
    if (sidechain == null || !(localBuildsAvailable || _runsInApp(sidechain))) {
      return deposit;
    }
    if (_binaryProvider.isSidechainUp(sidechain) || _binaryProvider.isStopping(sidechain)) {
      return deposit;
    }
    if (_binaryProvider.isInitializing(sidechain)) {
      return (label: 'Start', run: null, loading: true);
    }
    if (_isDownloadingFor(sidechain) && !sidechain.isDownloaded) {
      return (label: 'Download', run: null, loading: true);
    }
    if (!sidechain.isDownloaded) {
      return (label: 'Download', run: () => _download(context, sidechain), loading: false);
    }
    return (label: 'Start', run: () => startSidechain(sidechain), loading: false);
  }

  Future<void> _download(BuildContext context, Sidechain sidechain) async {
    if (!sidechain.developedByLayerTwoLabs && !await _confirmUntrustedDownload(context, sidechain)) {
      return;
    }
    await _binaryProvider.download(sidechain);
  }

  /// The actions of the "…" of the sidechain in [slot].
  List<SailMenuEntity> menuItems(BuildContext context, int slot) {
    final overview = sidechains[slot];
    if (overview == null) {
      return [];
    }
    final sidechain = sidechainForSlot(slot);
    final settingsConnection = rpcForSlot(slot);
    final pinned = isPinned(slot);
    SailMenuItem item(String label, Future<void> Function() run) =>
        SailMenuItem(onSelected: () => unawaited(run()), child: SailText.primary12(label));

    return [
      if (sidechain != null && localBuildsAvailable && !SailStyleValues.phoneLayout(context))
        ..._nodeItems(context, sidechain, item),
      if (SailStyleValues.phoneLayout(context)) ...appRunMenuItems(slot),
      item('Deposit', () => showDepositModal(context, slot, overview.info.title)),
      if (settingsConnection != null)
        item(
          'Settings',
          () => showThemedDialog(
            context: context,
            builder: (context) => ChainSettingsModal(connection: settingsConnection),
          ),
        ),
      item(pinned ? 'Unpin' : 'Pin to top', () => _togglePin(context, this, slot)),
      if (overview.info.chaintipTxid != '')
        item('Show Chaintip Transaction', () async => showTransactionDetails(context, overview.info.chaintipTxid)),
    ];
  }

  List<SailMenuItem> _nodeItems(
    BuildContext context,
    Sidechain sidechain,
    SailMenuItem Function(String label, Future<void> Function() run) item,
  ) {
    final up = _binaryProvider.isSidechainUp(sidechain);
    final busy =
        _binaryProvider.isInitializing(sidechain) ||
        _binaryProvider.isStopping(sidechain) ||
        _isDownloadingFor(sidechain);
    return [
      if (_offersOpenHere(sidechain)) item('Open', () => openHere(sidechain)),
      if (!_offersOpenHere(sidechain) && _offersOpenWindow(sidechain))
        item('Open window', () => _binaryProvider.start(sidechain)),
      if (!up && !busy && !sidechain.isDownloaded) item('Download', () => _download(context, sidechain)),
      if (!up && !busy && sidechain.isDownloaded)
        if (_offersStartMenu(sidechain))
          for (final option in _startOptions(sidechain)) item(option.title, option.onSelected)
        else
          item('Start', () => startSidechain(sidechain)),
      if (up && !_binaryProvider.isStopping(sidechain)) item('Stop', () => _binaryProvider.stop(sidechain)),
      if (sidechain.updateAvailable && !_isDownloadingFor(sidechain))
        item('Update ${sidechain.name}', () => _binaryProvider.update(sidechain)),
    ];
  }

  /// True when the app runs the node in its own process, which a phone does with no local build.
  bool _runsInApp(Sidechain sidechain) {
    final name = _binaryProvider.orchestratorName(sidechain);
    return name != null && GetIt.I.isRegistered<AppRunHost>() && GetIt.I.get<AppRunHost>().hosts(name);
  }

  /// The start, open and stop items of a node that the app runs in its own process.
  /// A phone table has no actions column, so the row menu holds them.
  List<SailMenuItem> appRunMenuItems(int slot) {
    final sidechain = sidechainForSlot(slot);
    if (sidechain == null || !_runsInApp(sidechain) || _binaryProvider.isStopping(sidechain)) {
      return const [];
    }
    if (_binaryProvider.isConnected(sidechain)) {
      return [
        SailMenuItem(
          onSelected: () => unawaited(openHere(sidechain)),
          child: SailText.primary12('Open ${sidechain.name}'),
        ),
        SailMenuItem(
          onSelected: () => unawaited(_binaryProvider.stop(sidechain)),
          child: SailText.primary12('Stop ${sidechain.name}'),
        ),
      ];
    }
    if (_binaryProvider.isSidechainUp(sidechain) || _binaryProvider.isInitializing(sidechain)) {
      return const [];
    }
    return [
      SailMenuItem(
        onSelected: () => unawaited(startSidechain(sidechain)),
        child: SailText.primary12('Start ${sidechain.name}'),
      ),
    ];
  }

  /// The row button of a node that the app runs in its own process: Open when it runs, else Start.
  /// A null run means the node starts or stops, so the button waits.
  ({String label, Future<void> Function()? run})? appRunButton(int slot) {
    final sidechain = sidechainForSlot(slot);
    if (sidechain == null || !_runsInApp(sidechain)) {
      return null;
    }
    if (_binaryProvider.isConnected(sidechain)) {
      return _binaryProvider.isStopping(sidechain)
          ? (label: 'Open', run: null)
          : (label: 'Open', run: () => openHere(sidechain));
    }
    if (_binaryProvider.isStopping(sidechain) ||
        _binaryProvider.isSidechainUp(sidechain) ||
        _binaryProvider.isInitializing(sidechain)) {
      return (label: 'Start', run: null);
    }
    return (label: 'Start', run: () => startSidechain(sidechain));
  }

  /// True when the sidechain opens inside BitWindow, not in a window of its own.
  bool _opensHere(Sidechain sidechain) =>
      !_settingsProvider.bitwindowSettings.openSidechainsInWindow && hostedModuleFor(sidechain) != null;

  /// Starts the sidechain the way the settings ask: its node with the view inside BitWindow, or its app window.
  Future<void> startSidechain(Sidechain sidechain) async {
    if (!_opensHere(sidechain)) {
      await _binaryProvider.start(sidechain);
      return;
    }
    await _binaryProvider.start(sidechain, background: true);
    await openHere(sidechain);
  }

  List<_StartOption> _startOptions(Sidechain sidechain) {
    if (!_opensHere(sidechain)) {
      return [
        _StartOption(title: 'Start with window', onSelected: () => _binaryProvider.start(sidechain)),
        _StartOption(
          title: 'Start in background',
          onSelected: () => _binaryProvider.start(sidechain, background: true),
        ),
      ];
    }
    return [
      _StartOption(title: 'Start and open here', onSelected: () => startSidechain(sidechain)),
      _StartOption(title: 'Start in background', onSelected: () => _binaryProvider.start(sidechain, background: true)),
      if (_binaryProvider.hasWindow(sidechain))
        _StartOption(title: 'Start in a separate window', onSelected: () => _binaryProvider.start(sidechain)),
    ];
  }

  /// The node runs, and the sidechain opens inside BitWindow.
  bool _offersOpenHere(Sidechain sidechain) =>
      _opensHere(sidechain) && _binaryProvider.isConnected(sidechain) && !_binaryProvider.isStopping(sidechain);

  /// The node runs, but the app window of the sidechain is closed.
  bool _offersOpenWindow(Sidechain sidechain) =>
      _binaryProvider.hasWindow(sidechain) &&
      _binaryProvider.isConnected(sidechain) &&
      !_binaryProvider.isWindowOpen(sidechain) &&
      !_binaryProvider.isStopping(sidechain);

  bool _offersStartMenu(Sidechain sidechain) =>
      sidechain.isDownloaded &&
      (_binaryProvider.hasWindow(sidechain) || _opensHere(sidechain)) &&
      !_binaryProvider.isSidechainUp(sidechain);

  int? _selectedIndex;

  int? get selectedIndex => _selectedIndex;

  /// Makes the table show [selectedIndex] again after a click on a row that holds no slot.
  void restoreSelection() => notifyListeners();

  /// The selected sidechain, or null when no row with a sidechain is selected.
  SidechainOverview? get selectedSidechain => _selectedIndex == null ? null : sidechains[_selectedIndex!];

  void selectSlot(int slot) {
    _selectedIndex = slot;
    notifyListeners();
  }

  void clearSelection() {
    _selectedIndex = null;
    notifyListeners();
  }

  void decrementSelectedIndex() {
    _selectedIndex = max(0, (_selectedIndex ?? 0) - 1);
    notifyListeners();
  }

  void incrementSelectedIndex() {
    _selectedIndex = min(255, (_selectedIndex ?? 0) + 1);
    notifyListeners();
  }

  List<ListSidechainDepositsResponse_SidechainDeposit> _sortedDeposits = [];
  String depositSortColumn = 'amount';
  bool depositSortAscending = true;

  List<ListSidechainDepositsResponse_SidechainDeposit> get sortedDeposits {
    if (!listEquals(_sortedDeposits, recentDeposits)) {
      _sortedDeposits = List<ListSidechainDepositsResponse_SidechainDeposit>.from(recentDeposits);
      _sortDeposits();
    }
    return _sortedDeposits;
  }

  List<WithdrawalBundle> get sortedWithdrawals {
    return selectedSidechain?.withdrawals ?? [];
  }

  void sortDeposits(String column) {
    if (depositSortColumn == column) {
      depositSortAscending = !depositSortAscending;
    } else {
      depositSortColumn = column;
      depositSortAscending = true;
    }
    _sortDeposits();
    notifyListeners();
  }

  void _sortDeposits() {
    _sortedDeposits.sort((a, b) {
      dynamic aValue;
      dynamic bValue;

      switch (depositSortColumn) {
        case 'amount':
          aValue = a.amount;
          bValue = b.amount;
          break;
        case 'txid':
          aValue = a.txid;
          bValue = b.txid;
          break;
        case 'confirmations':
          aValue = a.confirmations;
          bValue = b.confirmations;
          break;
        default:
          return 0;
      }

      return depositSortAscending ? aValue.compareTo(bValue) : bValue.compareTo(aValue);
    });
  }

  List<ListSidechainDepositsResponse_SidechainDeposit> get recentDeposits => selectedSidechain?.deposits ?? [];

  @override
  void dispose() {
    searchController.dispose();
    _settingsProvider.removeListener(notifyListeners);
    _sidechainProvider.removeListener(_onChange);
    _walletReader.removeListener(_onChange);
    _nodeMode?.removeListener(_onChange);
    _balanceProvider.removeListener(notifyListeners);
    _binaryProvider.removeListener(_onChange);
    _binaryProvider.removeListener(notifyListeners);
    _syncProvider.removeListener(_onChange);
    _syncProvider.removeListener(notifyListeners);
    _downloadProvider?.removeListener(_onChange);
    _downloadProvider?.removeListener(notifyListeners);
    super.dispose();
  }

  void _onChange() {
    // Core data that affects the UI
    track('sidechains', _sidechainProvider.sidechains);
    track('recentDeposits', recentDeposits);

    // Switching between an electrum and a backend-backed wallet changes nothing
    // else tracked here, so without this the tab keeps rendering the old gate.
    final gate = l1Gate;
    if (track('l1Gate', gate) && gate == L1Gate.ready) {
      // SidechainProvider only refetches once isSynced flips, which never
      // happens on an empty regtest chain — the slot list would stay as it was
      // when the daemons were still down.
      unawaited(_sidechainProvider.fetch());
    }

    // UI state that affects rendering
    track('showOnlyFilled', showOnlyFilled);
    track('selectedIndex', selectedIndex);

    // Sorting state
    track('depositSortColumn', depositSortColumn);
    track('depositSortAscending', depositSortAscending);

    // Binary states that affect sidechainWidget() rendering - notify immediately
    // so sidechain list buttons update instantly when binaries connect/disconnect.
    final binaryChanged = track('binaryStates', _getBinaryStates());

    // Loading and error states
    track('loading', loading);
    // Error handling
    final errorChanged = track('error', _sidechainProvider.error);
    if (errorChanged) {
      setErrorForObject('sidechain', _sidechainProvider.error);
    }

    if (binaryChanged) {
      // Binary state changes (connect/disconnect/start/stop) must rebuild
      // immediately - bypass the ChangeTrackingMixin debounce.
      notifyListeners();
    } else {
      notifyIfChanged();
    }
  }

  // Helper method to track binary states efficiently.
  // Uses per-binary helper methods for connected/initializing/stopping,
  // and tracks errors + download state for status icon tooltips.
  Map<String, dynamic> _getBinaryStates() {
    final states = <String, dynamic>{};

    for (final binary in _binaryProvider.binaries) {
      final key = binary.name;
      states['${key}_connected'] = _binaryProvider.isConnected(binary);
      states['${key}_initializing'] = _binaryProvider.isInitializing(binary);
      states['${key}_stopping'] = _binaryProvider.isStopping(binary);
      states['${key}_downloading'] = _isDownloadingFor(binary);
      states['${key}_error'] = _binaryProvider.connectionError(binary);
      states['${key}_downloaded'] = binary.isDownloaded;
    }

    return states;
  }
}

class DepositWithdrawView extends ViewModelWidget<SidechainsViewModel> {
  const DepositWithdrawView({super.key});

  @override
  Widget build(BuildContext context, SidechainsViewModel viewModel) {
    final phone = SailStyleValues.phoneLayout(context);
    return InlineTabBar(
      tabs: [
        TabItem(
          label: 'See Deposits',
          icon: phone ? null : SailSVGAsset.iconDeposit,
          child: const SeeDepositsView(),
        ),
        TabItem(
          label: 'See Withdrawals',
          icon: phone ? null : SailSVGAsset.iconWithdraw,
          child: const SeeWithdrawalsView(),
        ),
      ],
      initialIndex: 0,
    );
  }
}

/// The deposit fee, on a rate the backend estimated for a block target.
class DepositFeeFields extends StatelessWidget {
  final DepositFeeEstimate estimate;
  final ValueChanged<int> onTargetChanged;

  /// True puts each field on its own line, for a phone.
  final bool stacked;

  const DepositFeeFields({
    super.key,
    required this.estimate,
    required this.onTargetChanged,
    this.stacked = false,
  });

  Widget _targetDropdown() => SailDropdownButton<int>(
    value: estimate.confTarget,
    items: depositFeeTargets
        .map((target) => SailDropdownItem<int>(value: target, label: depositFeeTargetLabel(target)))
        .toList(),
    onChanged: (target) {
      if (target != null) {
        onTargetChanged(target);
      }
    },
  );

  @override
  Widget build(BuildContext context) {
    if (stacked) {
      return SailColumn(
        spacing: SailStyleValues.padding08,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NumericField(label: 'Fee', controller: estimate.controller, hintText: '0.00000000'),
          UnitDropdown(value: Unit.BTC, onChanged: (_) => {}, enabled: false),
          const SailSpacing(SailStyleValues.padding08),
          SailText.primary13('Fee target', bold: true),
          _targetDropdown(),
          SailText.secondary12(estimate.hint, color: context.sailTheme.colors.textTertiary),
        ],
      );
    }
    return SailColumn(
      spacing: SailStyleValues.padding08,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SailRow(
          spacing: SailStyleValues.padding08,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              flex: 2,
              child: NumericField(
                label: 'Fee',
                controller: estimate.controller,
                hintText: '0.00000000',
              ),
            ),
            UnitDropdown(value: Unit.BTC, onChanged: (_) => {}, enabled: false),
            Expanded(
              flex: 2,
              child: SailColumn(
                spacing: SailStyleValues.padding08,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SailText.primary13('Fee target', bold: true),
                  SizedBox(
                    width: double.infinity,
                    child: SailDropdownButton<int>(
                      value: estimate.confTarget,
                      items: depositFeeTargets
                          .map(
                            (target) => SailDropdownItem<int>(
                              value: target,
                              label: depositFeeTargetLabel(target),
                            ),
                          )
                          .toList(),
                      onChanged: (target) {
                        if (target != null) {
                          onTargetChanged(target);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        SailText.secondary12(estimate.hint, color: context.sailTheme.colors.textTertiary),
      ],
    );
  }
}

class SeeDepositsView extends ViewModelWidget<SidechainsViewModel> {
  const SeeDepositsView({super.key});

  @override
  Widget build(BuildContext context, SidechainsViewModel viewModel) {
    return SailCard(
      bottomPadding: false,
      child: RecentDepositsTable(),
    );
  }
}

class SeeWithdrawalsView extends ViewModelWidget<SidechainsViewModel> {
  const SeeWithdrawalsView({super.key});

  @override
  Widget build(BuildContext context, SidechainsViewModel viewModel) {
    return SailCard(
      bottomPadding: false,
      child: const RecentWithdrawalsTable(),
    );
  }
}

class RecentDepositsTable extends ViewModelWidget<SidechainsViewModel> {
  const RecentDepositsTable({super.key});

  @override
  Widget build(BuildContext context, SidechainsViewModel viewModel) {
    final formatter = GetIt.I<FormatterProvider>();

    return ListenableBuilder(
      listenable: formatter,
      builder: (context, child) => SailTable(
        getRowId: (index) => viewModel.sortedDeposits[index].txid,
        phoneColumns: const [0, 2, 3],
        headerBuilder: (context) => [
          SailTableHeaderCell(name: 'Txid', onSort: () => viewModel.sortDeposits('txid')),
          SailTableHeaderCell(name: 'Amount', onSort: () => viewModel.sortDeposits('amount')),
          SailTableHeaderCell(name: 'Fee', onSort: () => viewModel.sortDeposits('fee')),
          SailTableHeaderCell(
            name: 'Confirmations',
            onSort: () => viewModel.sortDeposits('confirmations'),
          ),
        ],
        rowBuilder: (context, row, selected) {
          final deposit = viewModel.sortedDeposits[row];
          return [
            SailTableCell(value: '${deposit.txid.substring(0, 10)}..', copyValue: deposit.txid),
            SailTableCell(value: formatter.formatSats(deposit.amount.toInt())),
            SailTableCell(value: formatter.formatSats(deposit.fee.toInt())),
            SailTableCell(
              value: deposit.dropped ? 'Dropped — deposit again' : deposit.confirmations.toString(),
            ),
          ];
        },
        rowCount: viewModel.sortedDeposits.length,
        emptyPlaceholder: 'No deposits yet',
        drawGrid: true,
        sortAscending: viewModel.depositSortAscending,
        sortColumnIndex: [
          'txid',
          'amount',
          'fee',
          'confirmations',
        ].indexOf(viewModel.depositSortColumn),
        onSort: (columnIndex, ascending) => viewModel.sortDeposits(viewModel.depositSortColumn),
        onDoubleTap: (rowId) => showTransactionDetails(context, rowId),
        contextMenuItems: (rowId) {
          return [
            SailMenuItem(
              onSelected: () => showTransactionDetails(context, rowId),
              child: SailText.primary12('Show Transaction Details'),
            ),
          ];
        },
      ),
    );
  }
}

class RecentWithdrawalsTable extends ViewModelWidget<SidechainsViewModel> {
  const RecentWithdrawalsTable({super.key});

  @override
  Widget build(BuildContext context, SidechainsViewModel viewModel) {
    if (viewModel.sortedWithdrawals.isEmpty) {
      return Center(child: SailText.secondary13('No withdrawal bundles found for this sidechain'));
    }

    return SailTable(
      getRowId: (index) => viewModel.sortedWithdrawals[index].m6id,
      headerBuilder: (context) => [
        const SailTableHeaderCell(name: 'M6 ID'),
        const SailTableHeaderCell(name: 'Status'),
        const SailTableHeaderCell(name: 'Block Height'),
        const SailTableHeaderCell(name: 'Sequence #'),
      ],
      rowBuilder: (context, row, selected) {
        final withdrawal = viewModel.sortedWithdrawals[row];
        return [
          SailTableCell(
            value: '${withdrawal.m6id.substring(0, 10)}...',
            copyValue: withdrawal.m6id,
          ),
          SailTableCell(value: withdrawal.status),
          SailTableCell(value: withdrawal.blockHeight.toString()),
          SailTableCell(
            value: withdrawal.sequenceNumber.toInt() > 0 ? withdrawal.sequenceNumber.toString() : '-',
          ),
        ];
      },
      rowCount: viewModel.sortedWithdrawals.length,
      emptyPlaceholder: 'No withdrawal bundles',
      drawGrid: true,
      sortAscending: true,
      sortColumnIndex: 2,
    );
  }
}

Future<void> showDepositModal(BuildContext context, int slot, String sidechainName) {
  return showThemedDialog<void>(
    barrierDismissible: true,
    context: context,
    builder: (context) => DepositModal(slot: slot, sidechainName: sidechainName),
  );
}

class DepositModal extends StatefulWidget {
  final int slot;
  final String sidechainName;

  const DepositModal({super.key, required this.slot, required this.sidechainName});

  @override
  State<DepositModal> createState() => _DepositModalState();
}

final _depositAddressPattern = RegExp(r'^[A-Za-z0-9_]{1,80}$');

class _DepositModalState extends State<DepositModal> {
  final TextEditingController addressController = TextEditingController();
  final TextEditingController amountController = TextEditingController();
  final TextEditingController feeController = TextEditingController();
  late final DepositFeeEstimate depositFee = DepositFeeEstimate(feeController);
  final FundingWalletBalances fundingBalances = FundingWalletBalances();

  bool isLoading = false;
  bool isFetchingAddress = true;
  String? fetchError;
  String? depositError;
  String? selectedWalletId;
  bool amountFollowsMax = false;

  String? get fromWalletId => GetIt.I<WalletReaderProvider>().resolveFundingWalletId(selectedWalletId);

  /// The spendable balance of the funding wallet, or null while unknown.
  int? get availableSats {
    final walletId = fromWalletId;
    return walletId == null ? null : fundingBalances.satsFor(walletId);
  }

  /// The largest amount the funding wallet can deposit at the current fee.
  int? get maxAmountSats {
    final available = availableSats;
    final fee = double.tryParse(feeController.text);
    if (available == null || fee == null || available <= btcToSatoshi(fee)) {
      return null;
    }
    return available - btcToSatoshi(fee);
  }

  String get _maxAmountText {
    final sats = maxAmountSats;
    return sats == null ? '' : satoshiToBTC(sats).toStringAsFixed(8);
  }

  void _useMaxAmount() {
    amountFollowsMax = true;
    amountController.text = _maxAmountText;
  }

  void _followMax() {
    if (amountFollowsMax) {
      amountController.text = _maxAmountText;
    }
  }

  void _onAmountChanged() {
    if (amountFollowsMax && amountController.text != _maxAmountText) {
      amountFollowsMax = false;
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchDepositAddress();
    unawaited(_setFeeTarget(depositFee.confTarget, keepEdits: true));
    addressController.addListener(_onTextChanged);
    amountController.addListener(_onTextChanged);
    amountController.addListener(_onAmountChanged);
    feeController.addListener(_onTextChanged);
    feeController.addListener(_followMax);
    fundingBalances.addListener(_followMax);
    GetIt.I<WalletReaderProvider>().addListener(_followMax);
  }

  Future<void> _setFeeTarget(int confTarget, {bool keepEdits = false}) async {
    await depositFee.refresh(confTarget, keepEdits: keepEdits);
    if (mounted) {
      setState(() {});
    }
  }

  void _onTextChanged() {
    setState(() => depositError = null);
  }

  @override
  void dispose() {
    addressController.removeListener(_onTextChanged);
    amountController.removeListener(_onTextChanged);
    amountController.removeListener(_onAmountChanged);
    feeController.removeListener(_onTextChanged);
    feeController.removeListener(_followMax);
    fundingBalances.removeListener(_followMax);
    GetIt.I<WalletReaderProvider>().removeListener(_followMax);
    fundingBalances.dispose();
    addressController.dispose();
    amountController.dispose();
    feeController.dispose();
    super.dispose();
  }

  SidechainRPC? _getSidechainRPC(int slot) {
    final binaryProvider = GetIt.I<BinaryProvider>();

    // Find the sidechain binary by slot
    final sidechain = binaryProvider.binaries.firstWhereOrNull(
      (b) => b is Sidechain && b.slot == slot,
    );
    if (sidechain == null) {
      return null;
    }

    // Get the RPC for this sidechain type
    // Thunder goes through drivechaind, so no direct SidechainRPC available here
    final rpc = switch (sidechain) {
      Truthcoin() => GetIt.I.isRegistered<TruthcoinRPC>() ? GetIt.I.get<TruthcoinRPC>() : null,
      Photon() => GetIt.I.isRegistered<PhotonRPC>() ? GetIt.I.get<PhotonRPC>() : null,
      BitNames() => GetIt.I.isRegistered<BitnamesRPC>() ? GetIt.I.get<BitnamesRPC>() : null,
      BitAssets() => GetIt.I.isRegistered<BitAssetsRPC>() ? GetIt.I.get<BitAssetsRPC>() : null,
      ZSide() => GetIt.I.isRegistered<ZSideRPC>() ? GetIt.I.get<ZSideRPC>() : null,
      CoinShift() => GetIt.I.isRegistered<CoinShiftRPC>() ? GetIt.I.get<CoinShiftRPC>() : null,
      Sidepot() => GetIt.I.isRegistered<SidepotRPC>() ? GetIt.I.get<SidepotRPC>() : null,
      Thunder() => GetIt.I.isRegistered<ThunderRPC>() ? GetIt.I.get<ThunderRPC>() : null,
      _ => null,
    };

    if (rpc != null && rpc.connected) {
      return rpc;
    }
    return null;
  }

  /// Reads an address from the sidechain. An address the user pastes while the
  /// read is in flight wins: the paste is the later action.
  Future<void> _fetchDepositAddress() async {
    final before = addressController.text;
    setState(() {
      isFetchingAddress = true;
      fetchError = null;
    });

    final sidechainRPC = _getSidechainRPC(widget.slot);
    if (sidechainRPC == null) {
      setState(() {
        fetchError = '${widget.sidechainName} is not running. Paste a deposit address.';
        isFetchingAddress = false;
      });
      return;
    }

    try {
      final address = await sidechainRPC.getDepositAddress();
      if (mounted) {
        setState(() {
          if (addressController.text == before) {
            addressController.text = address;
          }
          isFetchingAddress = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          fetchError = e.toString();
          isFetchingAddress = false;
        });
      }
    }
  }

  Future<void> _deposit() async {
    if (addressController.text.isEmpty) {
      setState(() => depositError = 'No deposit address available');
      return;
    }
    if (!_depositAddressPattern.hasMatch(addressController.text)) {
      setState(() => depositError = 'Invalid deposit address, use only letters, digits and _ (80 characters max)');
      return;
    }
    if (double.tryParse(amountController.text) == null) {
      setState(() => depositError = 'Invalid amount, enter a number');
      return;
    }
    if (double.tryParse(feeController.text) == null) {
      setState(() => depositError = 'Invalid fee, enter a number');
      return;
    }
    setState(() => depositError = null);

    final api = GetIt.I<BitwindowRPC>();
    final transactionsProvider = GetIt.I<TransactionProvider>();
    final balanceProvider = GetIt.I<BalanceProvider>();
    final sidechainProvider = GetIt.I<SidechainProvider>();

    try {
      final walletId = fromWalletId;
      if (walletId == null) {
        throw Exception('No wallet selected to fund the deposit');
      }

      setState(() => isLoading = true);

      final txid = await api.wallet.createSidechainDeposit(
        walletId,
        widget.slot,
        addressController.text,
        double.parse(amountController.text),
        double.parse(feeController.text),
      );

      if (mounted) {
        Navigator.of(context).pop();
        showSailToast(context, 'Deposited in txid: $txid');
      }

      // Refresh data
      await transactionsProvider.fetch();
      await balanceProvider.fetch();
      await sidechainProvider.fetch();
    } catch (e) {
      if (mounted) {
        setState(() => depositError = 'Could not create deposit: $e');
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // fromWalletId resolves against the live wallet list, so rebuild with it —
    // otherwise the dropdown keeps showing a wallet the deposit no longer uses.
    return ListenableBuilder(
      listenable: Listenable.merge([
        GetIt.I<WalletReaderProvider>(),
        fundingBalances,
        GetIt.I<FormatterProvider>(),
      ]),
      builder: (context, _) => _buildCard(context),
    );
  }

  Widget _buildCard(BuildContext context) {
    final available = availableSats;
    final sheet = SailSheetScope.of(context);
    final phone = SailStyleValues.phoneLayout(context);
    final fromWallet = FromWalletField(
      selectedWalletId: fromWalletId,
      balances: fundingBalances,
      onChanged: (walletId) {
        setState(() {
          selectedWalletId = walletId;
          depositError = null;
        });
        _followMax();
      },
    );
    return SailDialogFrame(
      child: Padding(
        padding: sheet
            ? EdgeInsets.zero
            : EdgeInsets.symmetric(
                horizontal: MediaQuery.of(context).size.width * 0.25,
                vertical: SailStyleValues.padding25,
              ),
        child: ClipRRect(
          borderRadius: sheet
              ? BorderRadius.vertical(top: context.sailTheme.chrome.radius.topLeft)
              : context.sailTheme.chrome.radius,
          child: SailCard(
            title: 'Deposit to ${widget.sidechainName}',
            subtitle: 'Slot ${widget.slot}',
            error: fetchError,
            withCloseButton: true,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SailRow(
                    spacing: SailStyleValues.padding08,
                    children: [
                      Expanded(
                        child: SailTextField(
                          label: 'Deposit Address',
                          loading: LoadingDetails(
                            enabled: isFetchingAddress,
                            description: 'Fetching deposit address from ${widget.sidechainName}...',
                          ),
                          controller: addressController,
                          hintText: 's${widget.slot}_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx_xxxxxx',
                          minLines: phone ? 1 : null,
                          maxLines: phone ? 3 : null,
                          alignSuffixTop: phone,
                          suffixWidget: addressController.text.isEmpty
                              ? null
                              : CopyButton(text: addressController.text),
                        ),
                      ),
                      SailTooltip(
                        message: 'Generate new address',
                        child: SailButton(
                          variant: ButtonVariant.icon,
                          icon: SailSVGAsset.iconRestart,
                          onPressed: isFetchingAddress ? null : _fetchDepositAddress,
                        ),
                      ),
                    ],
                  ),
                  const SailSpacing(SailStyleValues.padding16),
                  if (phone) ...[
                    NumericField(label: 'Deposit Amount', controller: amountController, hintText: '0.00'),
                    if (available != null)
                      Center(
                        child: SailButton(
                          label: 'MAX',
                          variant: ButtonVariant.link,
                          disabled: maxAmountSats == null,
                          onPressed: () async => _useMaxAmount(),
                        ),
                      ),
                    const SailSpacing(SailStyleValues.padding08),
                    SizedBox(
                      width: double.infinity,
                      child: UnitDropdown(value: Unit.BTC, onChanged: (_) {}, enabled: false),
                    ),
                    const SailSpacing(SailStyleValues.padding16),
                    SizedBox(width: double.infinity, child: fromWallet),
                  ] else
                    SailRow(
                      spacing: SailStyleValues.padding08,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          flex: 2,
                          child: NumericField(
                            label: 'Deposit Amount',
                            controller: amountController,
                            hintText: '0.00',
                            suffixWidget: available == null
                                ? null
                                : SailButton(
                                    label: 'MAX',
                                    variant: ButtonVariant.link,
                                    disabled: maxAmountSats == null,
                                    onPressed: () async => _useMaxAmount(),
                                    padding: EdgeInsets.zero,
                                  ),
                          ),
                        ),
                        UnitDropdown(value: Unit.BTC, onChanged: (_) {}, enabled: false),
                        Expanded(
                          flex: 2,
                          child: FromWalletField(
                            selectedWalletId: fromWalletId,
                            balances: fundingBalances,
                            onChanged: (walletId) {
                              setState(() {
                                selectedWalletId = walletId;
                                depositError = null;
                              });
                              _followMax();
                            },
                          ),
                        ),
                      ],
                    ),
                  if (available != null) ...[
                    const SailSpacing(SailStyleValues.padding08),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        SailText.primary13('Available'),
                        SailText.primary13(
                          GetIt.I<FormatterProvider>().formatSats(available),
                          bold: true,
                        ),
                      ],
                    ),
                  ],
                  const SailSpacing(SailStyleValues.padding08),
                  DepositFeeFields(estimate: depositFee, onTargetChanged: _setFeeTarget, stacked: phone),
                  const SailSpacing(SailStyleValues.padding08),
                  _LeavesWalletRow(amount: amountController.text, fee: feeController.text),
                  const SailSpacing(SailStyleValues.padding08),
                  SailText.secondary13(
                    '${widget.sidechainName} may deduct its own fee, so the credited amount can be lower.',
                    color: context.sailTheme.colors.textTertiary,
                  ),
                  const SailSpacing(SailStyleValues.padding20),
                  SizedBox(
                    width: double.infinity,
                    child: SailButton(
                      label: 'Deposit',
                      loading: isLoading,
                      disabled:
                          addressController.text.isEmpty ||
                          fromWalletId == null ||
                          amountController.text.isEmpty ||
                          feeController.text.isEmpty,
                      onPressed: _deposit,
                    ),
                  ),
                  if (depositError != null) ...[
                    const SailSpacing(SailStyleValues.padding08),
                    SailInlineError(depositError!),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The deposit amount plus the L1 fee. Hidden until both parse.
class _LeavesWalletRow extends StatelessWidget {
  final String amount;
  final String fee;

  const _LeavesWalletRow({required this.amount, required this.fee});

  @override
  Widget build(BuildContext context) {
    final amountBTC = double.tryParse(amount);
    final feeBTC = double.tryParse(fee);
    if (amountBTC == null || feeBTC == null) {
      return const SizedBox.shrink();
    }

    final formatter = GetIt.I<FormatterProvider>();
    final totalSats = btcToSatoshi(amountBTC) + btcToSatoshi(feeBTC);

    return ListenableBuilder(
      listenable: formatter,
      builder: (context, _) => Container(
        padding: const EdgeInsets.only(top: SailStyleValues.padding12),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: context.sailTheme.colors.divider)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            SailText.primary13('Leaves your wallet'),
            SailText.primary13(formatter.formatSats(totalSats), bold: true),
          ],
        ),
      ),
    );
  }
}
