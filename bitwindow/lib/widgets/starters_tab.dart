import 'dart:async';

import 'package:bitwindow/pages/sidechains_page.dart' show SidechainIconTile;
import 'package:collection/collection.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';

class RevealSeedWarningDialog extends StatefulWidget {
  final String starterName;
  final String action;

  const RevealSeedWarningDialog({
    super.key,
    required this.starterName,
    this.action = 'Reveal',
  });

  @override
  State<RevealSeedWarningDialog> createState() => _RevealSeedWarningDialogState();

  static Future<bool?> show(BuildContext context, String starterName, {String action = 'Reveal'}) {
    return showThemedDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => RevealSeedWarningDialog(starterName: starterName, action: action),
    );
  }
}

class _RevealSeedWarningDialogState extends State<RevealSeedWarningDialog> {
  bool _understoodRisk = false;
  bool _verifiedEnvironment = false;

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    final canReveal = _understoodRisk && _verifiedEnvironment;

    return SailDialog(
      title: '${widget.action} Seed Phrase',
      subtitle: 'Security Warning',
      actions: [
        SailButton(
          label: 'Cancel',
          variant: ButtonVariant.secondary,
          onPressed: () async => Navigator.of(context).pop(false),
        ),
        SailButton(
          label: '${widget.action} Seed Phrase',
          onPressed: canReveal ? () async => Navigator.of(context).pop(true) : null,
        ),
      ],
      child: SailColumn(
        spacing: SailStyleValues.padding16,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Warning section
          Container(
            padding: const EdgeInsets.all(SailStyleValues.padding12),
            decoration: BoxDecoration(
              color: theme.colors.orangeLight,
              borderRadius: context.sailTheme.chrome.radiusSmall,
              border: Border.all(color: theme.colors.orange),
            ),
            child: SailColumn(
              spacing: SailStyleValues.padding08,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SailSVG.fromAsset(SailSVGAsset.triangleAlert, width: 20, color: theme.colors.orange),
                    const SizedBox(width: SailStyleValues.padding08),
                    SailText.primary15(
                      'CRITICAL SECURITY WARNING',
                      color: theme.colors.orange,
                      bold: true,
                    ),
                  ],
                ),
                const SizedBox(height: SailStyleValues.padding08),
                SailText.secondary13(
                  'You are about to ${widget.action.toLowerCase()} the seed phrase for ${widget.starterName}. '
                  'Please read and understand the following:',
                ),
              ],
            ),
          ),

          Container(
            padding: const EdgeInsets.all(SailStyleValues.padding12),
            decoration: BoxDecoration(
              color: theme.colors.backgroundSecondary,
              borderRadius: context.sailTheme.chrome.radiusSmall,
              border: Border.all(color: theme.colors.border),
            ),
            child: SailColumn(
              spacing: SailStyleValues.padding08,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const BulletPoint('Anyone with this seed phrase can steal ALL your funds'),
                const BulletPoint('Never share this seed phrase with anyone, ever'),
                const BulletPoint('Make sure no cameras, phones, or observers can see your screen'),
                const BulletPoint('Disable screen recording and screenshot tools'),
                const BulletPoint('Be in a secure, private location before proceeding'),
              ],
            ),
          ),

          // Checkboxes
          GestureDetector(
            onTap: () => setState(() => _understoodRisk = !_understoodRisk),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SailCheckbox(
                  value: _understoodRisk,
                  onChanged: (value) => setState(() => _understoodRisk = value),
                ),
                const SizedBox(width: SailStyleValues.padding08),
                Expanded(
                  child: SailText.secondary13(
                    'I understand that anyone with this seed phrase can steal my funds',
                  ),
                ),
              ],
            ),
          ),

          GestureDetector(
            onTap: () => setState(() => _verifiedEnvironment = !_verifiedEnvironment),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SailCheckbox(
                  value: _verifiedEnvironment,
                  onChanged: (value) => setState(() => _verifiedEnvironment = value),
                ),
                const SizedBox(width: SailStyleValues.padding08),
                Expanded(
                  child: SailText.secondary13(
                    'I have verified this is a secure, private environment',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class StartersTab extends StatelessWidget {
  const StartersTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<StartersPageViewModel>.reactive(
      viewModelBuilder: () => StartersPageViewModel(),
      onViewModelReady: (model) => model.init(),
      builder: (context, viewModel, child) {
        // Pull a fresh future on every rebuild — the wallet stream pings
        // notifyListeners as wallets arrive, and we need a re-fetch then or
        // the table sticks at "empty" while activeWallet is still null.
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: viewModel.loadStarters(),
          builder: (context, snapshot) {
            final starters = viewModel.visibleStarters(snapshot.data ?? []);
            final walletName = viewModel.starterWalletName;
            final selected = starters.where((s) => s['name'] == viewModel.selectedStarter).firstOrNull;

            final card = SailCard(
              title: 'Starters',
              subtitle: walletName == null ? null : 'Wallet: $walletName',
              padding: true,
              bottomPadding: false,
              error: snapshot.hasError ? snapshot.error.toString() : null,
              child: StartersTable(viewModel: viewModel, starters: starters),
            );
            if (selected == null || SailStyleValues.phoneLayout(context)) {
              return card;
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: card),
                const SizedBox(width: SailStyleValues.padding12),
                StarterPanel(viewModel: viewModel, starter: selected, walletName: walletName),
              ],
            );
          },
        );
      },
    );
  }
}

/// The starters by layer: Master, then Layer 1, then Layer 2.
class StartersTable extends StatelessWidget {
  final StartersPageViewModel viewModel;
  final List<Map<String, dynamic>> starters;

  const StartersTable({super.key, required this.viewModel, required this.starters});

  @override
  Widget build(BuildContext context) {
    final colors = SailTheme.of(context).colors;
    final rows = <Object>[
      ...starters.where((s) => s['name'] == 'Master'),
      ..._group('Layer 1', starters.where((s) => s['chain_layer'] == 1)),
      ..._group('Layer 2', starters.where((s) => s['chain_layer'] == 2)),
    ];

    String rowId(int index) => switch (rows[index]) {
      final String label => 'group:$label',
      final Map<String, dynamic> starter => starter['name'] as String,
      _ => '$index',
    };
    Map<String, dynamic>? starterFor(String id) =>
        rows.whereType<Map<String, dynamic>>().where((s) => s['name'] == id).firstOrNull;

    return SailTable(
      getRowId: rowId,
      rowCount: rows.length,
      resizableColumns: false,
      selectedRowId: viewModel.selectedStarter,
      headerBuilder: (context) => const [
        SailTableHeaderCell(name: 'Starter', sortable: false),
        SailTableHeaderCell(name: 'Mnemonic', sortable: false),
      ],
      rowBuilder: (context, row, selected) => switch (rows[row]) {
        final String label => [
          SailTableCell(
            value: '',
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: const EdgeInsets.only(bottom: SailStyleValues.padding08),
                child: SailText.primary12(label, bold: true, color: colors.textSecondary),
              ),
            ),
          ),
          const SailTableCell(value: ''),
        ],
        final Map<String, dynamic> starter => [
          SailTableCell(value: starter['name'] as String),
          SailTableCell(
            value: starterMnemonicText(starter, viewModel.isStarterRevealed(starter['name'] as String)),
            textColor: starter['mnemonic'] == null ? colors.textSecondary : colors.text,
          ),
        ],
        _ => const [SailTableCell(value: ''), SailTableCell(value: '')],
      },
      onSelectedRow: (id) {
        final starter = id == null ? null : starterFor(id);
        viewModel.selectStarter(starter?['mnemonic'] == null ? null : id);
      },
      rowHasMenu: (id) => starterFor(id)?['mnemonic'] != null,
      contextMenuItems: (id) {
        final starter = starterFor(id);
        if (starter == null || starter['mnemonic'] == null) {
          return [];
        }
        return viewModel.menuItems(context, starter, withReveal: true);
      },
    );
  }

  Iterable<Object> _group(String label, Iterable<Map<String, dynamic>> starters) =>
      starters.isEmpty ? const [] : [label, ...starters];
}

/// The mnemonic as the table shows it: hidden dots, the words, or a note that none exists.
String starterMnemonicText(Map<String, dynamic> starter, bool revealed) {
  final mnemonic = starter['mnemonic'] as String?;
  if (mnemonic == null) {
    return 'No starter generated';
  }
  return revealed ? mnemonic : '••••••••••••';
}

/// The 380 px panel of the selected starter: its mnemonic and Reveal or Hide.
class StarterPanel extends StatelessWidget {
  final StartersPageViewModel viewModel;
  final Map<String, dynamic> starter;
  final String? walletName;

  const StarterPanel({super.key, required this.viewModel, required this.starter, required this.walletName});

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    final name = starter['name'] as String;
    final layer = starter['chain_layer'] as int?;
    final slot = starter['sidechain_slot'] as int?;
    final chain = slot == null ? null : Sidechain.fromSlot(slot);
    final revealed = viewModel.isStarterRevealed(name);
    final subtitle = [
      if (layer != null) 'Layer $layer',
      if (walletName != null) 'Wallet: $walletName',
    ].join(' · ');

    return SailSidePanel(
      key: ValueKey('starter_panel_$name'),
      title: name,
      lead: chain == null ? null : SidechainIconTile(chain: chain),
      menuItems: () => viewModel.menuItems(context, starter, withReveal: false),
      onClose: () async => viewModel.selectStarter(null),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (subtitle.isNotEmpty) SailText.secondary12(subtitle),
          const SizedBox(height: SailStyleValues.padding12),
          DecoratedBox(
            decoration: BoxDecoration(color: theme.colors.formField, borderRadius: theme.chrome.radius),
            child: Padding(
              padding: const EdgeInsets.all(SailStyleValues.padding12),
              child: SailText.primary13(starterMnemonicText(starter, revealed)),
            ),
          ),
          const SizedBox(height: SailStyleValues.padding16),
          SailButton(
            label: revealed ? 'Hide' : 'Reveal',
            onPressed: () async => viewModel.toggleStarterReveal(context, name, !revealed),
          ),
        ],
      ),
    );
  }
}

class StartersPageViewModel extends BaseViewModel {
  final Set<String> _revealedStarters = {};
  final WalletWriterProvider _walletProvider = GetIt.I.get<WalletWriterProvider>();
  final WalletReaderProvider _walletReader = GetIt.I.get<WalletReaderProvider>();

  /// Controllers for user input
  final TextEditingController mainchainAddressController = TextEditingController();
  final TextEditingController amountController = TextEditingController();
  final TextEditingController paymentTxIdController = TextEditingController();

  void init() {
    amountController.text = '1.0 BTC';
    // Re-render whenever the wallet stream emits — without this, opening the
    // Starters tab before the WatchWalletData stream has delivered the
    // enforcer wallet leaves the table permanently empty (the FutureBuilder
    // captures a blank loadStarters() result and never refetches).
    _walletReader.addListener(notifyListeners);
  }

  @override
  void dispose() {
    _walletReader.removeListener(notifyListeners);
    super.dispose();
  }

  void resetStartersTab() {
    _revealedStarters.clear();
    notifyListeners();
  }

  String? _selectedStarter;

  /// The name of the starter the panel shows, or null when the panel is closed.
  String? get selectedStarter => _selectedStarter;

  void selectStarter(String? name) {
    _selectedStarter = name;
    notifyListeners();
  }

  /// The starters the table shows. Layer 2 starters show only on a network with sidechains.
  List<Map<String, dynamic>> visibleStarters(List<Map<String, dynamic>> starters) => [
    for (final starter in starters)
      if (starter['chain_layer'] != 2 || GetIt.I.get<BitcoinConfProvider>().networkSupportsSidechains) starter,
  ];

  /// The actions of the "…" of [starter]. [withReveal] adds Reveal or Hide.
  List<SailMenuEntity> menuItems(BuildContext context, Map<String, dynamic> starter, {required bool withReveal}) {
    final name = starter['name'] as String;
    final revealed = isStarterRevealed(name);
    return [
      if (withReveal)
        SailMenuItem(
          onSelected: () => unawaited(toggleStarterReveal(context, name, !revealed)),
          child: SailText.primary12(revealed ? 'Hide' : 'Reveal'),
        ),
      SailMenuItem(
        onSelected: () => unawaited(copyStarterMnemonic(context, name, starter['mnemonic'] as String?)),
        child: SailText.primary12('Copy'),
      ),
    ];
  }

  Future<List<Map<String, dynamic>>> loadStarters() async {
    final BinaryProvider binaryProvider = GetIt.I.get<BinaryProvider>();

    final starters = <Map<String, dynamic>>[];
    final masterData = await _walletProvider.loadMasterStarter();
    // Always render the table scaffold — return the master row even when the
    // mnemonic is still empty (e.g., wallet stream hasn't fired yet, or the
    // active wallet is watch-only). The previous early-return left the
    // entire tab blank, which is what the user reported.
    if (masterData != null) {
      starters.add(masterData);
    } else {
      starters.add({'name': 'Master', 'mnemonic': null});
    }

    final l1Mnemonic = await _walletProvider.getL1Starter();
    starters.add({
      'name': BitcoinCore().name,
      'mnemonic': l1Mnemonic,
      'chain_layer': 1,
    });

    final l2Chains = binaryProvider.binaries.where((b) => b.chainLayer == 2).toList();

    for (var chain in l2Chains) {
      chain = chain as Sidechain;

      final mnemonic = await _walletProvider.getSidechainStarter(chain.slot);
      starters.add({
        'name': chain.name,
        'mnemonic': mnemonic,
        'sidechain_slot': chain.slot,
        'chain_layer': 2,
      });
    }

    return starters;
  }

  String? get starterWalletName {
    final wallet = _walletReader.primaryWallet;
    if (wallet == null || wallet.master.mnemonic.isEmpty) {
      return null;
    }
    return wallet.name;
  }

  bool isStarterRevealed(String? starterName) {
    return starterName != null && _revealedStarters.contains(starterName);
  }

  Future<void> toggleStarterReveal(BuildContext context, String? starterName, bool reveal) async {
    if (starterName == null) {
      return;
    }

    if (reveal) {
      // Show warning dialog before revealing
      final confirmed = await RevealSeedWarningDialog.show(context, starterName);
      if (confirmed != true) {
        // User cancelled, don't reveal
        return;
      }
      _revealedStarters.add(starterName);
    } else {
      _revealedStarters.remove(starterName);
    }

    notifyListeners();
  }

  Future<void> copyStarterMnemonic(BuildContext context, String starterName, String? mnemonic) async {
    if (mnemonic == null) {
      return;
    }
    final confirmed = await RevealSeedWarningDialog.show(context, starterName, action: 'Copy');
    if (confirmed != true) {
      return;
    }
    try {
      await copySecretToClipboard(mnemonic);
    } catch (e) {
      if (context.mounted) {
        showSailToast(context, 'Could not copy the seed phrase: $e', variant: SailToastVariant.destructive);
      }
      return;
    }
    if (context.mounted) {
      showSailToast(context, '$starterName seed phrase copied to clipboard');
    }
  }
}
