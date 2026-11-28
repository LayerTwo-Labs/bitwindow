import 'package:auto_route/auto_route.dart';
import 'package:bitwindow/models/bandwidth_data.dart';
import 'package:bitwindow/providers/network_provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';

@RoutePage()
class NetworkStatisticsPage extends StatefulWidget {
  const NetworkStatisticsPage({super.key});

  @override
  State<NetworkStatisticsPage> createState() => _NetworkStatisticsPageState();
}

class _NetworkStatisticsPageState extends State<NetworkStatisticsPage> {
  final NetworkProvider _networkProvider = GetIt.I.get<NetworkProvider>();

  GetNetworkStatsResponse? get stats => _networkProvider.stats;
  List<BandwidthDataPoint> get bandwidthHistory => _networkProvider.bandwidthHistory;
  String? get error => _networkProvider.error;
  bool get isLoading => stats == null && error == null;

  @override
  void initState() {
    super.initState();
    _networkProvider.addListener(_onProviderChanged);
  }

  @override
  void dispose() {
    _networkProvider.removeListener(_onProviderChanged);
    super.dispose();
  }

  void _onProviderChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.sailTheme;
    final phone = SailStyleValues.phoneLayout(context);
    final gap = phone ? SailStyleValues.padding12 : 32.0;

    return SailDialog(
      title: 'Network Statistics',
      withCloseButton: true,
      subtitle: 'Real-time Bitcoin network metrics with bandwidth graph',
      maxWidth: phone ? 900 : 760,
      maxHeight: 700,
      child: isLoading && stats == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: LoadingIndicator(),
              ),
            )
          : error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SailSVG.fromAsset(SailSVGAsset.circleAlert, width: 48, color: theme.colors.error),
                    const SizedBox(height: 16),
                    SailText.primary15('Error loading network statistics'),
                    const SizedBox(height: 8),
                    SailText.secondary13(error!),
                    const SizedBox(height: 24),
                    SailButton(
                      label: 'Retry',
                      onPressed: () async {
                        await _networkProvider.fetch();
                      },
                    ),
                  ],
                ),
              ),
            )
          : stats != null && !phone
          ? Builder(
              builder: (_) {
                final stats = this.stats!;
                Widget group(String title, List<(String, String)> rows) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SailDetailHeading(title),
                    const SizedBox(height: SailStyleValues.padding08),
                    SailDetailGroup(
                      fill: SailDetailFill.canvas,
                      children: [
                        for (final (label, value) in rows) SailDetailLine(wrap: true, label: label, value: value),
                      ],
                    ),
                  ],
                );
                const gap = SizedBox(height: SailStyleValues.padding12);

                return SingleChildScrollView(
                  padding: const EdgeInsets.only(top: SailStyleValues.padding04),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                group('Blockchain', [
                                  ('Block Height', stats.blockHeight.toString()),
                                  ('Average Block Time', '${stats.avgBlockTime.toStringAsFixed(1)}s'),
                                  ('Difficulty', stats.difficulty > 0 ? stats.difficulty.toString() : 'N/A'),
                                  (
                                    'Network Hashrate',
                                    stats.networkHashrate > 0 ? _formatHashrate(stats.networkHashrate) : 'N/A',
                                  ),
                                ]),
                                gap,
                                group('Network', [
                                  ('Total Peers', stats.peerCount.toString()),
                                  ('Inbound Connections', stats.connectionsIn.toString()),
                                  ('Outbound Connections', stats.connectionsOut.toString()),
                                  (
                                    'Network Version',
                                    stats.networkVersion > 0 ? stats.networkVersion.toString() : 'N/A',
                                  ),
                                  if (stats.subversion.isNotEmpty) ('Subversion', stats.subversion),
                                ]),
                              ],
                            ),
                          ),
                          const SizedBox(width: SailStyleValues.padding12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                group('Data Transfer', [
                                  (
                                    'Total Received',
                                    stats.totalBytesReceived > 0
                                        ? _formatBytes(stats.totalBytesReceived.toInt())
                                        : 'N/A',
                                  ),
                                  (
                                    'Total Sent',
                                    stats.totalBytesSent > 0 ? _formatBytes(stats.totalBytesSent.toInt()) : 'N/A',
                                  ),
                                ]),
                                if (stats.hasBitcoindBandwidth() || stats.hasEnforcerBandwidth()) ...[
                                  gap,
                                  group('Processes', [
                                    if (stats.hasBitcoindBandwidth()) ...[
                                      ('bitcoind PID', stats.bitcoindBandwidth.pid.toString()),
                                      ('bitcoind Connections', stats.bitcoindBandwidth.connectionCount.toString()),
                                    ],
                                    if (stats.hasEnforcerBandwidth()) ...[
                                      ('enforcer PID', stats.enforcerBandwidth.pid.toString()),
                                      ('enforcer Connections', stats.enforcerBandwidth.connectionCount.toString()),
                                    ],
                                  ]),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                      gap,
                      if (bandwidthHistory.length > 1)
                        _BandwidthGraph(bandwidthHistory: bandwidthHistory, formatBandwidth: _formatBandwidth)
                      else
                        Align(
                          alignment: Alignment.centerRight,
                          child: SailText.secondary12('Auto-refreshing every 5 seconds'),
                        ),
                    ],
                  ),
                );
              },
            )
          : stats != null
          ? SingleChildScrollView(
              child: Padding(
                padding: phone ? const EdgeInsets.only(top: SailStyleValues.padding12) : const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: phone ? CrossAxisAlignment.stretch : CrossAxisAlignment.start,
                  children: [
                    StatSection(
                      title: 'Blockchain',
                      children: [
                        StatRow(label: 'Block Height', value: stats!.blockHeight.toString()),
                        StatRow(label: 'Average Block Time', value: '${stats!.avgBlockTime.toStringAsFixed(1)}s'),
                        StatRow(
                          label: 'Difficulty',
                          value: stats!.difficulty > 0 ? stats!.difficulty.toString() : 'N/A',
                        ),
                        StatRow(
                          label: 'Network Hashrate',
                          value: stats!.networkHashrate > 0 ? _formatHashrate(stats!.networkHashrate) : 'N/A',
                        ),
                      ],
                    ),
                    SizedBox(height: gap),
                    StatSection(
                      title: 'Network',
                      children: [
                        StatRow(label: 'Total Peers', value: stats!.peerCount.toString()),
                        StatRow(label: 'Inbound Connections', value: stats!.connectionsIn.toString()),
                        StatRow(label: 'Outbound Connections', value: stats!.connectionsOut.toString()),
                        StatRow(
                          label: 'Network Version',
                          value: stats!.networkVersion > 0 ? stats!.networkVersion.toString() : 'N/A',
                        ),
                        if (stats!.subversion.isNotEmpty) StatRow(label: 'Subversion', value: stats!.subversion),
                      ],
                    ),
                    SizedBox(height: gap),
                    StatSection(
                      title: 'Data Transfer',
                      children: [
                        StatRow(
                          label: 'Total Received',
                          value: stats!.totalBytesReceived > 0
                              ? _formatBytes(stats!.totalBytesReceived.toInt())
                              : 'N/A',
                        ),
                        StatRow(
                          label: 'Total Sent',
                          value: stats!.totalBytesSent > 0 ? _formatBytes(stats!.totalBytesSent.toInt()) : 'N/A',
                        ),
                      ],
                    ),
                    if (bandwidthHistory.length > 1) ...[
                      SizedBox(height: gap),
                      _BandwidthGraph(
                        bandwidthHistory: bandwidthHistory,
                        formatBandwidth: _formatBandwidth,
                      ),
                    ],
                    if (stats!.hasBitcoindBandwidth() || stats!.hasEnforcerBandwidth()) ...[
                      SizedBox(height: gap),
                      StatSection(
                        title: 'Processes',
                        children: [
                          if (stats!.hasBitcoindBandwidth()) ...[
                            StatRow(label: 'bitcoind PID', value: stats!.bitcoindBandwidth.pid.toString()),
                            StatRow(
                              label: 'bitcoind Connections',
                              value: stats!.bitcoindBandwidth.connectionCount.toString(),
                            ),
                          ],
                          if (stats!.hasEnforcerBandwidth()) ...[
                            const SizedBox(height: 16),
                            StatRow(label: 'enforcer PID', value: stats!.enforcerBandwidth.pid.toString()),
                            StatRow(
                              label: 'enforcer Connections',
                              value: stats!.enforcerBandwidth.connectionCount.toString(),
                            ),
                          ],
                        ],
                      ),
                    ],
                    SizedBox(height: phone ? SailStyleValues.padding12 : 24),
                    Align(
                      alignment: phone ? Alignment.centerLeft : Alignment.center,
                      child: SailText.secondary12(
                        'Auto-refreshing every 5 seconds',
                      ),
                    ),
                  ],
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _formatBandwidth(double bytesPerSec) {
    if (bytesPerSec < 1024) {
      return '${bytesPerSec.toStringAsFixed(1)} B/s';
    }
    if (bytesPerSec < 1024 * 1024) {
      return '${(bytesPerSec / 1024).toStringAsFixed(1)} KB/s';
    }
    return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  String _formatHashrate(double hashrate) {
    if (hashrate < 1000) {
      return '${hashrate.toStringAsFixed(0)} H/s';
    }
    if (hashrate < 1000000) {
      return '${(hashrate / 1000).toStringAsFixed(2)} KH/s';
    }
    if (hashrate < 1000000000) {
      return '${(hashrate / 1000000).toStringAsFixed(2)} MH/s';
    }
    if (hashrate < 1000000000000) {
      return '${(hashrate / 1000000000).toStringAsFixed(2)} GH/s';
    }
    return '${(hashrate / 1000000000000).toStringAsFixed(2)} TH/s';
  }
}

/// Top of the bandwidth graph Y axis: the peak rate plus 10%, at least 1 KB/s.
double bandwidthGraphMaxY(Iterable<FlSpot> spots) {
  final peak = spots.fold<double>(1024, (max, s) => s.y > max ? s.y : max);
  return peak * 1.1;
}

class _BandwidthGraph extends StatelessWidget {
  final List<BandwidthDataPoint> bandwidthHistory;
  final String Function(double) formatBandwidth;

  const _BandwidthGraph({
    required this.bandwidthHistory,
    required this.formatBandwidth,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.sailTheme;

    // Calculate bandwidth rates from cumulative totals
    final List<FlSpot> rxSpots = [];
    final List<FlSpot> txSpots = [];

    for (int i = 1; i < bandwidthHistory.length; i++) {
      final prev = bandwidthHistory[i - 1];
      final curr = bandwidthHistory[i];
      final timeDiff = curr.time.difference(prev.time).inSeconds;

      if (timeDiff > 0) {
        final rxRate = (curr.totalRxBytes - prev.totalRxBytes) / timeDiff;
        final txRate = (curr.totalTxBytes - prev.totalTxBytes) / timeDiff;

        rxSpots.add(FlSpot(i.toDouble(), rxRate));
        txSpots.add(FlSpot(i.toDouble(), txRate));
      }
    }

    if (rxSpots.isEmpty || txSpots.isEmpty) {
      return const SizedBox.shrink();
    }

    final maxY = bandwidthGraphMaxY([...rxSpots, ...txSpots]);

    LineChartBarData line(List<FlSpot> spots, Color color) => LineChartBarData(
      spots: spots,
      color: color,
      barWidth: 2,
      dotData: const FlDotData(show: false),
    );
    LineChartData chart({required FlBorderData border}) => LineChartData(
      gridData: const FlGridData(show: false),
      titlesData: const FlTitlesData(show: false),
      borderData: border,
      minX: 1,
      maxX: bandwidthHistory.length.toDouble(),
      minY: 0,
      maxY: maxY,
      lineBarsData: [line(rxSpots, theme.colors.orange), line(txSpots, theme.colors.info)],
      lineTouchData: SailStyleValues.phoneLayout(context)
          ? const LineTouchData(enabled: false)
          : LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipItems: (touchedSpots) => touchedSpots
                    .map(
                      (spot) => LineTooltipItem(
                        '${spot.barIndex == 0 ? 'RX' : 'TX'}: ${formatBandwidth(spot.y)}',
                        TextStyle(color: theme.colors.text, fontWeight: FontWeight.bold),
                      ),
                    )
                    .toList(),
              ),
            ),
    );

    if (SailStyleValues.phoneLayout(context)) {
      final axis = BorderSide(color: theme.colors.divider);
      return StatSection(
        title: 'Bandwidth Graph',
        children: [
          SailText.secondary13('Last ${bandwidthHistory.length * 5} seconds'),
          const SizedBox(height: SailStyleValues.padding12),
          SizedBox(
            height: 180,
            child: LineChart(
              chart(
                border: FlBorderData(
                  show: true,
                  border: Border(left: axis, bottom: axis),
                ),
              ),
            ),
          ),
          const SizedBox(height: SailStyleValues.padding12),
          Row(
            children: [
              _LegendDot(color: theme.colors.orange),
              const SizedBox(width: 6),
              SailText.secondary13('Received'),
              const SizedBox(width: SailStyleValues.padding16),
              _LegendDot(color: theme.colors.info),
              const SizedBox(width: 6),
              SailText.secondary13('Sent'),
            ],
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(SailStyleValues.padding16),
      decoration: BoxDecoration(
        borderRadius: theme.chrome.radiusLarge,
        border: Border.all(color: theme.colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: SailText.primary13('Bandwidth Graph', bold: true)),
              SailText.secondary12('Last ${bandwidthHistory.length * 5} seconds'),
            ],
          ),
          const SizedBox(height: SailStyleValues.padding16),
          SizedBox(
            height: 120,
            child: LineChart(
              chart(
                border: FlBorderData(
                  show: true,
                  border: Border(bottom: BorderSide(color: theme.colors.divider)),
                ),
              ),
            ),
          ),
          const SizedBox(height: SailStyleValues.padding12),
          Row(
            children: [
              _LegendDash(color: theme.colors.orange),
              const SizedBox(width: SailStyleValues.padding12),
              SailText.secondary12('Received'),
              const SizedBox(width: SailStyleValues.padding16),
              _LegendDash(color: theme.colors.info),
              const SizedBox(width: SailStyleValues.padding12),
              SailText.secondary12('Sent'),
              const Spacer(),
              SailText.secondary12('Auto-refreshing every 5 seconds'),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendDash extends StatelessWidget {
  final Color color;

  const _LegendDash({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(key: const ValueKey('bandwidth-legend-dash'), width: 12, height: 2, color: color);
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;

  const _LegendDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('bandwidth-legend-dot'),
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
