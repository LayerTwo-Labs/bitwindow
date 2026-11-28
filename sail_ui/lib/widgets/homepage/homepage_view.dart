import 'package:flutter/material.dart';
import 'package:sail_ui/sail_ui.dart';

const _badgeOverhang = 8.0;

/// The homepage widgets. In edit mode the user drags, removes and adds widgets.
class HomepageView extends StatefulWidget {
  final HomepageProvider provider;

  /// True puts the half-width widgets in a 400 px column at the left and the full-width widgets
  /// at the right, under the bars. Phones keep one column.
  final bool sideColumns;

  /// With [sideColumns], true puts the full-width widgets at the left and every half-width widget in a 380 px
  /// column at the right.
  final bool halvesRight;

  static const double sideColumnWidth = 400;
  static const double rightColumnWidth = 380;

  const HomepageView({
    super.key,
    required this.provider,
    this.sideColumns = false,
    this.halvesRight = false,
  });

  @override
  State<HomepageView> createState() => _HomepageViewState();
}

class _HomepageViewState extends State<HomepageView> {
  final _keys = <String, GlobalKey>{};

  GlobalKey _keyFor(String widgetId) => _keys.putIfAbsent(widgetId, GlobalKey.new);

  Future<void> _done() async {
    try {
      await widget.provider.finishEdit();
    } catch (e) {
      if (mounted) {
        showSailToast(
          context,
          'Could not save the homepage: $e',
          variant: SailToastVariant.destructive,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.provider,
      builder: (context, _) {
        final provider = widget.provider;
        final editing = provider.editing;
        final editButton = Center(
          child: SailButton(
            key: const Key('HomepageEdit'),
            label: 'Edit homepage',
            variant: ButtonVariant.outline,
            small: true,
            skipLoading: true,
            disabled: !provider.ready,
            onPressed: () async => provider.startEdit(),
          ),
        );
        return LayoutBuilder(
          builder: (context, constraints) {
            if (!editing && constraints.maxHeight.isFinite && constraints.maxHeight >= _minFilledHeight) {
              final filled = _filledSideColumns(context, editButton);
              if (filled != null) {
                return filled;
              }
            }
            return _scrolledRows(context, editing, editButton);
          },
        );
      },
    );
  }

  Widget _scrolledRows(BuildContext context, bool editing, Widget editButton) {
    final provider = widget.provider;
    final gap = _gap(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ClipRect(
            clipper: _OutsetClipper(editing ? _badgeOverhang : 0),
            child: SingleChildScrollView(
              clipBehavior: Clip.none,
              child: SailColumn(
                spacing: gap,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ..._rows(context, editing),
                  if (!editing) editButton,
                ],
              ),
            ),
          ),
        ),
        if (editing)
          _EditBar(
            saving: provider.saving,
            onAdd: () => showWidgetLibrary(context, provider),
            onDone: _done,
          ),
      ],
    );
  }

  Widget _cell(HomepageWidgetEntry entry, bool editing) => _HomepageCell(
    key: editing ? null : ValueKey('HomepageWidget-${entry.info.id}'),
    entry: entry,
    provider: widget.provider,
    editKey: editing ? _keyFor(entry.info.id) : null,
  );

  /// The side-column layout with the full-width widgets stretched to the page height, so the tables
  /// do not scroll the page. Null when the layout does not apply or the page is too short for it.
  Widget? _filledSideColumns(BuildContext context, Widget editButton) {
    if (!widget.sideColumns || SailStyleValues.phoneLayout(context)) {
      return null;
    }
    final provider = widget.provider;
    final entries = [
      for (final row in homepageRows(provider.widgets, provider.catalog)) ...row,
    ];
    final bars = [
      for (final e in entries)
        if (e.size == WidgetSize.bar) e,
    ];
    final halves = [
      for (final e in entries)
        if (e.size == WidgetSize.half) e,
    ];
    final fulls = [
      for (final e in entries)
        if (e.size == WidgetSize.full) e,
    ];
    if (halves.isEmpty || fulls.isEmpty) {
      return null;
    }
    final gap = _gap(context);
    final right = widget.halvesRight;
    final middle = right ? <HomepageWidgetEntry>[] : halves.skip(_sideColumnHalves).toList();
    final topBars = middle.isEmpty ? bars : <HomepageWidgetEntry>[];
    final left = [
      if (middle.isNotEmpty) ...bars,
      ...right ? halves : halves.take(_sideColumnHalves),
    ];
    Widget scrolled(List<HomepageWidgetEntry> column, {Widget? footer}) => SingleChildScrollView(
      child: SailColumn(
        spacing: gap,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final e in column) _cell(e, false), ?footer],
      ),
    );
    return Column(
      key: const Key('HomepageFilled'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final bar in topBars) ...[
          _cell(bar, false),
          SizedBox(height: gap),
        ],
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!right) ...[
                SizedBox(
                  width: HomepageView.sideColumnWidth,
                  child: scrolled(left, footer: editButton),
                ),
                SizedBox(width: gap),
              ],
              if (middle.isNotEmpty) ...[
                Expanded(child: scrolled(middle)),
                SizedBox(width: gap),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, e) in fulls.indexed) ...[
                      if (i > 0) SizedBox(height: gap),
                      Expanded(child: _cell(e, false)),
                    ],
                  ],
                ),
              ),
              if (right) ...[
                SizedBox(width: gap),
                SizedBox(
                  width: HomepageView.rightColumnWidth,
                  child: scrolled(left, footer: editButton),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _rows(BuildContext context, bool editing) {
    final provider = widget.provider;
    final phone = SailStyleValues.phoneLayout(context);
    final rows = homepageRows(
      provider.widgets,
      provider.catalog,
      oneColumn: phone,
    );
    Widget cell(HomepageWidgetEntry entry) => _cell(entry, editing);
    Widget row(List<HomepageWidgetEntry> cells) => cells.length == 1
        ? cell(cells.single)
        : SailRow(
            spacing: _gap(context),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [for (final entry in cells) Expanded(child: cell(entry))],
          );
    if (!widget.sideColumns || phone) {
      return [for (final cells in rows) row(cells)];
    }
    final entries = [for (final row in rows) ...row];
    final bars = [
      for (final e in entries)
        if (e.size == WidgetSize.bar) e,
    ];
    final halves = [
      for (final e in entries)
        if (e.size == WidgetSize.half) e,
    ];
    final fulls = [
      for (final e in entries)
        if (e.size == WidgetSize.full) e,
    ];
    if (halves.isEmpty || fulls.isEmpty) {
      return [for (final cells in rows) row(cells)];
    }
    final gap = _gap(context);
    Widget column(List<HomepageWidgetEntry> entries) => SailColumn(
      spacing: gap,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (final e in entries) cell(e)],
    );
    if (widget.halvesRight) {
      return [
        for (final bar in bars) cell(bar),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: column(fulls)),
            SizedBox(width: gap),
            SizedBox(width: HomepageView.rightColumnWidth, child: column(halves)),
          ],
        ),
      ];
    }
    // A fourth half-width widget gets a middle column, and the bars move into the left column to make room.
    final middle = halves.skip(_sideColumnHalves).toList();
    if (middle.isEmpty) {
      return [
        for (final bar in bars) cell(bar),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: HomepageView.sideColumnWidth,
              child: column(halves),
            ),
            SizedBox(width: gap),
            Expanded(child: column(fulls)),
          ],
        ),
      ];
    }
    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: HomepageView.sideColumnWidth,
            child: column([...bars, ...halves.take(_sideColumnHalves)]),
          ),
          SizedBox(width: gap),
          Expanded(child: column(middle)),
          SizedBox(width: gap),
          Expanded(child: column(fulls)),
        ],
      ),
    ];
  }
}

/// One homepage widget; in edit mode it carries the drag and remove controls.
class _HomepageCell extends StatelessWidget {
  final HomepageWidgetEntry entry;
  final HomepageProvider provider;

  /// Non-null puts the widget in edit mode, under this key.
  final GlobalKey? editKey;

  const _HomepageCell({
    super.key,
    required this.entry,
    required this.provider,
    required this.editKey,
  });

  @override
  Widget build(BuildContext context) {
    final child = entry.info.builder(entry.size);
    final key = editKey;
    if (key == null) {
      return child;
    }
    return _EditableWidget(
      key: key,
      widgetId: entry.info.id,
      provider: provider,
      child: child,
    );
  }
}

const _sideColumnHalves = 3;

/// Below this page height the tables keep their own height and the page scrolls.
const _minFilledHeight = 480.0;

double _gap(BuildContext context) =>
    SailTheme.of(context).isBitwindowV2 ? SailStyleValues.padding12 : SailStyleValues.padding16;

class HomepageWidgetEntry {
  final HomepageWidgetInfo info;
  final WidgetSize size;

  const HomepageWidgetEntry(this.info, this.size);
}

/// Two half-width widgets share a row. A bar or a full-width widget takes a row alone.
/// With [oneColumn], every widget takes a row alone, and a full-width widget builds at half width
/// unless it is [HomepageWidgetInfo.fullOnPhones].
List<List<HomepageWidgetEntry>> homepageRows(
  List<HomepageWidgetConfig> widgets,
  Map<String, HomepageWidgetInfo> catalog, {
  bool oneColumn = false,
}) {
  if (oneColumn) {
    return [
      for (final config in widgets)
        if (catalog[config.widgetId] case final info?)
          [
            HomepageWidgetEntry(
              info,
              info.sizeOf(config) == WidgetSize.full && !info.fullOnPhones ? WidgetSize.half : info.sizeOf(config),
            ),
          ],
    ];
  }
  final rows = <List<HomepageWidgetEntry>>[];
  List<HomepageWidgetEntry>? pair;
  for (final config in widgets) {
    final info = catalog[config.widgetId];
    if (info == null) {
      continue;
    }
    final entry = HomepageWidgetEntry(info, info.sizeOf(config));
    if (entry.size != WidgetSize.half) {
      if (pair != null) {
        rows.add(pair);
      }
      pair = null;
      rows.add([entry]);
      continue;
    }
    if (pair == null) {
      pair = [entry];
    } else {
      rows.add([...pair, entry]);
      pair = null;
    }
  }
  if (pair != null) {
    rows.add(pair);
  }
  return rows;
}

class _EditableWidget extends StatelessWidget {
  final String widgetId;
  final HomepageProvider provider;
  final Widget child;

  const _EditableWidget({
    super.key,
    required this.widgetId,
    required this.provider,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    final radius = theme.chrome.radius;

    return DragTarget<String>(
      onWillAcceptWithDetails: (details) {
        provider.moveTo(details.data, widgetId);
        return details.data != widgetId;
      },
      builder: (context, _, _) => LayoutBuilder(
        builder: (context, constraints) => Draggable<String>(
          key: Key('HomepageDrag-$widgetId'),
          data: widgetId,
          hitTestBehavior: HitTestBehavior.opaque,
          feedback: SizedBox(
            width: constraints.maxWidth,
            child: Transform.scale(
              scale: 1.04,
              child: Material(
                type: MaterialType.transparency,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    boxShadow: [
                      BoxShadow(
                        color: SailColorScheme.black.withValues(alpha: 0.35),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: IgnorePointer(child: child),
                ),
              ),
            ),
          ),
          childWhenDragging: Stack(
            children: [
              Opacity(opacity: 0, child: IgnorePointer(child: child)),
              Positioned.fill(
                child: DecoratedBox(
                  key: const Key('HomepageDropPlace'),
                  decoration: BoxDecoration(
                    color: theme.colors.backgroundSecondary,
                    borderRadius: radius,
                  ),
                ),
              ),
            ],
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              CustomPaint(
                foregroundPainter: _DashedOutline(
                  color: theme.colors.textTertiary,
                  radius: radius,
                ),
                child: IgnorePointer(child: child),
              ),
              Positioned(
                left: -_badgeOverhang,
                top: -_badgeOverhang,
                child: HomepageRoundBadge(
                  key: Key('HomepageRemove-$widgetId'),
                  icon: SailSVGAsset.minus,
                  onTap: () => provider.remove(widgetId),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The round badge on the corner of a widget: remove in edit mode, add or added in the library.
class HomepageRoundBadge extends StatelessWidget {
  final SailSVGAsset icon;
  final VoidCallback? onTap;
  final bool light;

  const HomepageRoundBadge({
    super.key,
    required this.icon,
    this.onTap,
    this.light = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = SailTheme.of(context).colors;
    final badge = Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: light ? colors.backgroundSecondary : colors.text,
      ),
      child: SailSVG.icon(
        icon,
        width: 14,
        height: 14,
        color: light ? colors.text : colors.background,
      ),
    );
    if (onTap == null) {
      return badge;
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: badge,
      ),
    );
  }
}

class _EditBar extends StatelessWidget {
  final bool saving;
  final VoidCallback onAdd;
  final Future<void> Function() onDone;

  const _EditBar({
    required this.saving,
    required this.onAdd,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final colors = SailTheme.of(context).colors;
    return Container(
      key: const Key('HomepageEditBar'),
      margin: const EdgeInsets.only(top: SailStyleValues.padding12),
      padding: const EdgeInsets.symmetric(vertical: SailStyleValues.padding10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: SailRow(
        mainAxisAlignment: MainAxisAlignment.end,
        spacing: SailStyleValues.padding08,
        children: [
          SailButton(
            key: const Key('HomepageAddWidget'),
            label: 'Add Widget',
            variant: ButtonVariant.secondary,
            skipLoading: true,
            disabled: saving,
            onPressed: () async => onAdd(),
          ),
          SailButton(
            key: const Key('HomepageDone'),
            label: 'Done',
            loading: saving,
            onPressed: onDone,
          ),
        ],
      ),
    );
  }
}

/// Clips to the child's box grown by [outset] on the top, left and right.
class _OutsetClipper extends CustomClipper<Rect> {
  final double outset;

  const _OutsetClipper(this.outset);

  @override
  Rect getClip(Size size) => Rect.fromLTRB(-outset, -outset, size.width + outset, size.height);

  @override
  bool shouldReclip(_OutsetClipper old) => old.outset != outset;
}

class _DashedOutline extends CustomPainter {
  final Color color;
  final BorderRadius radius;

  const _DashedOutline({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final outline = Path()..addRRect(radius.toRRect(Offset.zero & size).deflate(0.5));
    const dash = 6.0;
    const gap = 4.0;
    for (final metric in outline.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += dash + gap) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedOutline old) => old.color != color || old.radius != radius;
}
