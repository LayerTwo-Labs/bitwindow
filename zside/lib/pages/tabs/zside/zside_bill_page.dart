import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:zside/providers/cast_provider.dart';

/// Formats a bill amount in sats, or in BTC with spaced decimals from 1 BTC up.
String billAmountLabel(int sats) {
  if (sats < 100000000) {
    return _groupDigits(sats.toString());
  }
  final fraction = (sats % 100000000).toString().padLeft(8, '0');
  return '${_groupDigits((sats ~/ 100000000).toString())}.${fraction.substring(0, 2)} ${_groupDigits(fraction.substring(2))}';
}

String _groupDigits(String digits) {
  final groups = <String>[];
  for (var end = digits.length; end > 0; end -= 3) {
    groups.insert(0, digits.substring(end < 3 ? 0 : end - 3, end));
  }
  return groups.join(' ');
}

/// Shows the Bill Amounts table in a dialog.
Future<void> showBillAmounts(BuildContext context) async {
  await widgetDialog(
    context: context,
    title: 'Bill Amounts',
    maxWidth: 820,
    child: const BillAmountsTable(),
  );
}

@RoutePage()
class ZSideBillPage extends StatelessWidget {
  const ZSideBillPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SailPage(
      widgetTitle: SailText.primary15('Bill Amounts'),
      scrollable: true,
      body: const Padding(
        padding: EdgeInsets.only(bottom: SailStyleValues.padding32),
        child: BillAmountsTable(),
      ),
    );
  }
}

/// The cast bill amounts in sats: one column per weekday, a hairline under each row.
class BillAmountsTable extends StatelessWidget {
  const BillAmountsTable({super.key});

  static const _days = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    final hairline = BorderSide(color: theme.colors.divider);

    return SailColumn(
      spacing: SailStyleValues.padding08,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SailText.secondary13('Bill Amounts (in sats)'),
        Table(
          border: TableBorder(horizontalInside: hairline, bottom: hairline),
          children: [
            TableRow(
              children: [
                for (final day in _days)
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: SailText.secondary12(day, textAlign: TextAlign.right),
                  ),
              ],
            ),
            for (var row = 0; row < 6; row++)
              TableRow(
                children: [
                  for (var day = 0; day < 7; day++)
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: SailText.primary12(
                        billAmountLabel(1 << (row * 7 + day)),
                        textAlign: TextAlign.right,
                        monospace: true,
                      ),
                    ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class ZSideBillTabViewModel extends BaseViewModel {
  final log = Logger(level: Level.debug);
  CastProvider get _castProvider => GetIt.I.get<CastProvider>();
  ZSideRPC get _rpc => GetIt.I.get<ZSideRPC>();

  List<PendingCastBill> get pendingBills => _castProvider.futureCasts.toList().sublist(1);

  Binary get chain => _rpc.chain;

  bool hideDust = true;

  void setShowAll(bool to) {
    hideDust = to;
    notifyListeners();
  }

  ZSideBillTabViewModel() {
    _castProvider.addListener(notifyListeners);
  }

  @override
  void dispose() {
    super.dispose();
    _castProvider.removeListener(notifyListeners);
  }
}
