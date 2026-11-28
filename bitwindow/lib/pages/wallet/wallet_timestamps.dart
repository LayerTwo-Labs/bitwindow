import 'package:bitwindow/pages/wallet/create_timestamp_page.dart';
import 'package:bitwindow/pages/wallet/timestamp_detail_page.dart';
import 'package:bitwindow/pages/wallet/verify_timestamp_page.dart';
import 'package:bitwindow/providers/timestamp_provider.dart';
import 'package:bitwindow/routing/router.dart';
import 'package:bitwindow/widgets/v2_details.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';

class TimestampsTabViewModel extends BaseViewModel {
  final TimestampProvider _timestampProvider = GetIt.I.get<TimestampProvider>();

  List<FileTimestamp> get timestamps => _timestampProvider.timestamps;
  bool get isLoading => _timestampProvider.isLoading;
  @override
  String? get modelError => _timestampProvider.modelError;

  /// The timestamp in the side panel.
  int? selectedTimestampId;

  TimestampsTabViewModel() {
    _timestampProvider.addListener(_onTimestampProviderChanged);
  }

  void _onTimestampProviderChanged() {
    notifyListeners();
  }

  Future<void> refresh() async {
    await _timestampProvider.fetch();
  }

  void selectTimestamp(int? id) {
    selectedTimestampId = id;
    notifyListeners();
  }

  Future<void> timestampFile(BuildContext context) async {
    if (SailStyleValues.phoneLayout(context)) {
      await GetIt.I.get<AppRouter>().push(const CreateTimestampRoute());
      return;
    }
    final created = await showCreateTimestampDialog(context);
    if (created != null) {
      selectTimestamp(created.id.toInt());
    }
  }

  Future<void> verifyFile(BuildContext context) async {
    if (SailStyleValues.phoneLayout(context)) {
      await GetIt.I.get<AppRouter>().push(const VerifyTimestampRoute());
      return;
    }
    await showVerifyTimestampDialog(context);
  }

  @override
  void dispose() {
    _timestampProvider.removeListener(_onTimestampProviderChanged);
    super.dispose();
  }
}

class TimestampsTab extends StatelessWidget {
  const TimestampsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<TimestampsTabViewModel>.reactive(
      viewModelBuilder: () => TimestampsTabViewModel(),
      onViewModelReady: (model) => model.refresh(),
      builder: (context, model, child) {
        final phone = SailStyleValues.phoneLayout(context);
        final selectedId = phone ? null : model.selectedTimestampId;
        final card = SailCard(
          title: 'File Timestamps',
          error: model.modelError,
          bottomPadding: false,
          widgetHeaderEnd: model.timestamps.isNotEmpty
              ? SailRow(
                  spacing: SailStyleValues.padding08,
                  children: [
                    SailButton(
                      label: 'Verify File',
                      variant: ButtonVariant.secondary,
                      onPressed: () async => model.verifyFile(context),
                    ),
                    SailButton(
                      label: 'Timestamp New File',
                      onPressed: () async => model.timestampFile(context),
                    ),
                  ],
                )
              : null,
          child: model.timestamps.isEmpty
              ? Center(
                  child: SailColumn(
                    spacing: SailStyleValues.padding16,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SailText.primary15('No timestamps yet'),
                      SailRow(
                        spacing: SailStyleValues.padding08,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SailButton(
                            label: 'Verify a File',
                            variant: ButtonVariant.secondary,
                            onPressed: () async => model.verifyFile(context),
                          ),
                          SailButton(
                            label: 'Timestamp Your First File',
                            onPressed: () async => model.timestampFile(context),
                          ),
                        ],
                      ),
                    ],
                  ),
                )
              : TimestampsTable(
                  timestamps: model.timestamps,
                  selectedTimestampId: selectedId,
                  onSelectTimestamp: phone ? null : model.selectTimestamp,
                ),
        );
        return SailPageWithPanel(
          panel: selectedId == null
              ? null
              : TimestampDetailPanel(timestampId: selectedId, onClose: () async => model.selectTimestamp(null)),
          child: card,
        );
      },
    );
  }
}

class TimestampsTable extends StatelessWidget {
  final List<FileTimestamp> timestamps;

  /// The timestamp in the side panel.
  final int? selectedTimestampId;

  /// Opens a timestamp in the side panel, or closes it with null. Null pushes the details page.
  final ValueChanged<int?>? onSelectTimestamp;

  const TimestampsTable({super.key, required this.timestamps, this.selectedTimestampId, this.onSelectTimestamp});

  @override
  Widget build(BuildContext context) {
    return SailTable(
      getRowId: (index) => timestamps[index].id.toString(),
      selectedRowId: selectedTimestampId?.toString(),
      onSelectedRow: (rowId) => onSelectTimestamp?.call(rowId == null ? null : int.parse(rowId)),
      headerBuilder: (context) => [
        SailTableHeaderCell(name: 'Filename'),
        SailTableHeaderCell(name: 'Hash'),
        SailTableHeaderCell(name: 'Timestamped'),
        SailTableHeaderCell(name: 'Status'),
        SailTableHeaderCell(name: 'Block Height', alignment: Alignment.centerRight),
      ],
      rowBuilder: (context, row, selected) {
        final timestamp = timestamps[row];
        final status = _getStatusLabel(timestamp.status, timestamp.confirmations);
        return [
          SailTableCell(value: timestamp.filename),
          SailTableCell(value: _truncateHash(timestamp.fileHash), copyValue: timestamp.fileHash),
          SailTableCell(value: formatConfirmedAt(timestamp, 'MMM d, yyyy HH:mm')),
          SailTableCell(
            value: status,
            child: StatusDotLabel(label: status, tone: timestampStatusTone(timestamp.status)),
          ),
          SailTableCell(
            value: timestamp.hasBlockHeight() ? timestamp.blockHeight.toString() : '-',
            alignment: Alignment.centerRight,
          ),
        ];
      },
      rowCount: timestamps.length,
      onDoubleTap: (rowId) => _viewTimestamp(timestamps.firstWhere((t) => t.id.toString() == rowId)),
      contextMenuItems: (rowId) {
        final timestamp = timestamps.firstWhere((t) => t.id.toString() == rowId);
        return [
          SailMenuItem(onSelected: () => _viewTimestamp(timestamp), child: SailText.primary12('View Details')),
          SailMenuItem(
            onSelected: () async {
              await Clipboard.setData(ClipboardData(text: timestamp.fileHash));
              if (context.mounted) {
                showSailToast(context, 'Hash copied to clipboard');
              }
            },
            child: SailText.primary12('Copy hash'),
          ),
        ];
      },
    );
  }

  String _truncateHash(String hash) {
    if (hash.length <= 20) {
      return hash;
    }
    return '${hash.substring(0, 10)}...${hash.substring(hash.length - 10)}';
  }

  String _getStatusLabel(String status, int confirmations) {
    switch (status) {
      case 'pending':
        return 'Pending';
      case 'confirming':
        return confirmations > 0 ? 'Confirming ($confirmations)' : 'Confirming (0)';
      case 'confirmed':
        return confirmations > 0 ? 'Confirmed ($confirmations)' : 'Confirmed';
      case 'failed':
        return 'Failed';
      default:
        return status;
    }
  }

  void _viewTimestamp(FileTimestamp timestamp) {
    final select = onSelectTimestamp;
    if (select != null) {
      select(timestamp.id.toInt());
      return;
    }
    GetIt.I.get<AppRouter>().push(TimestampDetailRoute(timestampId: timestamp.id.toInt()));
  }
}
