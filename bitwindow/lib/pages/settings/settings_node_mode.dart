import 'package:auto_route/auto_route.dart';
import 'package:bitwindow/widgets/node_mode_chip.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/pages/router.gr.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/gen/walletmanager/v1/walletmanager.pb.dart' as wmpb;

class SettingsNodeMode extends StatefulWidget {
  const SettingsNodeMode({super.key});

  @override
  State<SettingsNodeMode> createState() => _SettingsNodeModeState();
}

class _SettingsNodeModeState extends State<SettingsNodeMode> {
  NodeModeProvider get _nodeMode => GetIt.I.get<NodeModeProvider>();
  bool _switching = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nodeMode.addListener(setstate);
  }

  @override
  void dispose() {
    _nodeMode.removeListener(setstate);
    super.dispose();
  }

  void setstate() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _switchTo(wmpb.NodeMode next) async {
    // A Bitcoin Core wallet reads its balance from the local node. Light mode
    // stops that node, so the wallet would go dark with no way to spend.
    if (next == wmpb.NodeMode.NODE_MODE_LIGHT && _activeWalletNeedsCore) {
      setState(() {
        _error =
            'Your active wallet is served by Bitcoin Core, which light mode stops. '
            'Switch to an electrum wallet first.';
      });
      return;
    }

    // The router stays valid if the user leaves this page.
    final router = context.router;

    final confirmed = await _confirm(next);
    if (!confirmed) {
      return;
    }

    setState(() {
      _switching = true;
      _error = null;
    });
    try {
      if (next == wmpb.NodeMode.NODE_MODE_FULL) {
        final conf = GetIt.I.get<BitcoinConfProvider>();
        await conf.loadConfig();
        if (fullModeNeedsDataDir(conf)) {
          final selected = mounted && SailTheme.of(context).isBitwindowV2
              ? await showDataDirDialog(context, conf.network)
              : await router.push<bool>(DataDirSetupRoute(network: conf.network));
          await conf.loadConfig();
          if (selected != true || !conf.hasDataDirFor(conf.network)) {
            return;
          }
        }
      }
      await _nodeMode.select(next);
    } catch (e) {
      _showError('$e');
    } finally {
      if (mounted) {
        setState(() => _switching = false);
      }
    }
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }
    setState(() => _error = message);
  }

  /// True when the active wallet reads its chain from the local node.
  bool get _activeWalletNeedsCore {
    final active = GetIt.I.get<WalletReaderProvider>().activeWallet;
    return active != null && !active.isElectrum;
  }

  Future<bool> _confirm(wmpb.NodeMode next) async {
    final toFull = next == wmpb.NodeMode.NODE_MODE_FULL;
    return await widgetDialog<bool>(
          context: context,
          title: toFull ? 'Switch to full mode' : 'Switch to light mode',
          child: Builder(
            builder: (ctx) => SailColumn(
              spacing: SailStyleValues.padding16,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SailText.secondary13(
                  toFull
                      ? 'BitWindow downloads Bitcoin Core and the enforcer, then syncs the chain. '
                            'That takes hours and hundreds of gigabytes. You can leave this page while it runs.'
                      : _nodeMode.remoteEnforcerAvailable
                      ? 'BitWindow stops Bitcoin Core and the local enforcer. Local sidechains use the remote enforcer. '
                            'Your Bitcoin wallet uses Electrum. Your chain data stays on disk.'
                      : 'BitWindow stops Bitcoin Core and the local enforcer. '
                            'Your Bitcoin wallet uses Electrum. Your chain data stays on disk.',
                ),
                SailText.secondary13('No wallet and no key is deleted.'),
                SizedBox(
                  width: double.infinity,
                  child: SailButton(label: 'Switch', onPressed: () async => Navigator.of(ctx).pop(true)),
                ),
              ],
            ),
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final isFull = _nodeMode.isFull;

    return SailColumn(
      spacing: SailStyleValues.padding16,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SailSettingsGroup(
          title: 'Node mode',
          description: _nodeMode.remoteEnforcerAvailable
              ? 'Both modes run local sidechains. Light mode uses a remote enforcer and an Electrum Bitcoin wallet.'
              : 'Light mode uses an Electrum Bitcoin wallet.',
          children: [
            SailSettingsRow(
              label: 'Full mode',
              description: 'Runs Bitcoin Core and the enforcer locally. Uses about 1 TB of disk.',
              trailing: _ModeToggle(
                value: isFull,
                // The row below says light mode is unavailable here, so the
                // toggle must not offer a switch the backend refuses.
                enabled: _nodeMode.lightModeAvailable && (_nodeMode.localBuildsAvailable || isFull) && !_switching,
                onChanged: (on) => _switchTo(
                  on ? wmpb.NodeMode.NODE_MODE_FULL : wmpb.NodeMode.NODE_MODE_LIGHT,
                ),
              ),
            ),
            if (!_nodeMode.lightModeAvailable)
              SailSettingsRow(
                label: 'Light mode is unavailable here',
                description: 'This network has no remote enforcer or Bitcoin wallet server, so it uses full mode.',
              ),
            if (!_nodeMode.localBuildsAvailable)
              SailSettingsRow(
                label: 'Full mode is unavailable here',
                description: noLocalBuildsLine,
              ),
            if (_error != null)
              SailSettingsRow(
                label: 'Could not switch',
                description: _error,
                descriptionColor: SailTheme.of(context).colors.error,
              ),
          ],
        ),
      ],
    );
  }
}

class _ModeToggle extends StatelessWidget {
  final bool value;
  final bool enabled;
  final ValueSetter<bool> onChanged;

  const _ModeToggle({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: IgnorePointer(
        ignoring: !enabled,
        child: SailToggle(value: value, onChanged: onChanged),
      ),
    );
  }
}

/// Asks for the data directory of [network] in a dialog. True once it is saved.
Future<bool?> showDataDirDialog(BuildContext context, BitcoinNetwork network) => widgetDialog<bool>(
  context: context,
  title: 'Configure Data Directory',
  maxWidth: 440,
  child: DataDirDialogBody(network: network),
);

/// The body of [showDataDirDialog]: the field, Browse, and Continue.
class DataDirDialogBody extends StatefulWidget {
  final BitcoinNetwork network;

  const DataDirDialogBody({super.key, required this.network});

  @override
  State<DataDirDialogBody> createState() => _DataDirDialogBodyState();
}

class _DataDirDialogBodyState extends State<DataDirDialogBody> {
  final DataDirSelection _selection = DataDirSelection();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selection.addListener(_onChange);
  }

  @override
  void dispose() {
    _selection.removeListener(_onChange);
    _selection.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _continue() async {
    setState(() => _saving = true);
    final saved = await _selection.save(widget.network);
    if (!mounted) {
      return;
    }
    setState(() => _saving = false);
    if (saved) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    return SailColumn(
      spacing: SailStyleValues.padding16,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SailText.secondary13(
          '${widget.network.toDisplayName()} requires a data directory to store blockchain data.\n'
          'This will require significant disk space (700GB+ for mainnet).',
        ),
        SailColumn(
          spacing: SailStyleValues.padding12,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: DataDirField(path: _selection.selectedPath)),
                const SizedBox(width: 8),
                SailButton(
                  label: 'Browse',
                  variant: ButtonVariant.secondary,
                  loading: _selection.selecting,
                  disabled: _saving,
                  onPressed: _selection.browse,
                ),
              ],
            ),
            if (_selection.error != null) SailText.secondary12(_selection.error!, color: theme.colors.error),
          ],
        ),
        SailButton(
          label: 'Continue',
          loading: _saving,
          onPressed: _continue,
        ),
      ],
    );
  }
}
