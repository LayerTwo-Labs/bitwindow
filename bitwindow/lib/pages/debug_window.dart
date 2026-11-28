import 'package:bitwindow/pages/bitwindow_console_tab.dart';
import 'package:bitwindow/widgets/v2_details.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:sidechain_core/gen/bitcoin/bitcoind/v1alpha/bitcoin.pb.dart'
    show GetNetworkInfoResponse, GetNetworkInfoRequest, GetPeerInfoRequest;
import 'package:sail_ui/sail_ui.dart';

class DebugWindow extends StatefulWidget {
  const DebugWindow({
    super.key,
  });

  @override
  State<DebugWindow> createState() => _DebugWindowState();
}

class _DebugWindowState extends State<DebugWindow> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(SailStyleValues.padding12),
      child: InlineTabBar(
        tabs: [
          TabItem(label: 'Information', child: InformationTab()),
          TabItem(label: 'Processes', child: ProcessesTab()),
          TabItem(label: 'Console', child: BitwindowConsoleTab()),
          TabItem(label: 'Network', child: NetworkTab()),
          TabItem(label: 'Peers', child: PeersTab()),
          TabItem(label: 'Binaries', child: BinariesTab()),
        ],
        initialIndex: 0,
      ),
    );
  }
}

class InformationTab extends StatefulWidget {
  const InformationTab({super.key});

  @override
  State<InformationTab> createState() => _InformationTabState();
}

class _InformationTabState extends State<InformationTab> {
  OrchestratorRPC get _orchestrator => GetIt.I.get<OrchestratorRPC>();
  BitcoinConfProvider get _confProvider => GetIt.I.get<BitcoinConfProvider>();

  GetMainchainBlockchainInfoResponse? _blockchainInfo;
  GetNetworkInfoResponse? _networkInfo;
  GetCoreMempoolInfoResponse? _mempoolInfo;

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    try {
      final blockchainInfo = await _orchestrator.getMainchainBlockchainInfo();
      final networkInfo = await _orchestrator.bitcoind.getNetworkInfo(GetNetworkInfoRequest());
      final mempoolInfo = await _orchestrator.getCoreMempoolInfo();

      setState(() {
        _blockchainInfo = blockchainInfo;
        _networkInfo = networkInfo;
        _mempoolInfo = mempoolInfo;
      });
    } catch (e) {
      // do nothing
    }
  }

  @override
  Widget build(BuildContext context) {
    return SailCard(
      title: 'Debug Information',
      subtitle: 'General information about the node',
      child: SingleChildScrollView(
        child: SailColumn(
          spacing: SailStyleValues.padding12,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InfoSection(
              title: 'General Info',
              details: {
                'Client version': _networkInfo?.version.toString() ?? 'Loading...',
                'User Agent': _networkInfo?.subversion ?? 'Loading...',
                'Protocol Version': _networkInfo?.protocolVersion.toString() ?? 'Loading...',
                'Datadir': _confProvider.detectedDataDir ?? 'default',
              },
            ),
            InfoSection(
              title: 'Network Info',
              details: {
                'Chain': _blockchainInfo?.chain ?? 'Loading...',
                'Network Activity': switch (_networkInfo?.networkActive) {
                  null => 'Loading...',
                  true => 'Enabled',
                  false => 'Disabled',
                },
              },
            ),
            InfoSection(
              title: 'Blockchain Info',
              details: {
                'Current number of blocks': _blockchainInfo?.blocks.toString() ?? 'Loading...',
                'Headers': _blockchainInfo?.headers.toString() ?? 'Loading...',
                'Verification Progress': '${((_blockchainInfo?.verificationProgress ?? 0) * 100).toStringAsFixed(0)}%',
                'Difficulty': _blockchainInfo?.difficulty.toString() ?? 'Loading...',
                'Size on Disk': '${_blockchainInfo?.sizeOnDisk.toInt() ?? 0} bytes',
                'Last block time': (_blockchainInfo?.time ?? Int64.ZERO) != Int64.ZERO
                    ? DateTime.fromMillisecondsSinceEpoch(_blockchainInfo!.time.toInt() * 1000).toString()
                    : 'Loading...',
              },
            ),
            InfoSection(
              title: 'Mempool Info',
              details: {
                'Transaction Count': _mempoolInfo?.size.toString() ?? 'Loading...',
                'Memory Usage': '${_mempoolInfo?.usage ?? 0} bytes',
                'Total Fee': '${_mempoolInfo?.totalFee ?? 0} ${activeTicker.symbol}',
                'Min Relay Fee': '${_mempoolInfo?.minRelayTxFee ?? 0} ${activeTicker.symbol}',
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// A bold title over a grey group of label and value rows.
class InfoSection extends StatelessWidget {
  final String title;
  final Map<String, String> details;

  const InfoSection({super.key, required this.title, required this.details});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SailDetailHeading(title),
        const SizedBox(height: SailStyleValues.padding08),
        SailDetailGroup(
          fill: SailDetailFill.canvas,
          children: [for (final e in details.entries) SailDetailLine(wrap: true, label: e.key, value: e.value)],
        ),
      ],
    );
  }
}

class NetworkTab extends StatefulWidget {
  const NetworkTab({super.key});

  @override
  State<NetworkTab> createState() => _NetworkTabState();
}

class _NetworkTabState extends State<NetworkTab> {
  BitwindowRPC get bitwindow => GetIt.I.get<BitwindowRPC>();
  GetNetworkStatsResponse? _networkStats;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNetworkStats();
  }

  Future<void> _loadNetworkStats() async {
    setState(() => _isLoading = true);
    try {
      final stats = await bitwindow.bitwindowd.getNetworkStats();
      setState(() {
        _networkStats = stats;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SailCard(
        title: 'Network Statistics',
        subtitle: 'Bitcoin network and node statistics',
        child: Center(child: LoadingIndicator()),
      );
    }

    if (_networkStats == null) {
      return SailCard(
        title: 'Network Statistics',
        subtitle: 'Bitcoin network and node statistics',
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SailText.secondary13('Failed to load network statistics'),
              const SizedBox(height: 16),
              SailButton(
                label: 'Retry',
                onPressed: () async => _loadNetworkStats(),
              ),
            ],
          ),
        ),
      );
    }

    return SailCard(
      title: 'Network Statistics',
      subtitle: 'Bitcoin network and node statistics',
      widgetHeaderEnd: SailButton(
        label: 'Refresh',
        onPressed: () async => _loadNetworkStats(),
        variant: ButtonVariant.secondary,
      ),
      child: SingleChildScrollView(
        child: SailColumn(
          spacing: SailStyleValues.padding12,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InfoSection(
              title: 'Connection Status',
              details: {
                'Connected Peers': _networkStats!.peerCount.toString(),
                'Inbound Connections': _networkStats!.connectionsIn.toString(),
                'Outbound Connections': _networkStats!.connectionsOut.toString(),
              },
            ),
            InfoSection(
              title: 'Block Information',
              details: {
                'Current Height': _networkStats!.blockHeight.toString(),
                'Average Block Time': '${_networkStats!.avgBlockTime.toStringAsFixed(1)}s',
                'Difficulty': _networkStats!.difficulty.toStringAsFixed(2),
              },
            ),
            InfoSection(
              title: 'Network Activity',
              details: {
                'Total Bytes Received': '${_networkStats!.totalBytesReceived} bytes',
                'Total Bytes Sent': '${_networkStats!.totalBytesSent} bytes',
                'Network Version': _networkStats!.networkVersion.toString(),
              },
            ),
            if (_networkStats!.hasBitcoindBandwidth())
              InfoSection(
                title: 'Bitcoind Process (PID ${_networkStats!.bitcoindBandwidth.pid})',
                details: {
                  'Connections': _networkStats!.bitcoindBandwidth.connectionCount.toString(),
                },
              ),
            if (_networkStats!.hasEnforcerBandwidth())
              InfoSection(
                title: 'Enforcer Process (PID ${_networkStats!.enforcerBandwidth.pid})',
                details: {
                  'Connections': _networkStats!.enforcerBandwidth.connectionCount.toString(),
                },
              ),
          ],
        ),
      ),
    );
  }
}

class PeersTab extends StatefulWidget {
  const PeersTab({super.key});

  @override
  State<PeersTab> createState() => _PeersTabState();
}

class _PeersTabState extends State<PeersTab> {
  OrchestratorRPC get _orchestrator => GetIt.I.get<OrchestratorRPC>();
  List<PeerInfo> peers = [];

  /// The peer in the side panel.
  int? _selected;

  @override
  void initState() {
    super.initState();
    _loadPeers();
  }

  Future<void> _loadPeers() async {
    final resp = await _orchestrator.bitcoind.getPeerInfo(GetPeerInfoRequest());
    setState(() {
      peers = resp.peers.map(PeerInfo.fromProto).toList();
      if (_selected != null && _selected! >= peers.length) {
        _selected = null;
      }
    });
  }

  void _select(String? rowId) {
    if (rowId != null && SailStyleValues.phoneLayout(context)) {
      widgetDialog(
        context: context,
        title: 'Peer Details',
        child: PeerDetailsBody(peer: peers[int.parse(rowId)]),
      );
      return;
    }
    setState(() => _selected = rowId == null ? null : int.parse(rowId));
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final table = SailCard(
      title: 'Peer Information',
      subtitle: 'Connected peers and their details',
      child: SailTable(
        getRowId: (index) => index.toString(),
        selectedRowId: selected?.toString(),
        onSelectedRow: _select,
        headerBuilder: (context) => [
          const SailTableHeaderCell(name: 'ID'),
          const SailTableHeaderCell(name: 'Address'),
          const SailTableHeaderCell(name: 'Network'),
          const SailTableHeaderCell(name: 'Version'),
          const SailTableHeaderCell(name: 'Connection'),
          const SailTableHeaderCell(name: 'Ping'),
        ],
        rowBuilder: (context, row, selected) {
          final peer = peers[row];
          return [
            SailTableCell(value: peer.id.toString()),
            SailTableCell(value: peer.addr),
            SailTableCell(value: peer.network),
            SailTableCell(value: peer.subVer),
            SailTableCell(value: peer.connectionType),
            SailTableCell(value: '${peer.pingTime.toStringAsFixed(3)}s'),
          ];
        },
        rowCount: peers.length,
        emptyPlaceholder: 'No peers connected',
        onDoubleTap: _select,
      ),
    );
    if (SailStyleValues.phoneLayout(context)) {
      return table;
    }
    return SailPageWithPanel(
      panel: selected == null || selected >= peers.length
          ? null
          : SailSidePanel(
              title: 'Peer Details',
              onClose: () async => _select(null),
              child: PeerDetailsBody(peer: peers[selected]),
            ),
      child: table,
    );
  }
}

/// The grey groups of every field of [peer].
class PeerDetailsBody extends StatelessWidget {
  final PeerInfo peer;

  const PeerDetailsBody({super.key, required this.peer});

  @override
  Widget build(BuildContext context) {
    String time(int seconds) => seconds == 0 ? 'Never' : DateTime.fromMillisecondsSinceEpoch(seconds * 1000).toString();
    return SailColumn(
      spacing: SailStyleValues.padding12,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SailText.secondary12('Full details about the peer'),
        InfoSection(
          title: 'Connection',
          details: {
            'ID': peer.id.toString(),
            'Address': peer.addr,
            'Bind Address': peer.addrBind,
            'Local Address': peer.addrLocal,
            'Network': peer.network,
            'Connection Type': peer.connectionType,
            'Transport Protocol': peer.transportProtocolType,
            'Session ID': peer.sessionId,
          },
        ),
        InfoSection(
          title: 'Status',
          details: {
            'Version': peer.version.toString(),
            'Subversion': peer.subVer,
            'Services': peer.services,
            'Service Names': peer.serviceNames.join(', '),
            'Inbound': peer.inbound.toString(),
            'Relay Transactions': peer.relayTxes.toString(),
            'Time Offset': '${peer.timeOffset}s',
            'Ping Time': '${peer.pingTime}s',
            'Min Ping': '${peer.minPing}s',
          },
        ),
        InfoSection(
          title: 'Sync Status',
          details: {
            'Starting Height': peer.startingHeight.toString(),
            'Synced Headers': peer.syncedHeaders.toString(),
            'Synced Blocks': peer.syncedBlocks.toString(),
            'Last Transaction': time(peer.lastTransaction),
            'Last Block': time(peer.lastBlock),
          },
        ),
        InfoSection(
          title: 'Traffic',
          details: {
            'Bytes Sent': '${peer.bytesSent} bytes',
            'Bytes Received': '${peer.bytesRecv} bytes',
            'Last Send': time(peer.lastSend),
            'Last Receive': time(peer.lastRecv),
          },
        ),
      ],
    );
  }
}

class ProcessesTab extends StatefulWidget {
  const ProcessesTab({super.key});

  @override
  State<ProcessesTab> createState() => _ProcessesTabState();
}

class _ProcessesTabState extends State<ProcessesTab> {
  final _drivechaind = DrivechaindState();

  @override
  void dispose() {
    _drivechaind.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final binaryProvider = GetIt.I.get<BinaryProvider>();
    final confProvider = GetIt.I.get<BitcoinConfProvider>();

    return ListenableBuilder(
      listenable: Listenable.merge([_drivechaind, confProvider]),
      builder: (context, _) {
        final allBinaries = binaryProvider.binaries;

        return SailCard(
          title: 'Binaries',
          subtitle: 'Managed by orchestrator',
          child: SailTable(
            getRowId: (index) => allBinaries[index].name,
            headerBuilder: (context) => [
              const SailTableHeaderCell(name: 'Name'),
              const SailTableHeaderCell(name: 'Type'),
              const SailTableHeaderCell(name: 'Port'),
              const SailTableHeaderCell(name: 'Status'),
            ],
            rowBuilder: (context, row, selected) {
              final binary = allBinaries[row];
              // bitwindowd spawns drivechaind, so only the orchestrator poll knows its state.
              final DaemonState? daemon = binary is Drivechaind ? _drivechaind : null;
              final connected = daemon?.connected ?? binaryProvider.isConnected(binary);
              final initializing = daemon?.initializingBinary ?? binaryProvider.isInitializing(binary);

              final status = connected
                  ? 'Connected'
                  : initializing
                  ? 'Initializing'
                  : 'Disconnected';

              return [
                SailTableCell(value: binary.name),
                SailTableCell(value: binary.type.name),
                SailTableCell(value: (binary is BitcoinCore ? confProvider.rpcPort : binary.port).toString()),
                SailTableCell(
                  value: status,
                  child: StatusDotLabel(
                    label: status,
                    tone: connected
                        ? SailStatusTone.success
                        : initializing
                        ? SailStatusTone.warning
                        : SailStatusTone.error,
                  ),
                ),
              ];
            },
            rowCount: allBinaries.length,
            emptyPlaceholder: 'No processes running',
          ),
        );
      },
    );
  }
}

class BinariesTab extends StatelessWidget {
  const BinariesTab({super.key});

  @override
  Widget build(BuildContext context) {
    final binaryProvider = GetIt.I.get<BinaryProvider>();

    return ListenableBuilder(
      listenable: binaryProvider,
      builder: (context, _) {
        final allBinaries = binaryProvider.binaries;

        return SailCard(
          title: 'Binary Hashes',
          subtitle: 'SHA256 hashes of downloaded binaries for verification',
          child: SailTable(
            getRowId: (index) => index.toString(),
            headerBuilder: (context) => [
              const SailTableHeaderCell(name: 'Name'),
              const SailTableHeaderCell(name: 'Version'),
              const SailTableHeaderCell(name: 'Status'),
              const SailTableHeaderCell(name: 'SHA256 Hash'),
              const SailTableHeaderCell(name: 'Verified'),
            ],
            rowBuilder: (context, row, selected) {
              final binary = allBinaries[row];
              final downloadInfo = binary.downloadInfo;
              final hash = downloadInfo.hash;
              final hashMatch = downloadInfo.hashMatch;
              final status = binary.isDownloaded ? 'Downloaded' : 'Not downloaded';

              final verifiedText = switch (hashMatch) {
                true => 'OK',
                false => 'MISMATCH',
                null => '-',
              };

              return [
                SailTableCell(value: binary.name),
                SailTableCell(value: binary.version),
                SailTableCell(value: status),
                SailTableCell(value: hash ?? '-'),
                SailTableCell(
                  value: verifiedText,
                  child: _HashVerificationIcon(hashMatch: hashMatch),
                ),
              ];
            },
            rowCount: allBinaries.length,
            emptyPlaceholder: 'No binaries configured',
            onDoubleTap: (index) => _copyHash(context, allBinaries[int.parse(index)]),
            contextMenuItems: (index) {
              final binary = allBinaries[int.parse(index)];
              return [
                if (binary.downloadInfo.hash != null)
                  SailMenuItem(
                    onSelected: () => _copyHash(context, binary),
                    child: SailText.primary12('Copy hash'),
                  ),
              ];
            },
          ),
        );
      },
    );
  }

  void _copyHash(BuildContext context, Binary binary) {
    final hash = binary.downloadInfo.hash;
    if (hash == null) {
      return;
    }
    Clipboard.setData(ClipboardData(text: hash));
    showSailToast(context, 'SHA256 hash copied to clipboard', duration: const Duration(seconds: 2));
  }
}

class _HashVerificationIcon extends StatelessWidget {
  final bool? hashMatch;

  const _HashVerificationIcon({required this.hashMatch});

  @override
  Widget build(BuildContext context) {
    return switch (hashMatch) {
      true => const StatusDotLabel(label: 'OK', tone: SailStatusTone.success),
      false => const StatusDotLabel(label: 'MISMATCH', tone: SailStatusTone.error),
      null => SailText.secondary13('-'),
    };
  }
}
