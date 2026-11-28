import 'package:flutter/widgets.dart';
import 'package:sail_ui/sail_ui.dart';

/// The dot color of an auction status: Active, Upcoming or Ended.
SailStatusTone auctionStatusTone(String status) => switch (status.toLowerCase()) {
  'active' => SailStatusTone.success,
  'upcoming' => SailStatusTone.info,
  _ => SailStatusTone.neutral,
};

/// The value of a table cell that holds an [AuctionStatusLabel]: the em space sizes the column for the dot.
String auctionStatusCellValue(String status) => '\u2003 $status';

/// A status dot before the status label, for a table cell.
class AuctionStatusLabel extends StatelessWidget {
  final String status;

  const AuctionStatusLabel({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SailStatusDot(tone: auctionStatusTone(status)),
        const SizedBox(width: SailStyleValues.padding08),
        Flexible(child: SailText.primary13(status)),
      ],
    );
  }
}

/// A big value over a grey caption, at the top of a side panel.
class PanelKeyValue extends StatelessWidget {
  final String value;
  final String caption;

  const PanelKeyValue({super.key, required this.value, required this.caption});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SailText.primary24(value, bold: true),
        const SizedBox(height: 2),
        SailText.secondary13(caption),
      ],
    );
  }
}
