import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:sail_ui/sail_ui.dart';

class ChainSettingsModal extends StatefulWidget {
  final RPCConnection connection;
  final VoidCallback? onOpenConfConfigurator;

  /// True when another host runs the daemon, so no local binary exists.
  final bool remote;

  const ChainSettingsModal({
    super.key,
    required this.connection,
    this.onOpenConfConfigurator,
    this.remote = false,
  });

  @override
  State<ChainSettingsModal> createState() => _ChainSettingsModalState();
}

class _ChainSettingsModalState extends State<ChainSettingsModal> {
  List<String> args = [];
  String? _binaryVersion;
  String? _resolvedBinaryPath;
  bool _loadingVersion = true;

  final TextEditingController _resetTarget = TextEditingController();
  int? _chainHeight;
  int? _enforcerHeight;
  bool _chainHeightFailed = false;
  bool _enforcerFailed = false;
  String? _error;
  // The last progress message. A finished reset keeps its result on screen.
  ResetToBlockResponse? _reset;
  StreamSubscription<ResetToBlockResponse>? _resetStream;

  bool get _resetting => _resetStream != null;

  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _loadArgs();
    if (widget.remote) {
      _loadingVersion = false;
    } else {
      _loadBinaryVersion();
    }
    _loadChainHeight();
    _resetTarget.addListener(_clearNoTarget);
  }

  void _clearNoTarget() {
    if (_error == _noTargetError && _resetTarget.text.isNotEmpty) {
      setState(() => _error = null);
    }
  }

  @override
  void dispose() {
    unawaited(_resetStream?.cancel());
    _resetTarget.dispose();
    super.dispose();
  }

  Future<void> _loadArgs() async {
    final loadedArgs = await widget.connection.binaryArgs();
    // Create a mutable copy since extraBootArgs may be const
    final mutableArgs = List<String>.from(loadedArgs);
    mutableArgs.removeWhere((arg) => arg.contains('pass'));
    if (mounted) {
      setState(() {
        args = mutableArgs;
      });
    }
  }

  Future<void> _loadBinaryVersion() async {
    setState(() {
      _loadingVersion = true;
    });

    try {
      final binaryProvider = GetIt.I.get<BinaryProvider>();
      final binary = widget.connection.binary;

      // The orchestrator owns path resolution and runs --version; the frontend
      // never guesses. Sidechains (L2) pass forceBackend so we read the real
      // Rust node version, not the Flutter test build (which has no --version).
      final name = binaryProvider.orchestratorName(binary);
      if (name != null) {
        final resp = await GetIt.I.get<OrchestratorRPC>().getBinaryVersion(
          name,
          forceBackend: binary.chainLayer == 2,
        );
        if (mounted) {
          setState(() {
            _binaryVersion = resp.isTestBuild ? 'Test Sidechain' : resp.version;
            _resolvedBinaryPath = resp.binaryPath.isEmpty ? null : resp.binaryPath;
            _loadingVersion = false;
          });
        }
        return;
      }

      // Daemons without an orchestrator name (none today) fall back to the
      // configured version string.
      if (mounted) {
        setState(() {
          _binaryVersion = binary.version;
          _loadingVersion = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _binaryVersion = 'Error: $e';
          _loadingVersion = false;
        });
      }
    }
  }

  /// The rollback acts on Bitcoin Core's chain, so only Core's own settings
  /// offer it. The enforcer and bitwindowd are layer 1 too, and their modal
  /// must not roll back a chain they do not own.
  bool get _isBitcoinCore => widget.connection.binary.type == BinaryType.BINARY_TYPE_BITCOIND;

  Future<void> _loadChainHeight() async {
    if (!_isBitcoinCore) {
      return;
    }
    // GetSyncStatus keeps serving the last-good numbers through a daemon
    // outage, on purpose, so progress never snaps to zero. That makes its
    // height a poor liveness reading: ask the connection itself first.
    if (!widget.connection.connected) {
      setState(() => _chainHeightFailed = true);
      return;
    }

    try {
      final status = await GetIt.I.get<OrchestratorRPC>().getSyncStatus();
      if (!mounted) {
        return;
      }
      final mainchain = status.mainchain;
      final enforcer = status.enforcer;
      setState(() {
        if (mainchain.error.isNotEmpty) {
          _chainHeightFailed = true;
        } else {
          _chainHeight = mainchain.blocks.toInt();
        }
        // A stopped enforcer reports an error, and its row says so rather than
        // showing a height it never read.
        _enforcerHeight = enforcer.error.isNotEmpty ? null : enforcer.blocks.toInt();
        _enforcerFailed = enforcer.error.isNotEmpty;
      });
    } catch (e) {
      GetIt.I.get<Logger>().d('chain settings: could not read the height: $e');
      if (mounted) {
        setState(() => _chainHeightFailed = true);
      }
    }
  }

  /// Starts a reset. The orchestrator resolves the target, so a bad height or
  /// a bad hash fails before the stream opens.
  Future<void> _startReset(BuildContext context) async {
    final target = _resetTarget.text.trim();
    if (target.isEmpty) {
      setState(() => _error = _noTargetError);
      return;
    }

    BuildContext? confirmContext;
    await widgetDialog(
      context: context,
      title: 'Reset to block $target?',
      maxWidth: 440,
      action: SailDialogAction(
        label: 'Confirm',
        variant: ButtonVariant.destructive,
        onPressed: () async {
          Navigator.of(confirmContext!).pop();
          await _runReset(target);
        },
      ),
      child: Builder(
        builder: (context) {
          confirmContext = context;
          return SailText.secondary13(
            'That block and every block above it leave the active chain, then the node replays them from disk. '
            'The blocks stay on disk, so the replay downloads nothing.',
          );
        },
      ),
    );
  }

  Future<void> _runReset(String target) async {
    setState(() {
      _error = null;
      _reset = null;
    });

    final stream = GetIt.I.get<OrchestratorRPC>().resetToBlock(target: target);
    setState(() {
      _resetStream = stream.listen(
        (msg) {
          if (!mounted) {
            return;
          }
          setState(() {
            _reset = msg;
            if (msg.coreHeight != 0) {
              _chainHeight = msg.coreHeight;
            }
            if (msg.done && msg.enforcerChecked) {
              _enforcerHeight = msg.enforcerHeight;
              _enforcerFailed = false;
            }
          });
        },
        onError: (Object e) {
          if (!mounted) {
            return;
          }
          setState(() {
            _error = '$e';
            _resetStream = null;
          });
        },
        onDone: () {
          if (!mounted) {
            return;
          }
          setState(() {
            _resetStream = null;
            _resetTarget.clear();
          });
          unawaited(_loadChainHeight());
        },
      );
    });
  }

  Future<void> _showWipeReset(BuildContext context, Binary binary) async {
    final binaryProvider = GetIt.I.get<BinaryProvider>();
    final appDir = binaryProvider.appDir;
    final log = GetIt.I.get<Logger>();

    // Wipe everything for this one binary. Wallet included for enforcer and
    // sidechains (moved to wallet_backups/ server-side); excluded for bitcoind
    // and bitwindow, whose L1 wallet is only ever wiped from the reset page.
    final deletions = <DeletionType>[
      DeletionType.DELETION_TYPE_DATA,
      DeletionType.DELETION_TYPE_SETTINGS,
      DeletionType.DELETION_TYPE_LOGS,
      DeletionType.DELETION_TYPE_SOFTWARE,
      if (binary.type != BinaryType.BINARY_TYPE_BITCOIND && binary.type != BinaryType.BINARY_TYPE_BITWINDOWD)
        DeletionType.DELETION_TYPE_WALLET,
    ];

    final resetStarted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ResetConfirmationPage(
          request: [SingleDeletion(binary: binary.type, deletions: deletions)],
          appDir: appDir,
          binaryProvider: binaryProvider,
          log: log,
        ),
      ),
    );

    if (!context.mounted) {
      return;
    }

    if (resetStarted == true) {
      Navigator.of(context).pop();
    }
  }

  String _port() {
    if (widget.connection.binary.port != 0) {
      return widget.connection.binary.port.toString();
    }
    return CoreConnectionSettings.empty(
      GetIt.I.get<BitcoinConfProvider>().network,
    ).port.toString();
  }

  String _chainLayer(Binary binary) {
    switch (binary.chainLayer) {
      case 0:
        return 'Utility';
      case 1:
        return 'Layer 1';
      default:
        return 'Layer 2';
    }
  }

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<ChainSettingsViewModel>.reactive(
      viewModelBuilder: () => ChainSettingsViewModel(widget.connection.binary),
      builder: (context, viewModel, child) {
        final theme = SailTheme.of(context);
        final binary = viewModel.binary;
        final version = _loadingVersion ? 'Loading...' : (_binaryVersion ?? binary.version);
        final menu = _menuItems(context, viewModel);
        final tabs = [
          (
            'Overview',
            () => widget.remote
                ? _RemoteOverviewTab(binary: binary)
                : _OverviewTab(viewModel: viewModel, version: version),
          ),
          if (!widget.remote)
            ('Paths', () => _PathsTab(viewModel: viewModel, args: args, resolvedBinaryPath: _resolvedBinaryPath)),
          if (_isBitcoinCore)
            (
              'Chain',
              () {
                final height = _chainHeight?.toString() ?? (_chainHeightFailed ? 'Unavailable' : 'Loading...');
                final enforcer =
                    _enforcerHeight?.toString() ??
                    (_chainHeightFailed || _enforcerFailed ? 'Unavailable' : 'Loading...');
                final noTarget = _error == _noTargetError;

                return SailColumn(
                  spacing: SailStyleValues.padding12,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _FieldGroup(
                      children: [
                        _FieldRow(label: 'Network', value: GetIt.I.get<BitcoinConfProvider>().network.name),
                        _FieldRow(label: 'Core height', value: height),
                        _FieldRow(label: 'Enforcer height', value: enforcer),
                      ],
                    ),
                    SailColumn(
                      spacing: SailStyleValues.padding08,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SailText.primary13('Reset to Block', bold: true),
                        SailText.secondary13(
                          'Give a height or a block hash. The node moves back to that block, then syncs forward to the tip again. '
                          'The blocks stay on disk, so it downloads nothing.',
                        ),
                      ],
                    ),
                    SailRow(
                      spacing: SailStyleValues.padding08,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: SailTextField(
                            controller: _resetTarget,
                            hintText: 'Height or block hash',
                            enabled: !_resetting,
                            errorText: noTarget ? _noTargetError : null,
                          ),
                        ),
                        SailButton(
                          label: 'Reset to Block',
                          variant: ButtonVariant.outline,
                          onPressed: _resetting ? null : () async => _startReset(context),
                          loading: _resetting,
                          loadingLabel: _resetLoadingLabel(),
                        ),
                      ],
                    ),
                    ?_resetStatus(theme, noTarget),
                  ],
                );
              },
            ),
        ];
        final tab = _tab.clamp(0, tabs.length - 1);
        final maxHeight = MediaQuery.sizeOf(context).height * 0.85;

        return Dialog(
          backgroundColor: theme.colors.backgroundSecondary,
          shape: RoundedRectangleBorder(
            borderRadius: theme.chrome.radiusLarge,
            side: BorderSide(color: theme.colors.border),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 640, maxHeight: maxHeight),
            child: Padding(
              padding: const EdgeInsets.all(SailStyleValues.padding16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SailColumn(
                    spacing: SailStyleValues.padding12,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SailRow(
                        spacing: SailStyleValues.padding08,
                        children: [
                          Expanded(child: SailText.primary16(binary.name, bold: true)),
                          if (menu.isNotEmpty) SailRowMenuButton(items: () => _menuItems(context, viewModel)),
                          SailIconBoxButton(
                            icon: SailSVGAsset.x,
                            tooltip: 'Close',
                            onPressed: () async => Navigator.pop(context),
                          ),
                        ],
                      ),
                      SailText.secondary13(
                        widget.remote
                            ? '${_chainLayer(binary)} · remote'
                            : '${_chainLayer(binary)} · 127.0.0.1:${_port()} · version $version',
                      ),
                    ],
                  ),
                  const SailSpacing(SailStyleValues.padding12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SailSegments(
                      labels: [for (final (label, _) in tabs) label],
                      activeIndex: tab,
                      onSelect: (index) => setState(() => _tab = index),
                    ),
                  ),
                  const SailSpacing(SailStyleValues.padding12),
                  Flexible(child: SingleChildScrollView(child: tabs[tab].$2())),
                  if (viewModel.showUpdateButton || viewModel.isUpdating) ...[
                    const SailSpacing(SailStyleValues.padding16),
                    SailDialogActionButton(
                      action: SailDialogAction(
                        label: 'Update',
                        loadingLabel: viewModel.isUpdating ? 'Updating' : null,
                        onPressed: () async {
                          if (!viewModel.isUpdating) {
                            await viewModel.handleUpdate(context);
                          }
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<SailMenuEntity> _menuItems(BuildContext context, ChainSettingsViewModel viewModel) {
    final theme = SailTheme.of(context);
    return [
      if (!widget.remote)
        SailMenuItem(
          onSelected: () => unawaited(_showWipeReset(context, viewModel.binary)),
          child: SailTooltip(
            message: 'Wipe ${viewModel.binary.name} binary, data, and wallets, then reinstall',
            child: SailText.primary13('Wipe and reinstall', color: theme.colors.error),
          ),
        ),
      if (widget.onOpenConfConfigurator != null)
        SailMenuItem(
          onSelected: () {
            Navigator.pop(context);
            widget.onOpenConfConfigurator!();
          },
          child: SailText.primary13('Open configurator'),
        ),
    ];
  }

  String _resetLoadingLabel() {
    return switch (_reset?.phase) {
      ResetPhase.RESET_PHASE_SYNC_FORWARD => 'Syncs forward',
      ResetPhase.RESET_PHASE_ENFORCER => 'Enforcer',
      _ => 'Moves back',
    };
  }

  /// The area under the field: the failure, the live progress, or the result.
  Widget? _resetStatus(SailThemeData theme, bool noTarget) {
    if (noTarget) {
      return null;
    }
    if (_error != null) {
      return _ResetArea(children: [SailText.secondary12(_error!, color: theme.colors.error)]);
    }

    final reset = _reset;
    if (reset == null) {
      return SailText.secondary12(
        'A height names the block on the chain this node follows today. Paste a hash to name one exactly.',
      );
    }

    if (reset.done) {
      final enforcerError = reset.enforcerError.isNotEmpty;
      return _ResetArea(
        children: [
          SailText.primary12(reset.message, bold: true),
          SailText.secondary12(
            _enforcerResult(reset),
            color: enforcerError
                ? theme.colors.error
                : reset.enforcerChecked && !reset.enforcerRebuilt
                ? theme.colors.success
                : null,
          ),
        ],
      );
    }

    final forward =
        reset.phase == ResetPhase.RESET_PHASE_SYNC_FORWARD || reset.phase == ResetPhase.RESET_PHASE_ENFORCER;
    return _ResetArea(
      children: [
        SailRow(
          spacing: SailStyleValues.padding12,
          children: [
            _ResetStep(label: 'Moves back', tone: forward ? SailStatusTone.success : SailStatusTone.warning),
            _ResetStep(label: 'Syncs forward', tone: forward ? SailStatusTone.warning : SailStatusTone.neutral),
          ],
        ),
        if (reset.phase == ResetPhase.RESET_PHASE_SYNC_FORWARD && reset.blocksTotal != 0)
          ProgressBar(
            current: reset.blocksDone.toDouble(),
            goal: reset.blocksTotal.toDouble(),
            color: theme.colors.primary,
          ),
        SailText.secondary12(reset.message),
      ],
    );
  }

  String _enforcerResult(ResetToBlockResponse reset) {
    if (reset.enforcerError.isNotEmpty) {
      return 'The enforcer did not follow: ${reset.enforcerError}';
    }
    if (!reset.enforcerChecked) {
      return 'The enforcer reads the chain on its next start.';
    }
    if (reset.enforcerRebuilt) {
      return 'The enforcer rebuilds from the local Core.';
    }
    return "The enforcer sits on Core's chain at ${reset.enforcerHeight}.";
  }
}

const String _noTargetError = 'Give a height or a block hash.';

class _RemoteOverviewTab extends StatelessWidget {
  final Binary binary;

  const _RemoteOverviewTab({required this.binary});

  @override
  Widget build(BuildContext context) {
    return _FieldGroup(
      children: [
        const _FieldRow(label: 'Runs on', value: 'Remote validator'),
        if (binary.repoUrl.isNotEmpty) _FieldRow(label: 'Repository', value: binary.repoUrl, copyable: true),
      ],
    );
  }
}

class _OverviewTab extends StatelessWidget {
  final ChainSettingsViewModel viewModel;
  final String version;

  const _OverviewTab({required this.viewModel, required this.version});

  @override
  Widget build(BuildContext context) {
    final binary = viewModel.binary;
    final network = GetIt.I.get<BitcoinConfProvider>().network;
    var downloadFile = binary.metadata.downloadConfig.files[network]?[viewModel.os];
    final variants = binary.metadata.downloadConfig.variants;
    if (downloadFile == null && variants.isNotEmpty && GetIt.I.isRegistered<CoreVariantProvider>()) {
      final activeId = GetIt.I.get<CoreVariantProvider>().activeId;
      downloadFile = (variants[activeId] ?? variants.values.first)[viewModel.os];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FieldGroup(
          children: [
            _FieldRow(label: 'Version', value: version),
            if (binary.repoUrl.isNotEmpty) _FieldRow(label: 'Repository', value: binary.repoUrl, copyable: true),
            _FieldRow(
              label: 'Latest release at',
              value: binary.metadata.remoteTimestamp?.toLocal().toString() ?? 'N/A',
            ),
            _FieldRow(
              label: 'Installed at',
              value: binary.metadata.downloadedTimestamp?.toLocal().toString() ?? 'N/A',
            ),
            if (downloadFile != null) _FieldRow(label: 'Download file', value: downloadFile, copyable: true),
          ],
        ),
        _HashVerificationSection(downloadInfo: binary.downloadInfo),
      ],
    );
  }
}

class _PathsTab extends StatelessWidget {
  final ChainSettingsViewModel viewModel;
  final List<String> args;
  final String? resolvedBinaryPath;

  const _PathsTab({required this.viewModel, required this.args, required this.resolvedBinaryPath});

  @override
  Widget build(BuildContext context) {
    final binary = viewModel.binary;
    final network = GetIt.I.get<BitcoinConfProvider>().network;
    final baseDir = binary.directories.binary[network]?[viewModel.os];

    return _FieldGroup(
      children: [
        if (baseDir != null) _FieldRow(label: 'Installation directory', value: baseDir, copyable: true),
        _FieldRow(label: 'Data directory', value: binary.datadirNetwork(), copyable: true),
        _FieldRow(label: 'Log path', value: binary.logPath(), copyable: true),
        _FieldRow(
          label: 'Binary asset path',
          // Prefer the path the orchestrator actually resolved (and ran
          // --version against); fall back to the reported status path while
          // that's still loading.
          value: resolvedBinaryPath ?? binary.metadata.binaryPath?.path ?? 'N/A',
          copyable: true,
        ),
        if (args.isNotEmpty) _FieldRow(label: 'Binary arguments', value: args.join(' \\\n'), copyable: true),
      ],
    );
  }
}

/// The grey box that holds the run or the result of a reset.
class _ResetArea extends StatelessWidget {
  final List<Widget> children;

  const _ResetArea({required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(SailStyleValues.padding12),
      decoration: BoxDecoration(color: theme.colors.formField, borderRadius: theme.chrome.radius),
      child: SailColumn(
        spacing: SailStyleValues.padding08,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

/// One step of a reset: a dot that is orange while it runs, green once it is done.
class _ResetStep extends StatelessWidget {
  final String label;
  final SailStatusTone tone;

  const _ResetStep({required this.label, required this.tone});

  @override
  Widget build(BuildContext context) {
    return SailRow(
      spacing: 6,
      children: [
        SailStatusDot(tone: tone),
        SailText.primary12(label),
      ],
    );
  }
}

double _labelWidth(BuildContext context) => SailStyleValues.phoneLayout(context) ? 112 : 150;

/// Detail rows on a grey box, a hairline between two rows.
class _FieldGroup extends StatelessWidget {
  final List<Widget> children;

  const _FieldGroup({required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: SailStyleValues.padding12),
      decoration: BoxDecoration(color: theme.colors.formField, borderRadius: theme.chrome.radius),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, child) in children.indexed) ...[
            if (index > 0) Container(height: 1, color: theme.colors.divider),
            child,
          ],
        ],
      ),
    );
  }
}

/// Label and value on one line, with an optional copy action.
class _FieldRow extends StatelessWidget {
  final String label;
  final String value;
  final bool copyable;

  const _FieldRow({required this.label, required this.value, this.copyable = false});

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SailStyleValues.padding08),
      child: SailRow(
        spacing: SailStyleValues.padding16,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _labelWidth(context),
            child: SailText.secondary13(label),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: SailStyleValues.thirteen.copyWith(color: theme.colors.text),
            ),
          ),
          if (copyable) CopyButton(text: value),
        ],
      ),
    );
  }
}

class _HashVerificationSection extends StatelessWidget {
  final DownloadInfo downloadInfo;

  const _HashVerificationSection({required this.downloadInfo});

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    final localHash = downloadInfo.hash;
    final releaseHash = downloadInfo.expectedHash;
    final isMismatch = downloadInfo.hashMatch == false;

    if (localHash == null && releaseHash == null) {
      return Padding(
        padding: const EdgeInsets.only(top: SailStyleValues.padding16),
        child: SailText.secondary12(
          'No hash data available (re-download to verify)',
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: SailStyleValues.padding16),
        SailText.secondary12('HASH VERIFICATION', bold: true),
        const SizedBox(height: SailStyleValues.padding08),
        _FieldGroup(
          children: [
            if (localHash != null) _HashRow(label: 'Local SHA256', hash: localHash),
            if (releaseHash != null)
              _HashRow(
                label: 'Release server',
                hash: releaseHash,
                isMismatch: localHash != null && releaseHash != localHash,
              ),
          ],
        ),
        const SizedBox(height: SailStyleValues.padding08),
        if (isMismatch)
          SailTooltip(
            message:
                'The downloaded binary does not match the expected hash from the release server. '
                'This could indicate the binary was tampered with or the download was corrupted.',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: SailStyleValues.padding12, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colors.formField,
                borderRadius: theme.chrome.radius,
                border: Border.all(color: theme.colors.error),
              ),
              child: Row(
                children: [
                  const SailStatusDot(tone: SailStatusTone.error),
                  const SizedBox(width: SailStyleValues.padding08),
                  Flexible(child: SailText.primary13('HASH MISMATCH — binary may be compromised')),
                ],
              ),
            ),
          )
        else if (downloadInfo.hashMatch == true)
          SailText.secondary12('Hashes match the release server.', color: theme.colors.success)
        else
          SailText.secondary12('Not compared — one of the two hashes is missing.'),
      ],
    );
  }
}

class _HashRow extends StatelessWidget {
  final String label;
  final String hash;
  final bool isMismatch;

  const _HashRow({
    required this.label,
    required this.hash,
    this.isMismatch = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);

    return SailTooltip(
      message: hash,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: SailStyleValues.padding08),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: _labelWidth(context),
              child: SailText.secondary13(label, color: isMismatch ? theme.colors.error : null),
            ),
            const SizedBox(width: SailStyleValues.padding16),
            Expanded(
              child: SelectableText(
                '${hash.substring(0, 16)}...${hash.substring(hash.length - 16)}',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  color: isMismatch ? theme.colors.error : theme.colors.text,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ChainSettingsViewModel extends BaseViewModel {
  final BinaryProvider _binaryProvider = GetIt.I.get<BinaryProvider>();
  final Binary _binary;
  bool _isUpdating = false;

  ChainSettingsViewModel(this._binary) {
    _binaryProvider.addListener(notifyListeners);
  }

  Binary get binary => _binaryProvider.binaries.firstWhere((b) => b.type == _binary.type);
  bool get isUpdating => _isUpdating;
  Directory get appDir => _binaryProvider.appDir;
  OS get os => getOS();

  // Show update button only if update is available and not currently updating
  bool get showUpdateButton => binary.updateAvailable && !_isUpdating;

  Future<void> handleUpdate(BuildContext context) async {
    if (_isUpdating) {
      return;
    }

    _isUpdating = true;
    notifyListeners();

    try {
      Navigator.of(context).pop();
      await _binaryProvider.update(binary);
    } catch (e) {
      // Handle any errors during the update process
      // You might want to show a snackbar or dialog here
    } finally {
      _isUpdating = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _binaryProvider.removeListener(notifyListeners);
    super.dispose();
  }
}

/// Which call the retry button repeats.
