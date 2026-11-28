import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import 'package:sail_ui/sail_ui.dart';

/// The space between the cards of a v2 wallet tab.
const double walletGap = 12;

/// [sats] in the display unit, with no unit.
String walletAmountText(int sats) {
  final formatter = GetIt.I<FormatterProvider>();
  return formatter.formatSats(sats).replaceAll(' ${formatter.currentUnit.symbol}', '');
}

/// The unit line under an amount in a table row.
String walletUnitText() => GetIt.I<FormatterProvider>().currentUnit.symbol;

/// "1 204 confirmations", in the singular for one.
String confirmationsText(int confirmations) =>
    '${formatWithThousandSpacers(confirmations)} confirmation${confirmations == 1 ? '' : 's'}';

/// The date line of a table row: day and month, and the year when it is not this year.
String walletRowDate(DateTime time) =>
    DateFormat(time.year == DateTime.now().year ? 'd MMM' : 'd MMM yyyy').format(time);

/// The time line of a table row.
String walletRowTime(DateTime time) => DateFormat('HH:mm').format(time);

/// The full date of a detail row.
String walletDetailDate(DateTime time) => DateFormat('d MMM yyyy, HH:mm').format(time);

/// The start and the end of a long id, such as "7c1e…9f03".
String walletShortId(String id, {int keep = 4}) =>
    id.length <= keep * 2 + 1 ? id : '${id.substring(0, keep)}…${id.substring(id.length - keep)}';

/// [base] in the theme text font. The SailText sizes above 13 px leave the family to the app default.
TextStyle walletTextStyle(
  BuildContext context,
  TextStyle base, {
  Color? color,
  bool bold = false,
}) {
  final theme = SailTheme.of(context);
  return base.copyWith(
    color: color ?? theme.colors.text,
    fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
    fontFamily: theme.chrome.textFamily(),
  );
}

/// A small grey label over a large amount and its sats line. The ⇅ after the sats line swaps the two lines in
/// this block only; the unit setting of the app stays.
class WalletAmountBlock extends StatefulWidget {
  final String? label;
  final String amount;
  final String? sats;
  final Color? color;

  const WalletAmountBlock({
    super.key,
    this.label,
    required this.amount,
    this.sats,
    this.color,
  });

  @override
  State<WalletAmountBlock> createState() => _WalletAmountBlockState();
}

class _WalletAmountBlockState extends State<WalletAmountBlock> {
  bool _swapped = false;

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    final sats = widget.sats;
    final big = sats != null && _swapped ? sats : widget.amount;
    final small = sats == null ? null : (_swapped ? widget.amount : sats);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null)
          SailText.primary12(
            widget.label!,
            bold: true,
            color: theme.colors.textSecondary,
          ),
        Text(
          big,
          style: walletTextStyle(
            context,
            SailStyleValues.twentyFour,
            color: widget.color,
            bold: true,
          ),
        ),
        if (small != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  small,
                  style: walletTextStyle(
                    context,
                    SailStyleValues.fourteen,
                    color: theme.colors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              SailTappable(
                key: const Key('wallet_swap_unit'),
                onTap: () async => setState(() => _swapped = !_swapped),
                borderRadius: theme.chrome.radius,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: SailSVG.fromAsset(
                    SailSVGAsset.arrowDownUp,
                    width: 14,
                    height: 14,
                    color: theme.colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// A status dot over the first line of a table cell, with an optional second line.
class WalletStatusCell extends StatelessWidget {
  final SailStatusTone tone;
  final String status;
  final String? detail;
  final Color? color;

  /// Icons between the dot and the status, such as a warning.
  final List<Widget> marks;

  const WalletStatusCell({
    super.key,
    required this.tone,
    required this.status,
    this.detail,
    this.color,
    this.marks = const [],
  });

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SailStatusDot(tone: tone),
            const SizedBox(width: 6),
            for (final mark in marks) ...[mark, const SizedBox(width: 4)],
            Flexible(
              child: SailText.primary13(
                status,
                color: color,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        if (detail != null && detail!.isNotEmpty) ...[
          const SizedBox(height: 1),
          Padding(
            padding: const EdgeInsets.only(left: 13),
            child: SailText.primary12(
              detail!,
              color: theme.colors.textSecondary,
              maxLines: 1,
            ),
          ),
        ],
      ],
    );
  }
}

/// The search field of a table toolbar.
class WalletSearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final double width;

  const WalletSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    this.width = 260,
  });

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    return SizedBox(
      width: width,
      child: SailTextField(
        controller: controller,
        hintText: hintText,
        size: TextFieldSize.small,
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 10, right: 6),
          child: SailSVG.icon(
            SailSVGAsset.search,
            width: 14,
            color: theme.colors.textSecondary,
          ),
        ),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 30,
          maxHeight: 14,
        ),
      ),
    );
  }
}

/// The date range filter of a table toolbar: "All time", or the range. A tap on a range clears it.
class WalletDateRangeButton extends StatelessWidget {
  final ({DateTime start, DateTime end})? range;
  final void Function(({DateTime start, DateTime end})? range) onChanged;

  const WalletDateRangeButton({
    super.key,
    required this.range,
    required this.onChanged,
  });

  static String label(({DateTime start, DateTime end})? range) {
    if (range == null) {
      return 'All time';
    }
    final sameYear = range.start.year == range.end.year;
    return '${DateFormat(sameYear ? 'd MMM' : 'd MMM yyyy').format(range.start)} – '
        '${DateFormat('d MMM yyyy').format(range.end)}';
  }

  @override
  Widget build(BuildContext context) {
    return SailTooltip(
      message: 'Filter by date range',
      child: SailButton(
        label: label(range),
        variant: ButtonVariant.secondary,
        small: true,
        trailingIcon: range == null ? SailSVGAsset.chevronDown : SailSVGAsset.x,
        onPressed: () async {
          if (range != null) {
            onChanged(null);
            return;
          }
          final picked = await showSailDateRangePicker(
            context: context,
            firstDate: DateTime(2009, 1, 3),
            lastDate: DateTime.now().add(const Duration(days: 365)),
          );
          if (picked != null) {
            onChanged(picked);
          }
        },
      ),
    );
  }
}

/// Below this width the toolbar of a table card goes under its title.
const double _toolbarBesideTitle = 640;

/// A v2 table card: title, toolbar, error line and a table that fills the height.
class WalletTableCard extends StatelessWidget {
  final String title;
  final List<Widget> toolbar;
  final String? error;
  final Widget child;

  const WalletTableCard({
    super.key,
    required this.title,
    this.toolbar = const [],
    this.error,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    return DecoratedBox(
      decoration: theme.chrome.panel(theme.colors),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final heading = SailText.primary16(title, bold: true);
                  if (constraints.maxWidth >= _toolbarBesideTitle) {
                    return Row(
                      children: [
                        Expanded(child: heading),
                        for (final item in toolbar) ...[
                          const SizedBox(width: 8),
                          item,
                        ],
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      heading,
                      if (toolbar.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              for (final (i, item) in toolbar.indexed) ...[
                                if (i > 0) const SizedBox(width: 8),
                                item,
                              ],
                            ],
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8, right: 8),
                child: SailText.primary13(
                  error!,
                  color: theme.colors.error,
                  overflow: TextOverflow.visible,
                ),
              ),
            const SizedBox(height: 8),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

/// Below this width a wallet tab stacks its parts, and a side panel takes the place of its table.
const double walletNarrowWidth = 900;

/// Gives a strip at least [minWidth], and scrolls it sideways in a narrower window.
class WalletStripScroll extends StatelessWidget {
  final double minWidth;
  final Widget child;

  const WalletStripScroll({
    super.key,
    this.minWidth = walletNarrowWidth,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= minWidth) {
          return child;
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(width: minWidth, child: child),
        );
      },
    );
  }
}
