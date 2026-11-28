import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';

/// Merkle Tree Visualizer Dialog - Calculate and visualize Bitcoin Merkle trees
///
/// Qt equivalent: merkletreedialog.ui (size: 1213x780)
/// Tabs: Merkle Tree, Witness Merkle Tree, Help
/// Features: RCB (Reversed Concatenated Bytes) toggle for manual verification
class MerkleTreeDialog extends StatefulWidget {
  final List<String>? initialTxids;
  final String? expectedRoot;

  const MerkleTreeDialog({
    super.key,
    this.initialTxids,
    this.expectedRoot,
  });

  @override
  State<MerkleTreeDialog> createState() => _MerkleTreeDialogState();
}

class _MerkleTreeDialogState extends State<MerkleTreeDialog> {
  final TextEditingController _txidsController = TextEditingController();

  List<List<String>>? _tree;
  List<List<String>>? _rcbTree;
  String? _formattedText;
  String? _error;
  bool _showRCB = true; // Qt default is checked

  @override
  void initState() {
    super.initState();
    // Auto-populate if initial TxIDs provided
    if (widget.initialTxids != null && widget.initialTxids!.isNotEmpty) {
      _txidsController.text = widget.initialTxids!.join('\n');
      // Auto-calculate on next frame
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _calculateTree();
      });
    }
  }

  @override
  void dispose() {
    _txidsController.dispose();
    super.dispose();
  }

  Future<void> _calculateTree() async {
    final input = _txidsController.text.trim();
    if (input.isEmpty) {
      setState(() => _error = 'Please enter transaction IDs (one per line)');
      return;
    }

    final txids = input.split('\n').map((line) => line.trim()).where((line) => line.isNotEmpty).toList();
    if (txids.isEmpty) {
      setState(() => _error = 'Please enter at least one transaction ID');
      return;
    }
    for (final txid in txids) {
      if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(txid)) {
        setState(() => _error = 'Invalid transaction ID format: $txid\n(must be 64 hex characters)');
        return;
      }
    }

    setState(() {
      _error = null;
      _tree = null;
      _rcbTree = null;
      _formattedText = null;
    });

    try {
      final resp = await GetIt.I.get<BitwindowRPC>().utils.calculateMerkleTree(txids, showRCB: _showRCB);
      if (!mounted) {
        return;
      }
      setState(() {
        _tree = resp.levels.map((l) => l.hashes.toList()).toList();
        _rcbTree = resp.levels.any((l) => l.rcb.isNotEmpty) ? resp.levels.map((l) => l.rcb.toList()).toList() : null;
        _formattedText = resp.formattedText;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Failed to calculate Merkle tree: $e');
      }
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    showSailToast(context, '$label copied to clipboard');
  }

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);

    return SailModal(
      child: Container(
        width: 900,
        constraints: const BoxConstraints(maxHeight: 800),
        padding: const EdgeInsets.all(SailStyleValues.padding16),
        decoration: BoxDecoration(
          color: theme.colors.backgroundSecondary,
          borderRadius: theme.chrome.radiusLarge,
          border: Border.all(color: theme.colors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: SailText.primary15('Merkle Tree', bold: true)),
                SailIconBoxButton(
                  icon: SailSVGAsset.x,
                  tooltip: 'Close',
                  onPressed: () async => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: SailStyleValues.padding12),
            Flexible(
              child: InlineTabBar(
                initialIndex: 0,
                tabs: [
                  TabItem(
                    label: 'Merkle Tree',
                    child: _TreeTab(
                      txidsController: _txidsController,
                      tree: _tree,
                      rcbTree: _rcbTree,
                      formattedText: _formattedText,
                      error: _error,
                      expectedRoot: widget.expectedRoot,
                      onCalculate: _calculateTree,
                      onCopy: _copyToClipboard,
                      onInputChanged: () {
                        if (_tree != null || _error != null) {
                          setState(() {
                            _tree = null;
                            _rcbTree = null;
                            _error = null;
                          });
                        }
                      },
                    ),
                  ),
                  const TabItem(label: 'Help', child: _HelpTab()),
                ],
              ),
            ),
            const SizedBox(height: SailStyleValues.padding12),
            Row(
              children: [
                SailCheckbox(
                  value: _showRCB,
                  label: 'Display RCB',
                  onChanged: (value) {
                    setState(() => _showRCB = value);
                    if (_tree != null) {
                      unawaited(_calculateTree());
                    }
                  },
                ),
                const SizedBox(width: 8),
                SailTooltip(
                  message:
                      'Reversed & Concatenated Bytes\n'
                      'Used for manual verification with hash calculators',
                  child: SailSVG.fromAsset(SailSVGAsset.info, width: 16, color: theme.colors.textSecondary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Mono text on the grey field fill, as the tree and the help diagrams.
class _MonoBox extends StatelessWidget {
  final String text;

  const _MonoBox(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(SailStyleValues.padding12),
      decoration: BoxDecoration(color: theme.colors.background, borderRadius: theme.chrome.radius),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SailSelectableText(
          text,
          style: TextStyle(fontFamily: SailFonts.mono, fontSize: 11, color: theme.colors.text, height: 1.5),
        ),
      ),
    );
  }
}

class _TreeTab extends StatelessWidget {
  final TextEditingController txidsController;
  final List<List<String>>? tree;
  final List<List<String>>? rcbTree;
  final String? formattedText;
  final String? error;
  final String? expectedRoot;
  final VoidCallback onCalculate;
  final void Function(String text, String label) onCopy;
  final VoidCallback onInputChanged;

  const _TreeTab({
    required this.txidsController,
    required this.tree,
    required this.rcbTree,
    required this.formattedText,
    required this.error,
    required this.expectedRoot,
    required this.onCalculate,
    required this.onCopy,
    required this.onInputChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);

    final root = tree?.last.first;
    final rootMatches = root != null && expectedRoot != null && root.toLowerCase() == expectedRoot!.toLowerCase();

    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: SailStyleValues.padding12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SailText.primary13('Transaction IDs', bold: true),
          const SizedBox(height: SailStyleValues.padding08),
          SailText.secondary12('Enter transaction IDs (TxIDs) one per line - 64 hex characters each'),
          const SizedBox(height: SailStyleValues.padding12),
          SailTextField(
            controller: txidsController,
            hintText:
                'bd3a498beaca2b118b90f372c03ddf926cf167c3d97db260f4be32e3973a4ac1\n'
                '7c1a4b6f9a2e3d8c5b4a3f2e1d9c8b7a6f5e4d3c2b1a0f9e8d7c6b5a4f3e2d1c',
            monospace: true,
            minLines: 4,
            maxLines: 8,
            onChanged: (_) => onInputChanged(),
          ),
          const SizedBox(height: SailStyleValues.padding12),
          SailButton(onPressed: () async => onCalculate(), label: 'Calculate Merkle Tree'),
          if (error != null) ...[
            const SizedBox(height: SailStyleValues.padding12),
            SailAlert(
              variant: SailAlertVariant.destructive,
              icon: SailSVG.fromAsset(SailSVGAsset.circleAlert, width: 24, color: theme.colors.error),
              description: error!,
            ),
          ],
          if (root != null) ...[
            const SizedBox(height: SailStyleValues.padding16),
            Row(
              children: [
                SailText.primary13('Merkle Tree', bold: true),
                const SizedBox(width: SailStyleValues.padding08),
                SailDetailCopyIcon(onCopy: () => onCopy(formattedText ?? '', 'Merkle tree')),
              ],
            ),
            const SizedBox(height: SailStyleValues.padding08),
            SizedBox(width: double.infinity, child: _MonoBox(formattedText ?? '')),
            const SizedBox(height: SailStyleValues.padding12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SailText.primary13('Merkle Root:', bold: true),
                const SizedBox(width: SailStyleValues.padding08),
                Expanded(
                  child: SailSelectableText(
                    root,
                    style: TextStyle(fontFamily: SailFonts.mono, fontSize: 13, color: theme.colors.text),
                  ),
                ),
              ],
            ),
            if (expectedRoot != null) ...[
              const SizedBox(height: SailStyleValues.padding12),
              SailText.primary13(
                rootMatches ? 'Merkle root matches block header ✓' : 'Merkle root MISMATCH ✗',
                color: rootMatches ? theme.colors.success : theme.colors.error,
              ),
              const SizedBox(height: SailStyleValues.padding08),
              SailDetailGroup(
                fill: SailDetailFill.canvas,
                children: [
                  SailDetailLine(wrap: true, label: 'Expected:', value: expectedRoot!),
                  SailDetailLine(wrap: true, label: 'Calculated:', value: root),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _HelpTab extends StatelessWidget {
  const _HelpTab();

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: SailStyleValues.padding12),
      child: Container(
        padding: const EdgeInsets.all(SailStyleValues.padding16),
        decoration: BoxDecoration(
          color: theme.colors.backgroundSecondary,
          borderRadius: theme.chrome.radiusLarge,
          border: Border.all(color: theme.colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SailText.primary13('How to Use the Merkle Tree Visualizer', bold: true),
            const SizedBox(height: SailStyleValues.padding12),

            SailSelectableText(
              'This window allows you to audit the "hashMerkleRoot" field. '
              'You can see each step of the process yourself.\n\n'
              '         MerkleRoot = hashZ\n\n'
              '                hashZ\n'
              '               /    \\\n'
              '              /      \\\n'
              '           hashX       hashY |\n'
              '           /   \\         \\\n'
              '          /     \\         \\\n'
              '         /       \\         \\\n'
              '     hashF       hashG  |   hashH\n'
              '    /   \\       /     \\      \\\n'
              'hashA  hashB | hashC  hashD | hashE\n\n'
              'Notes:\n'
              '1. hashF = Sha256D ( hashA, hashB )\n'
              '   Each node in the tree is the hash of the two nodes beneath it.\n\n'
              '2. hashY = Sha256D ( hashH, hashH )\n'
              '   If there is an odd number of nodes at that level, the final node is hashed with itself.\n\n'
              '3. Hashes A through E are TxIDs -- the hashes of each transaction.\n\n'
              'Use the Hash Calculator to check that the Sha256D hash of the first two TxIDs '
              'is the value one level above it. And so on ad infinitum.',
              style: TextStyle(
                fontFamily: SailFonts.mono,
                fontSize: 13,
                color: theme.colors.text,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),

            SailText.primary13('What is RCB?', bold: true),
            const SizedBox(height: 12),
            SailSelectableText(
              'Computers sometimes have a crazy way of reading from their computer memory, '
              'related to something called "endianness".\n\n'
              'For whatever reason, Bitcoin merkle root hash calculations run like this:\n\n'
              'Hashes:          ... | hash01 hash02 | ...\n'
              'Reversed Bytes:  ... | 01shha 02shha | ...\n'
              'Next Level:      ... | Sha256D("01shha02shha") | ...\n\n'
              'For convenience, we provide both the "original bytes" and the "Reversed Concatenated" bytes (RCB).\n'
              'You can just paste the latter into our Sha256D Hash Calculator.\n\n'
              'If you want to do everything yourself, copy one TxID, reverse the hex using our hash calculator '
              '"flip hex" button and do the same to the second TxID. Concatenate the reversed hashes and then '
              'paste that into the Sha256D section of the hash calculator to calculate one hash for the next level of the tree.',
              style: TextStyle(
                fontFamily: SailFonts.mono,
                fontSize: 13,
                color: theme.colors.text,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),

            SailText.primary13('Further Reading', bold: true),
            const SizedBox(height: 12),
            SailSelectableText(
              '• https://en.bitcoinwiki.org/wiki/Merkle_tree\n'
              '• https://www.investopedia.com/terms/m/merkle-tree.asp\n'
              '• https://www.geeksforgeeks.org/introduction-to-merkle-tree/',
              style: TextStyle(
                fontFamily: SailFonts.mono,
                fontSize: 13,
                color: theme.colors.text,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
