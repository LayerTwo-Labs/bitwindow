import 'package:bitwindow/pages/wallet/cash_check_page.dart';
import 'package:bitwindow/pages/wallet/check_detail_page.dart';
import 'package:bitwindow/pages/wallet/create_check_page.dart';
import 'package:bitwindow/providers/check_provider.dart';
import 'package:bitwindow/routing/router.dart';
import 'package:bitwindow/utils/explorer_url.dart';
import 'package:bitwindow/widgets/v2_details.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:sidechain_core/gen/wallet/v1/wallet.pb.dart';

/// Renders a Cheque's created/funded/swept timestamp. Returns '-' for null
/// or zero-valued proto Timestamps so unset DB timestamps don't surface as
/// epoch 1970 in the UI. Exposed at the top level so unit tests can pin the
/// formatting behavior without spinning up the full ChecksTable widget.
String formatChequeDate(Timestamp? timestamp) {
  if (timestamp == null) {
    return '-';
  }
  final dt = timestamp.toDateTime().toLocal();
  if (dt.millisecondsSinceEpoch == 0) {
    return '-';
  }
  return DateFormat('MMM d, yyyy HH:mm').format(dt);
}

class ChecksTabViewModel extends BaseViewModel {
  final CheckProvider _checkProvider = GetIt.I.get<CheckProvider>();

  List<Cheque> get checks => _checkProvider.checks;
  bool get isLoading => _checkProvider.isLoading;
  @override
  String? get modelError => _checkProvider.modelError;

  /// The check in the side panel.
  int? selectedCheckId;

  ChecksTabViewModel() {
    _checkProvider.addListener(_onCheckProviderChanged);
  }

  void _onCheckProviderChanged() {
    notifyListeners();
  }

  Future<void> refresh() async {
    await _checkProvider.fetch();
  }

  void selectCheck(int? id) {
    selectedCheckId = id;
    notifyListeners();
  }

  Future<void> createNewCheck(BuildContext context) async {
    if (SailStyleValues.phoneLayout(context)) {
      await GetIt.I.get<AppRouter>().push(const CreateCheckRoute());
      return;
    }
    final checkId = await showCreateCheckDialog(context);
    if (checkId != null) {
      selectCheck(checkId);
    }
  }

  Future<void> cashCheck(BuildContext context) async {
    if (SailStyleValues.phoneLayout(context)) {
      await GetIt.I.get<AppRouter>().push(const CashCheckRoute());
      return;
    }
    await showCashCheckDialog(context);
  }

  @override
  void dispose() {
    _checkProvider.removeListener(_onCheckProviderChanged);
    super.dispose();
  }
}

class ChecksTab extends StatelessWidget {
  const ChecksTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<ChecksTabViewModel>.reactive(
      viewModelBuilder: () => ChecksTabViewModel(),
      onViewModelReady: (model) => model.refresh(),
      builder: (context, model, child) {
        final phone = SailStyleValues.phoneLayout(context);
        final actions = SailRow(
          spacing: SailStyleValues.padding08,
          children: [
            SailButton(
              label: 'Cash Check',
              variant: ButtonVariant.secondary,
              onPressed: () async => model.cashCheck(context),
            ),
            SailButton(
              label: 'Create New Check',
              onPressed: () async => model.createNewCheck(context),
            ),
          ],
        );
        final selectedId = model.selectedCheckId;
        final card = SailCard(
          title: model.checks.isEmpty ? 'Send ${activeTicker.name} Without an Internet Connection' : 'Your Checks',
          subtitle: model.checks.isEmpty
              ? "Checks let you transfer ${activeTicker.name} to anyone. Create a check with a specific amount, and the recipient can cash it later when they're ready to claim the ${activeTicker.name}."
              : null,
          error: model.modelError,
          bottomPadding: false,
          widgetHeaderEnd: model.checks.isNotEmpty && !phone ? actions : null,
          child: model.checks.isEmpty
              ? ChecksEmptyState(
                  onCreateCheck: () => model.createNewCheck(context),
                  onCashCheck: () => model.cashCheck(context),
                )
              : phone
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    actions,
                    const SailSpacing(SailStyleValues.padding08),
                    Expanded(child: ChecksTable(checks: model.checks)),
                  ],
                )
              : ChecksTable(checks: model.checks, selectedCheckId: selectedId, onSelectCheck: model.selectCheck),
        );
        if (phone) {
          return card;
        }
        return SailPageWithPanel(
          panel: selectedId == null
              ? null
              : CheckDetailPanel(checkId: selectedId, onClose: () async => model.selectCheck(null)),
          child: card,
        );
      },
    );
  }
}

class ChecksEmptyState extends StatelessWidget {
  final VoidCallback onCreateCheck;
  final VoidCallback onCashCheck;

  const ChecksEmptyState({
    super.key,
    required this.onCreateCheck,
    required this.onCashCheck,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(SailStyleValues.padding20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SailText.primary15('How It Works'),
            const SailSpacing(SailStyleValues.padding08),
            SailText.secondary13(
              '1. Create a check for a specific amount\n'
              '2. Share the check data with anyone (QR code, text, print on paper)\n'
              '3. The recipient cashes the check when convenient\n'
              '4. Funds move directly to their wallet',
            ),
            const SailSpacing(SailStyleValues.padding20),
            SailText.primary15('Why Use Checks?'),
            const SailSpacing(SailStyleValues.padding08),
            SailText.secondary13(
              "• Gift ${activeTicker.name} without needing the recipient's address upfront\n"
              "• Pay someone who's currently offline\n"
              '• Pre-fund payments that can be claimed later\n'
              '• Share value via any communication channel',
            ),
            const SailSpacing(SailStyleValues.padding20),
            SailRow(
              spacing: SailStyleValues.padding08,
              children: [
                SailButton(
                  label: 'Cash a Check',
                  variant: ButtonVariant.secondary,
                  onPressed: () async => onCashCheck(),
                ),
                SailButton(
                  label: 'Create Your First Check',
                  onPressed: () async => onCreateCheck(),
                ),
                Expanded(child: Container()),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ChecksTable extends StatelessWidget {
  final List<Cheque> checks;

  /// The check in the side panel. Desktop only.
  final int? selectedCheckId;

  /// Opens a check in the side panel, or closes it with null. Desktop only.
  final ValueChanged<int?>? onSelectCheck;

  const ChecksTable({super.key, required this.checks, this.selectedCheckId, this.onSelectCheck});

  @override
  Widget build(BuildContext context) {
    if (SailStyleValues.phoneLayout(context)) {
      return SailDividedList(
        itemCount: checks.length,
        itemBuilder: (context, index) {
          final check = checks[index];
          return SailListRow(
            title: formatChequeDate(check.createdAt),
            subtitle: check.fundedTxids.isEmpty
                ? 'Awaiting funding'
                : formatCheckSats(
                    check.hasActualAmountSats() ? check.actualAmountSats.toInt() : check.expectedAmountSats.toInt(),
                  ),
            trailing: _CheckActions(
              check: check,
              onView: () => _pushCheck(check),
              onDelete: () => confirmDeleteCheck(context, check),
            ),
          );
        },
      );
    }
    return SailTable(
      getRowId: (index) => checks[index].id.toString(),
      selectedRowId: selectedCheckId?.toString(),
      onSelectedRow: (rowId) => onSelectCheck?.call(rowId == null ? null : int.parse(rowId)),
      headerBuilder: (context) => [
        SailTableHeaderCell(name: 'Created'),
        SailTableHeaderCell(name: 'Address'),
        SailTableHeaderCell(name: 'Expected Amount', alignment: Alignment.centerRight),
        SailTableHeaderCell(name: 'Status'),
        SailTableHeaderCell(name: 'Funded Amount', alignment: Alignment.centerRight),
      ],
      rowBuilder: (context, row, selected) {
        final check = checks[row];
        final swept = check.hasSweptTxid() && check.sweptTxid.isNotEmpty;
        return [
          SailTableCell(value: formatChequeDate(check.createdAt)),
          SailTableCell(value: shortHash(check.address), copyValue: check.address),
          SailTableCell(value: formatCheckSats(check.expectedAmountSats.toInt()), alignment: Alignment.centerRight),
          SailTableCell(
            value: checkStatusLabel(check),
            child: StatusDotLabel(
              label: checkStatusLabel(check) == 'Awaiting funding' ? 'Unfunded' : checkStatusLabel(check),
              tone: checkStatusTone(check),
              textColor: swept ? context.sailTheme.colors.textSecondary : null,
            ),
          ),
          SailTableCell(
            value: check.fundedTxids.isNotEmpty && check.hasActualAmountSats()
                ? formatCheckSats(check.actualAmountSats.toInt())
                : '-',
            alignment: Alignment.centerRight,
          ),
        ];
      },
      rowCount: checks.length,
      onDoubleTap: (rowId) => onSelectCheck?.call(int.parse(rowId)),
      contextMenuItems: (rowId) {
        final check = checks.firstWhere((c) => c.id.toString() == rowId);
        return [
          SailMenuItem(
            onSelected: () => onSelectCheck?.call(check.id.toInt()),
            child: SailText.primary12(check.fundedTxids.isEmpty ? 'Fund Check' : 'View Details'),
          ),
          SailMenuItem(
            onSelected: () =>
                openUrl(Uri.parse(mempoolAddressUrl(check.address, GetIt.I.get<BitcoinConfProvider>().network))),
            child: SailText.primary12('View on mempool.space'),
          ),
          SailMenuItem(
            onSelected: () => confirmDeleteCheck(
              context,
              check,
              onDeleted: () async {
                if (selectedCheckId == check.id.toInt()) {
                  onSelectCheck?.call(null);
                }
              },
            ),
            child: SailText.primary12('Delete', color: context.sailTheme.colors.error),
          ),
        ];
      },
    );
  }

  void _pushCheck(Cheque check) {
    GetIt.I.get<AppRouter>().push(CheckDetailRoute(checkId: check.id.toInt()));
  }
}

class _CheckActions extends StatelessWidget {
  final Cheque check;
  final VoidCallback onView;
  final Future<void> Function() onDelete;

  const _CheckActions({required this.check, required this.onView, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (check.hasSweptTxid() && check.sweptTxid.isNotEmpty)
          SailButton(
            label: 'Swept',
            onPressed: () async => onView(),
            variant: ButtonVariant.secondary,
            insideTable: true,
            disabled: true,
          )
        else
          SailButton(
            label: check.fundedTxids.isNotEmpty ? 'View Details' : 'Fund Check',
            onPressed: () async => onView(),
            variant: check.fundedTxids.isNotEmpty ? ButtonVariant.secondary : ButtonVariant.primary,
            insideTable: true,
          ),
        const SizedBox(width: SailStyleValues.padding08),
        SailButton(
          icon: SailSVGAsset.iconDelete,
          onPressed: () async => onDelete(),
          variant: ButtonVariant.destructive,
          insideTable: true,
        ),
      ],
    );
  }
}
