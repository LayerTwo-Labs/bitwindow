import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/pages/sidechains/sidechain_overview_page.dart';
import 'package:sail_ui/sail_ui.dart';

@RoutePage()
class BlockExplorerPage extends StatelessWidget {
  const BlockExplorerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return QtPage(
      child: ViewModelBuilder<BlockExplorerViewModel>.reactive(
        viewModelBuilder: () => BlockExplorerViewModel(),
        builder: (context, model, child) {
          final note = model.errorMessage != null && model.block != null;
          return SailCard(
            title: 'Block Explorer',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _BlockNavigationControls(model: model),
                const SizedBox(height: SailStyleValues.padding12),
                if (model.errorMessage != null) ...[
                  SidechainNotice(
                    message: model.errorMessage!,
                    tone: note ? SidechainNoticeTone.warning : SidechainNoticeTone.error,
                  ),
                  const SizedBox(height: SailStyleValues.padding12),
                ],
                if (model.block != null)
                  Expanded(child: _BlockDetails(model: model))
                else if (model.errorMessage == null)
                  const Padding(
                    padding: EdgeInsets.all(SailStyleValues.padding16),
                    child: Center(child: SailCircularProgressIndicator()),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _BlockNavigationControls extends StatelessWidget {
  final BlockExplorerViewModel model;

  const _BlockNavigationControls({required this.model});

  @override
  Widget build(BuildContext context) {
    return SailRow(
      spacing: SailStyleValues.padding08,
      children: [
        SailIconBoxButton(
          icon: SailSVGAsset.chevronLeft,
          tooltip: 'Previous block',
          size: 36,
          onPressed: model.canGoBack ? () async => model.goBack() : null,
        ),
        SizedBox(
          width: 100,
          child: SailTextField(
            controller: model.heightController,
            hintText: 'Height',
            onSubmitted: (_) => model.goToHeight(),
          ),
        ),
        SailIconBoxButton(
          icon: SailSVGAsset.chevronRight,
          tooltip: 'Next block',
          size: 36,
          onPressed: model.canGoForward ? () async => model.goForward() : null,
        ),
        SailButton(
          label: 'Latest',
          variant: ButtonVariant.secondary,
          onPressed: () async => model.goToLatest(),
        ),
        const SizedBox(width: SailStyleValues.padding04),
        SailText.secondary13('Block ${model.currentHeight} of ${model.maxHeight ?? "?"}'),
      ],
    );
  }
}

class _BlockDetails extends StatelessWidget {
  final BlockExplorerViewModel model;

  const _BlockDetails({required this.model});

  @override
  Widget build(BuildContext context) {
    final block = model.block!;
    final formatter = GetIt.I<FormatterProvider>();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BlockInfoRow(label: 'Block hash', value: block['hash']?.toString() ?? '-', selectable: true),
          _BlockInfoRow(label: 'Merkle root', value: block['merkle_root']?.toString() ?? '-', selectable: true),
          _BlockInfoRow(label: 'Prev side hash', value: block['prev_side_hash']?.toString() ?? '-', selectable: true),
          _BlockInfoRow(label: 'Prev main hash', value: block['prev_main_hash']?.toString() ?? '-', selectable: true),
          _BlockInfoRow(
            label: 'Num transactions',
            value: (block['num_transactions'] ?? block['transactions']?.length ?? 0).toString(),
          ),
          _BlockInfoRow(label: 'Coinbase value', value: _formatCoinbaseValue(block['coinbase_value'], formatter)),
          _BlockInfoRow(label: 'Body size', value: _formatSize(block['body_size'] as int?)),
          _BlockInfoRow(label: 'Num sigops', value: (block['num_sigops'] ?? 0).toString()),
          if (block['body_size_limit'] != null)
            _BlockInfoRow(label: 'Body size limit', value: _formatSize(block['body_size_limit'] as int?)),
          if (block['body_sigops_limit'] != null)
            _BlockInfoRow(label: 'Body sigops limit', value: (block['body_sigops_limit']).toString()),
          if (block['utreexo_accumulator'] != null) ...[
            const _BlockInfoRow(label: 'Utreexo accumulator', value: ''),
            const SizedBox(height: SailStyleValues.padding12),
            Container(
              padding: const EdgeInsets.all(SailStyleValues.padding12),
              decoration: BoxDecoration(
                color: SailTheme.of(context).colors.formField,
                borderRadius: SailTheme.of(context).chrome.radius,
              ),
              child: SailSelectableText(block['utreexo_accumulator'].toString(), monospace: true),
            ),
          ],
        ],
      ),
    );
  }

  String _formatCoinbaseValue(dynamic value, FormatterProvider formatter) {
    if (value == null) return '-';
    if (value is int) {
      return formatter.formatSats(value);
    }
    return value.toString();
  }

  String _formatSize(int? bytes) {
    if (bytes == null) return '-';
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)} KiB';
    } else {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MiB';
    }
  }
}

/// One label and value line with a hairline under it.
class _BlockInfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool selectable;

  const _BlockInfoRow({required this.label, required this.value, this.selectable = false});

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 43),
      padding: const EdgeInsets.symmetric(vertical: SailStyleValues.padding08),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.colors.divider)),
      ),
      child: Row(
        children: [
          SizedBox(width: 182, child: SailText.secondary13('$label:')),
          Expanded(
            child: selectable ? SailSelectableText(value, monospace: true) : SailText.primary13(value, monospace: true),
          ),
          if (selectable && value != '-') CopyButton(text: value),
        ],
      ),
    );
  }
}

class BlockExplorerViewModel extends BaseViewModel {
  PhotonRPC get _rpc => GetIt.I.get<PhotonRPC>();

  final TextEditingController heightController = TextEditingController();

  int currentHeight = 0;
  int? maxHeight;
  Map<String, dynamic>? block;
  String? errorMessage;

  bool get canGoBack => currentHeight > 0;
  bool get canGoForward => maxHeight != null && currentHeight < maxHeight!;

  BlockExplorerViewModel() {
    _init();
  }

  Future<void> _init() async {
    try {
      maxHeight = await _rpc.getBlockCount();
      currentHeight = maxHeight ?? 0;
      heightController.text = currentHeight.toString();
      await _fetchBlock();
    } catch (e) {
      errorMessage = e.toString();
      notifyListeners();
    }
  }

  Future<void> _fetchBlock() async {
    errorMessage = null;
    block = null;
    notifyListeners();

    try {
      final bestHash = await _rpc.getBestSidechainBlockHash();
      if (bestHash == null) {
        errorMessage = 'Could not get best hash';
        notifyListeners();
        return;
      }

      // For now, we can only fetch the current best block
      // The RPC needs block hash, and we'd need a getblockhash(height) method
      // to navigate by height. For now, show the best block.
      if (currentHeight == maxHeight) {
        block = await _rpc.getBlock(bestHash);
      } else {
        // Try to get block by constructing from the response
        // This is a limitation - we may need additional RPC methods
        block = await _rpc.getBlock(bestHash);
        errorMessage = 'Note: Block navigation by height requires additional RPC support. Showing best block.';
      }

      notifyListeners();
    } catch (e) {
      errorMessage = e.toString();
      notifyListeners();
    }
  }

  void goBack() {
    if (canGoBack) {
      currentHeight--;
      heightController.text = currentHeight.toString();
      _fetchBlock();
    }
  }

  void goForward() {
    if (canGoForward) {
      currentHeight++;
      heightController.text = currentHeight.toString();
      _fetchBlock();
    }
  }

  Future<void> goToLatest() async {
    try {
      maxHeight = await _rpc.getBlockCount();
      currentHeight = maxHeight ?? 0;
      heightController.text = currentHeight.toString();
      await _fetchBlock();
    } catch (e) {
      errorMessage = e.toString();
      notifyListeners();
    }
  }

  void goToHeight() {
    final height = int.tryParse(heightController.text);
    if (height != null && height >= 0 && (maxHeight == null || height <= maxHeight!)) {
      currentHeight = height;
      _fetchBlock();
    }
  }

  @override
  void dispose() {
    heightController.dispose();
    super.dispose();
  }
}
