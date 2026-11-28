import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:bitwindow/providers/m4_provider.dart';
import 'package:bitwindow/providers/sidechain_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:sidechain_core/gen/drivechain/v1/drivechain.pb.dart' as drivechainpb;
import 'package:sidechain_core/gen/m4/v1/m4.pb.dart' as m4pb;
import 'package:sail_ui/sail_ui.dart';

@RoutePage()
class M4ExplorerPage extends StatefulWidget {
  const M4ExplorerPage({super.key});

  @override
  State<M4ExplorerPage> createState() => _M4ExplorerPageState();
}

class _M4ExplorerPageState extends State<M4ExplorerPage> {
  int? _selectedSidechainSlot;
  String? _voteError;
  M4Provider get _m4Provider => GetIt.I.get<M4Provider>();
  SidechainProvider get _sidechainProvider => GetIt.I.get<SidechainProvider>();

  @override
  Widget build(BuildContext context) {
    final confProvider = GetIt.I.get<BitcoinConfProvider>();
    final theme = SailTheme.of(context);

    if (!confProvider.networkSupportsSidechains) {
      return SailScaffold(
        backgroundColor: theme.colors.background,
        appBar: SailAppBar.build(context, title: SailText.primary20('Sidechain Withdrawal Admin')),
        body: Padding(
          padding: const EdgeInsets.all(SailStyleValues.padding16),
          child: SailCard(
            title: 'Sidechain Withdrawal Admin',
            subtitle: 'Not available on this network',
            child: Padding(
              padding: const EdgeInsets.all(SailStyleValues.padding20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SailText.primary20('Unlock M4 Features with BIP300'),
                  const SailSpacing(SailStyleValues.padding20),
                  SailText.secondary13(
                    'The Sidechain Withdrawal Admin (M4 Explorer) is only available on Drivechain-enabled networks '
                    '(eCash and Signet). These networks implement BIP300, which enables trustless two-way pegged sidechains.',
                  ),
                  const SailSpacing(SailStyleValues.padding20),
                  SailText.primary15('What is M4?'),
                  const SailSpacing(SailStyleValues.padding08),
                  SailText.secondary13(
                    'M4 is the mechanism for handling sidechain withdrawals in BIP300. As a miner or node operator, '
                    'you can vote on withdrawal bundles and help secure the sidechain-to-mainchain peg.',
                  ),
                  const SailSpacing(SailStyleValues.padding20),
                  SailText.primary15('How to Enable'),
                  const SailSpacing(SailStyleValues.padding08),
                  SailText.secondary13(
                    '1. Go to Settings\n'
                    '2. Switch to "eCash" or "Signet" network\n'
                    '3. Restart BitWindow\n'
                    '4. Return here to manage sidechain withdrawals',
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return SailScaffold(
      backgroundColor: theme.colors.background,
      appBar: SailAppBar.build(context, title: SailText.primary20('Sidechain Withdrawal Admin')),
      body: ListenableBuilder(
        listenable: Listenable.merge([_sidechainProvider, _m4Provider]),
        builder: (context, child) {
          return Padding(
            padding: const EdgeInsets.all(SailStyleValues.padding12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SailStrip(
                  lead: SailRow(
                    children: [
                      SailText.primary13('Default vote for all sidechains'),
                      const SizedBox(width: SailStyleValues.padding12),
                      SailDropdownButton<m4pb.VotePolicy>(
                        value: _m4Provider.votePolicy,
                        items: const [
                          SailDropdownItem(value: m4pb.VotePolicy.VOTE_POLICY_ABSTAIN, label: 'Abstain'),
                          SailDropdownItem(
                            value: m4pb.VotePolicy.VOTE_POLICY_UPVOTE_KNOWN,
                            label: 'Upvote bundles from this node',
                          ),
                          SailDropdownItem(
                            value: m4pb.VotePolicy.VOTE_POLICY_UPVOTE_ALL,
                            label: 'Upvote the first bundle',
                          ),
                          SailDropdownItem(value: m4pb.VotePolicy.VOTE_POLICY_ALARM, label: 'Alarm'),
                        ],
                        onChanged: (policy) async {
                          if (policy != null) {
                            await _setVotePolicy(policy);
                          }
                        },
                      ),
                    ],
                  ),
                ),
                if (_voteError != null) ...[
                  const SizedBox(height: SailStyleValues.padding08),
                  SailInlineError(_voteError!),
                ],
                const SizedBox(height: SailStyleValues.padding12),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 320,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: SailCard(
                                title: 'Active Sidechains',
                                bottomPadding: false,
                                child: Builder(
                                  builder: (context) {
                                    if (_sidechainProvider.sidechains.isEmpty) {
                                      return const Center(child: LoadingIndicator());
                                    }

                                    final activeSidechains = _activeSidechains;

                                    return SailTable(
                                      getRowId: (index) => activeSidechains[index].toString(),
                                      selectedRowId: _selectedSidechainSlot?.toString(),
                                      headerBuilder: (context) => [
                                        const SailTableHeaderCell(name: '#'),
                                        const SailTableHeaderCell(name: 'Name'),
                                      ],
                                      rowBuilder: (context, row, selected) {
                                        final slot = activeSidechains[row];
                                        final sidechain = _sidechainProvider.sidechains[slot];
                                        return [
                                          SailTableCell(value: '$slot'),
                                          SailTableCell(value: sidechain?.info.title ?? 'Sidechain $slot'),
                                        ];
                                      },
                                      rowCount: activeSidechains.length,
                                      emptyPlaceholder: 'No active sidechains',
                                      onSelectedRow: (rowId) {
                                        setState(
                                          () => _selectedSidechainSlot = rowId != null ? int.tryParse(rowId) : null,
                                        );
                                      },
                                    );
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: SailStyleValues.padding12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _selectedSidechainSlot == null
                                  ? Center(
                                      child: SailText.secondary13('Select a sidechain from the list'),
                                    )
                                  // M4 Details
                                  : Builder(
                                      builder: (context) {
                                        final hasData =
                                            _m4Provider.withdrawalBundlesBySidechain.isNotEmpty ||
                                            _m4Provider.history.isNotEmpty;
                                        if (_m4Provider.isLoading && !hasData) {
                                          return const Center(child: LoadingIndicator());
                                        }

                                        if (_m4Provider.modelError != null) {
                                          return Center(child: SailText.primary15('Error: ${_m4Provider.modelError}'));
                                        }

                                        final bundles = _m4Provider.getWithdrawalBundles(_selectedSidechainSlot!)
                                          ..sort((a, b) => b.blockHeight.compareTo(a.blockHeight));
                                        final history = _m4Provider.history;
                                        final upvote = _m4Provider.upvotes[_selectedSidechainSlot];

                                        return Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              flex: 3,
                                              child: SailCard(
                                                title: 'Pending Withdrawals',
                                                subtitle: 'Withdrawal bundles waiting for votes',
                                                child: bundles.isEmpty
                                                    ? Center(
                                                        child: SailText.secondary13('No withdrawal bundles pending'),
                                                      )
                                                    : ListView(
                                                        children: bundles
                                                            .map(
                                                              (bundle) => _BundleRow(
                                                                bundle: bundle,
                                                                upvoted: upvote == bundle.m6id,
                                                                onCopy: () {
                                                                  Clipboard.setData(ClipboardData(text: bundle.m6id));
                                                                  showSailToast(context, 'Copied M6 Bundle Hash');
                                                                },
                                                                onUpvote: () => _setUpvote(
                                                                  upvote == bundle.m6id ? null : bundle.m6id,
                                                                ),
                                                              ),
                                                            )
                                                            .toList(),
                                                      ),
                                              ),
                                            ),
                                            const SizedBox(height: SailStyleValues.padding12),

                                            Expanded(
                                              flex: 2,
                                              child: SailCard(
                                                title: 'Vote History',
                                                subtitle: 'Recent blocks showing withdrawal bundle votes',
                                                child: history.isEmpty
                                                    ? Center(child: SailText.secondary13('No vote history available'))
                                                    : ListView(
                                                        children: history
                                                            .map(
                                                              (entry) => _HistoryEntry(
                                                                entry: entry,
                                                                selectedSidechainSlot: _selectedSidechainSlot!,
                                                              ),
                                                            )
                                                            .toList(),
                                                      ),
                                              ),
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  List<int> get _activeSidechains {
    final result = <int>[];
    for (int slot = 0; slot < _sidechainProvider.sidechains.length; slot++) {
      if (_sidechainProvider.sidechains[slot] != null) {
        result.add(slot);
      }
    }
    return result;
  }

  Future<void> _setUpvote(String? m6id) async {
    setState(() => _voteError = null);
    try {
      await _m4Provider.setBundleUpvote(sidechainSlot: _selectedSidechainSlot!, m6id: m6id);
    } catch (e) {
      if (mounted) {
        setState(() => _voteError = 'Could not set the upvote: $e');
      }
    }
  }

  Future<void> _setVotePolicy(m4pb.VotePolicy policy) async {
    setState(() => _voteError = null);
    try {
      await _m4Provider.setVotePolicy(policy);
    } catch (e) {
      if (mounted) {
        setState(() => _voteError = 'Could not set the default vote: $e');
      }
    }
  }
}

/// Widget for displaying a withdrawal bundle row
class _BundleRow extends StatelessWidget {
  final drivechainpb.WithdrawalBundle bundle;
  final bool upvoted;
  final VoidCallback onCopy;
  final Future<void> Function() onUpvote;

  const _BundleRow({
    required this.bundle,
    required this.upvoted,
    required this.onCopy,
    required this.onUpvote,
  });

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);

    Color statusColor;
    switch (bundle.status.toLowerCase()) {
      case 'succeeded':
        statusColor = theme.colors.success;
      case 'failed':
        statusColor = theme.colors.error;
      default:
        statusColor = theme.colors.orange;
    }

    final isPending = bundle.status.toLowerCase() == 'pending';

    return SailTappable(
      onTap: () async => onCopy(),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
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
                    bundle.m6id.length > 24 ? '${bundle.m6id.substring(0, 24)}...' : bundle.m6id,
                  ),
                  SailText.secondary12(
                    isPending ? 'Age: ${bundle.age} / ${bundle.maxAge}' : 'Block ${bundle.blockHeight}',
                  ),
                ],
              ),
            ),
            if (isPending) ...[
              SizedBox(width: 140, child: SailText.secondary13('Blocks left: ${bundle.blocksLeft}')),
              const SizedBox(width: SailStyleValues.padding12),
            ],
            SizedBox(
              width: 110,
              child: SailRow(
                spacing: SailStyleValues.padding08,
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                  ),
                  SailText.primary13(bundle.status.toUpperCase()),
                ],
              ),
            ),
            SizedBox(
              width: 100,
              child: upvoted
                  ? const SailRow(
                      spacing: SailStyleValues.padding08,
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        SailStatusDot(tone: SailStatusTone.success),
                        _UpvotedLabel(),
                      ],
                    )
                  : null,
            ),
            SizedBox(
              width: 28,
              child: isPending
                  ? SailRowMenuButton(
                      filled: false,
                      items: () => [
                        SailMenuItem(
                          onSelected: () => unawaited(onUpvote()),
                          child: SailText.primary12(upvoted ? 'Upvoted' : 'Upvote'),
                        ),
                      ],
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _UpvotedLabel extends StatelessWidget {
  const _UpvotedLabel();

  @override
  Widget build(BuildContext context) => SailText.primary13('Upvoted');
}

/// Widget for displaying a vote history entry
class _HistoryEntry extends StatelessWidget {
  final m4pb.M4HistoryEntry entry;
  final int selectedSidechainSlot;

  const _HistoryEntry({
    required this.entry,
    required this.selectedSidechainSlot,
  });

  @override
  Widget build(BuildContext context) {
    // Filter votes to only show ones for the selected sidechain
    final relevantVotes = entry.votes.where((v) => v.sidechainSlot == selectedSidechainSlot).toList();

    return SailCollapsible(
      trigger: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SailText.primary13('Block #${entry.blockHeight}'),
            SailText.secondary12(
              relevantVotes.isEmpty ? 'No votes for this sidechain' : '${relevantVotes.length} vote(s)',
            ),
          ],
        ),
      ),
      child: Column(
        children: relevantVotes.isEmpty
            ? [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SailText.secondary12('No withdrawal votes recorded in this block'),
                ),
              ]
            : relevantVotes.map((vote) => _VoteEntry(vote: vote)).toList(),
      ),
    );
  }
}

/// Widget for displaying a single vote entry
class _VoteEntry extends StatelessWidget {
  final m4pb.M4Vote vote;

  const _VoteEntry({required this.vote});

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);

    Color voteColor;
    String voteLabel;
    SailSVGAsset voteIcon;

    switch (vote.voteType.toLowerCase()) {
      case 'upvote':
        voteColor = theme.colors.success;
        voteLabel = 'Upvote';
        voteIcon = SailSVGAsset.arrowUp;
      case 'alarm':
      case 'downvote':
        voteColor = theme.colors.error;
        voteLabel = 'Alarm';
        voteIcon = SailSVGAsset.triangleAlert;
      default:
        voteColor = theme.colors.textSecondary;
        voteLabel = 'Abstain';
        voteIcon = SailSVGAsset.minus;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: SailRow(
        spacing: SailStyleValues.padding12,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: voteColor.withValues(alpha: 0.1),
              borderRadius: context.sailTheme.chrome.radius,
            ),
            child: SailSVG.fromAsset(voteIcon, color: voteColor, width: 16),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SailText.primary13(voteLabel, color: voteColor),
                if (vote.hasBundleHash())
                  SailText.secondary12(
                    'Bundle: ${vote.bundleHash.length > 16 ? '${vote.bundleHash.substring(0, 16)}...' : vote.bundleHash}',
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
