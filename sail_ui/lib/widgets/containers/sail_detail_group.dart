import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:sail_ui/sail_ui.dart';

/// The fill of a [SailDetailGroup].
enum SailDetailFill {
  /// The form field grey.
  sunken,

  /// The page background.
  canvas,
}

/// The grey box that groups the detail lines of a side panel, under an optional bold [title].
class SailDetailGroup extends StatelessWidget {
  final String? title;
  final List<Widget> children;
  final SailDetailFill fill;

  /// The space around the lines. Null uses the default of [fill].
  final EdgeInsetsGeometry? padding;

  /// The space between two lines. Null uses the default of [fill].
  final double? spacing;

  const SailDetailGroup({
    super.key,
    this.title,
    required this.children,
    this.fill = SailDetailFill.sunken,
    this.padding,
    this.spacing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    final canvas = fill == SailDetailFill.canvas;
    final gap = spacing ?? (canvas ? 10 : SailStyleValues.padding08);
    final box = DecoratedBox(
      decoration: BoxDecoration(
        color: canvas ? theme.colors.background : theme.colors.formField,
        borderRadius: theme.chrome.radius,
      ),
      child: Padding(
        padding:
            padding ??
            (canvas
                ? const EdgeInsets.symmetric(horizontal: SailStyleValues.padding12, vertical: 10)
                : const EdgeInsets.all(SailStyleValues.padding12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (index, child) in children.indexed) ...[
              if (index > 0) SizedBox(height: gap),
              child,
            ],
          ],
        ),
      ),
    );
    if (title == null) {
      return box;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SailDetailHeading(title!),
        const SizedBox(height: SailStyleValues.padding08),
        box,
      ],
    );
  }
}

/// The bold title over a [SailDetailGroup], with an optional grey [note] after it.
class SailDetailHeading extends StatelessWidget {
  final String text;
  final String? note;

  const SailDetailHeading(this.text, {super.key, this.note});

  @override
  Widget build(BuildContext context) {
    final title = SailText.primary13(text, bold: true);
    final note = this.note;
    if (note == null || note.isEmpty) {
      return title;
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        title,
        const SizedBox(width: SailStyleValues.padding08),
        Flexible(child: SailText.secondary12(note)),
      ],
    );
  }
}

/// A grey label at the left and its value at the right, in a [SailDetailGroup].
class SailDetailLine extends StatelessWidget {
  final String label;
  final String? value;

  /// Takes the place of the value text.
  final Widget? child;
  final Color? valueColor;
  final bool monospace;

  /// True wraps a long value onto more lines. False cuts it to one line.
  final bool wrap;

  /// Shows an info icon with this text after the label.
  final String? info;

  /// A control after the value, such as a copy icon.
  final Widget? trailing;

  /// Runs on a tap on the line.
  final Future<void> Function()? onTap;

  /// True copies the value on a tap on the line.
  final bool copyable;
  final LoadingDetails? loading;

  /// The space between the label and the value.
  final double gap;

  const SailDetailLine({
    super.key,
    required this.label,
    required String this.value,
    this.valueColor,
    this.monospace = false,
    this.wrap = false,
    this.info,
    this.trailing,
    this.onTap,
    this.copyable = false,
    this.loading,
    this.gap = SailStyleValues.padding12,
  }) : child = null;

  const SailDetailLine.child({
    super.key,
    required this.label,
    required Widget this.child,
    this.info,
    this.trailing,
    this.gap = SailStyleValues.padding12,
  }) : value = null,
       valueColor = null,
       monospace = false,
       wrap = false,
       onTap = null,
       copyable = false,
       loading = null;

  @override
  Widget build(BuildContext context) {
    final value = this.value;
    final loading = this.loading;
    final Widget valueBox;
    if (value == null) {
      valueBox = Align(alignment: Alignment.centerRight, child: child);
    } else {
      final text = SailText.primary13(
        value,
        textAlign: TextAlign.end,
        color: valueColor,
        monospace: monospace,
        overflow: wrap ? TextOverflow.visible : TextOverflow.ellipsis,
        maxLines: wrap ? null : 1,
      );
      valueBox = loading == null
          ? text
          : Align(
              alignment: Alignment.centerRight,
              child: SailSkeletonizer(enabled: loading.enabled, description: loading.description, child: text),
            );
    }
    final row = Row(
      crossAxisAlignment: wrap ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        SailText.secondary13(label),
        if (info != null) ...[
          const SizedBox(width: SailStyleValues.padding04),
          SailInfoIcon(title: label, message: info!),
        ],
        SizedBox(width: gap),
        Expanded(child: valueBox),
        if (trailing != null) ...[const SizedBox(width: SailStyleValues.padding08), trailing!],
      ],
    );
    if (copyable && value != null) {
      return SailTappable(
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: value));
          if (!context.mounted) {
            return;
          }
          showSnackBar(context, 'Copied $value');
        },
        child: row,
      );
    }
    if (onTap != null) {
      return SailTappable(onTap: onTap, child: row);
    }
    return row;
  }
}

/// A grey label over a value that wraps, for long values such as a hash.
class SailStackedDetail extends StatelessWidget {
  final String label;
  final String value;
  final bool monospace;

  /// True lets the reader select the value text.
  final bool selectable;

  /// True draws the label at 13 px in place of 12 px.
  final bool largeLabel;

  /// Non-null shows a copy button for this text beside the value.
  final String? copyValue;

  /// Non-null shows a small copy icon at the right of the label and the value.
  final VoidCallback? onCopy;

  const SailStackedDetail({
    super.key,
    required this.label,
    required this.value,
    this.monospace = true,
    this.selectable = false,
    this.largeLabel = false,
    this.copyValue,
    this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final valueText = selectable
        ? SailSelectableText(value, monospace: monospace)
        : SailText.primary13(value, monospace: monospace, overflow: null);
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (largeLabel) SailText.secondary13(label) else SailText.secondary12(label),
        const SizedBox(height: 2),
        if (copyValue == null)
          valueText
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: valueText),
              CopyButton(text: copyValue!),
            ],
          ),
      ],
    );
    if (onCopy == null) {
      return column;
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: column),
        const SizedBox(width: SailStyleValues.padding08),
        SailDetailCopyIcon(onCopy: onCopy!),
      ],
    );
  }
}

/// A small copy icon for a detail line.
class SailDetailCopyIcon extends StatelessWidget {
  final VoidCallback onCopy;

  const SailDetailCopyIcon({super.key, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    return SailTappable(
      onTap: () async => onCopy(),
      borderRadius: theme.chrome.radius,
      child: Padding(
        padding: const EdgeInsets.all(SailStyleValues.padding04),
        child: SailSVG.fromAsset(SailSVGAsset.iconCopy, width: 14, height: 14, color: theme.colors.text),
      ),
    );
  }
}

/// The page body with an optional side panel at the right. Below [narrowWidth] the panel takes the place of the body.
class SailPageWithPanel extends StatefulWidget {
  final Widget child;
  final Widget? panel;

  /// Null keeps the body and the panel side by side at every width.
  final double? narrowWidth;

  const SailPageWithPanel({super.key, required this.child, this.panel, this.narrowWidth});

  @override
  State<SailPageWithPanel> createState() => _SailPageWithPanelState();
}

class _SailPageWithPanelState extends State<SailPageWithPanel> {
  // Moves the body between layouts without a rebuild, so a table keeps its search, sort and filters.
  final GlobalKey _bodyKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final body = KeyedSubtree(key: _bodyKey, child: widget.child);
    final panel = widget.panel;
    if (panel == null) {
      return body;
    }
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: body),
        const SizedBox(width: SailStyleValues.padding12),
        panel,
      ],
    );
    final narrowWidth = widget.narrowWidth;
    if (narrowWidth == null) {
      return row;
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < narrowWidth) {
          return Stack(
            children: [
              Offstage(child: body),
              SizedBox(width: constraints.maxWidth, child: panel),
            ],
          );
        }
        return row;
      },
    );
  }
}
