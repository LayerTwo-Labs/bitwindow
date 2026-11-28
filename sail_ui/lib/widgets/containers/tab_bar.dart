import 'package:flutter/material.dart';
import 'package:sail_ui/sail_ui.dart';

class InlineTabBar extends StatefulWidget {
  final List<TabItem> tabs;
  final int initialIndex;
  final int? selectedIndex;
  final void Function(int)? onTabChanged;
  final Widget? endWidget;
  final bool secondary;

  /// Sits at the left of the tab strip and moves the strip to the right, as in a card head.
  final Widget? leading;

  const InlineTabBar({
    super.key,
    required this.tabs,
    this.initialIndex = 0,
    this.selectedIndex,
    this.onTabChanged,
    this.endWidget,
    this.secondary = false,
    this.leading,
  });

  @override
  State<InlineTabBar> createState() => InlineTabBarState();
}

class InlineTabBarState extends State<InlineTabBar> {
  late int _selectedIndex;
  String? _selectedSubItem;
  final Map<String, MenuController> _menuControllers = {};

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.selectedIndex ?? widget.initialIndex;
  }

  @override
  void didUpdateWidget(covariant InlineTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedIndex != null && widget.selectedIndex != _selectedIndex) {
      setState(() {
        _selectedIndex = widget.selectedIndex!;
        _selectedSubItem = null;
      });
    }
  }

  void setIndex(int index, String? label) {
    if (index >= 0 && index < widget.tabs.length) {
      setState(() {
        _selectedIndex = index;
        _selectedSubItem = label;
      });
      widget.onTabChanged?.call(index);
    } else {
      throw Exception(
        'Index out of bounds: index=$index, tabs.length=${widget.tabs.length}',
      );
    }
  }

  // Method to force rebuild when dropdown selection changes
  void refreshState() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    final v2 = theme.isBitwindowV2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (widget.leading != null) ...[
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: widget.leading,
                ),
              ),
              const SizedBox(width: SailStyleValues.padding12),
            ],
            Flexible(
              child: Container(
                padding: v2 ? const EdgeInsets.all(3) : const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
                decoration: BoxDecoration(
                  color: v2
                      ? theme.colors.formField
                      : widget.secondary
                      ? context.sailTheme.colors.background
                      : context.sailTheme.colors.backgroundSecondary,
                  borderRadius: theme.chrome.radius,
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SailRow(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: List.generate(widget.tabs.length, (index) {
                      final tab = widget.tabs[index];

                      if (tab is MultiSelectTabItem) {
                        // Ensure we have a controller for this tab
                        _menuControllers[tab.title] ??= MenuController();

                        return MenuAnchor(
                          controller: _menuControllers[tab.title]!,
                          style: MenuStyle(
                            backgroundColor: WidgetStatePropertyAll(
                              context.sailTheme.colors.backgroundSecondary,
                            ),
                            padding: const WidgetStatePropertyAll(
                              EdgeInsets.zero,
                            ),
                            shadowColor: const WidgetStatePropertyAll(
                              Colors.black26,
                            ),
                            elevation: const WidgetStatePropertyAll(4),
                            shape: WidgetStatePropertyAll(
                              RoundedRectangleBorder(
                                borderRadius: theme.chrome.radius,
                                side: BorderSide(
                                  color: context.sailTheme.colors.border,
                                ),
                              ),
                            ),
                          ),
                          menuChildren: [
                            SailMenu(
                              items: tab.items
                                  .map(
                                    (item) => SailMenuItem(
                                      onSelected: () {
                                        setIndex(index, item.label);
                                        item.onTap?.call();
                                        _menuControllers[tab.title]!.close();
                                      },
                                      child: SailText.primary13(item.label),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ],
                          builder: (context, controller, child) {
                            final isSelected = _selectedIndex == index && _selectedSubItem != null;
                            final displayLabel = isSelected && _selectedSubItem != null ? _selectedSubItem! : tab.label;

                            return SailTabItem(
                              label: displayLabel, // Use the dynamic label
                              isSelected: isSelected,
                              icon: tab.icon,
                              onIconTap: tab.onIconTap,
                              secondary: widget.secondary,
                              onTap: () {
                                if (controller.isOpen) {
                                  controller.close();
                                } else {
                                  controller.open();
                                }
                              },
                              withDropdown: true,
                            );
                          },
                        );
                      }

                      // Regular tab items
                      final isSelected = index == _selectedIndex && _selectedSubItem == null;
                      return SailTabItem(
                        label: tab.label,
                        isSelected: isSelected,
                        icon: tab.icon,
                        onIconTap: tab.onIconTap,
                        secondary: widget.secondary,
                        onLabelChanged: tab.onLabelChanged,
                        leading: tab.leading,
                        onTap: () {
                          setIndex(index, null);
                          if (tab.onTap != null) {
                            tab.onTap!();
                          }
                        },
                        withDropdown: false,
                      );
                    }),
                  ),
                ),
              ),
            ),
            if (widget.endWidget != null) widget.endWidget!,
          ],
        ),
        SizedBox(
          height: v2 ? SailStyleValues.padding12 : SailStyleValues.padding16,
        ),
        Expanded(
          child: () {
            final tab = widget.tabs[_selectedIndex];
            if (tab is MultiSelectTabItem && _selectedSubItem != null) {
              final selectedItem = tab.items.firstWhere(
                (item) => item.label == _selectedSubItem,
              );
              return selectedItem.child;
            }
            return tab.child;
          }(),
        ),
      ],
    );
  }
}

/// One tab in a strip. Pass [onLabelChanged] to let the selected tab be renamed.
class SailTabItem extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final SailSVGAsset? icon;
  final VoidCallback? onIconTap;
  final bool isSelected;
  final bool withDropdown;
  final bool secondary;
  final ValueChanged<String>? onLabelChanged;
  final Widget? leading;
  final Widget? trailing;

  const SailTabItem({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.icon,
    this.onIconTap,
    this.withDropdown = false,
    this.secondary = false,
    this.onLabelChanged,
    this.leading,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    final v2 = theme.isBitwindowV2;
    final labelColor = v2
        ? (isSelected ? theme.colors.text : theme.colors.textSecondary)
        : isSelected
        ? context.sailTheme.colors.activeNavText
        : context.sailTheme.colors.inactiveSubNavText;
    return InkWell(
      onTap: onTap,
      borderRadius: v2 ? theme.chrome.radiusSmall : null,
      child: Container(
        padding: EdgeInsets.symmetric(
          vertical: v2 ? 6 : SailStyleValues.padding04,
          horizontal: SailStyleValues.padding12,
        ),
        decoration: v2
            ? BoxDecoration(
                color: isSelected ? theme.colors.backgroundSecondary : Colors.transparent,
                borderRadius: theme.chrome.radiusSmall,
              )
            : theme.chrome.terminalStyle
            ? BoxDecoration(
                color: Colors.transparent,
                borderRadius: theme.chrome.radiusSmall,
                border: Border(
                  bottom: BorderSide(
                    color: isSelected ? context.sailTheme.colors.activeNavText : Colors.transparent,
                    width: 2.0,
                  ),
                ),
              )
            : BoxDecoration(
                color: isSelected
                    ? (secondary ? context.sailTheme.colors.backgroundSecondary : context.sailTheme.colors.background)
                    : Colors.transparent,
                borderRadius: theme.chrome.radius,
              ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: SailStyleValues.padding04),
            ],
            if (onLabelChanged != null && isSelected)
              SailEditableText(
                value: label,
                onSubmitted: onLabelChanged!,
                showPencil: false,
                editOnDoubleTap: true,
                style: SailStyleValues.thirteen.copyWith(
                  color: labelColor,
                  fontWeight: v2 ? FontWeight.w600 : null,
                ),
              )
            else if (v2)
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 2),
                style: SailStyleValues.thirteen.copyWith(
                  color: labelColor,
                  fontWeight: isSelected ? FontWeight.w600 : null,
                  fontFamily: theme.chrome.textFamily(),
                ),
              )
            else
              SailText.primary13(label, color: labelColor, bold: false),
            if (trailing != null) ...[
              const SizedBox(width: SailStyleValues.padding08),
              trailing!,
            ],
            if (icon != null) const SizedBox(width: SailStyleValues.padding04),
            if (icon != null)
              GestureDetector(
                onTap: onIconTap,
                child: SailSVG.fromAsset(icon!, color: labelColor, height: 13),
              )
            else if (withDropdown)
              SailSVG.fromAsset(SailSVGAsset.chevronDown, color: labelColor, width: 18, height: 18),
          ],
        ),
      ),
    );
  }
}

class SingleTabItem extends TabItem {
  const SingleTabItem({
    required super.label,
    required super.child,
    super.onTap,
    super.icon,
    super.onIconTap,
    super.onLabelChanged,
    super.leading,
  });
}

class MultiSelectTabItem extends TabItem {
  final String title; // The display title (e.g. "Tools")
  final List<TabItem> items;

  const MultiSelectTabItem({required this.title, required this.items})
    : super(
        label: title, // Use the title as the label
        child: const SizedBox(), // Not used since we handle content differently
      );
}

class TabItem {
  final String label;
  final Widget child;
  final VoidCallback? onTap;
  final SailSVGAsset? icon;
  final VoidCallback? onIconTap;

  /// Set to make the tab's label renameable while it is selected.
  final ValueChanged<String>? onLabelChanged;

  /// Small widget drawn before the label, e.g. a state dot.
  final Widget? leading;

  const TabItem({
    required this.label,
    required this.child,
    this.onTap,
    this.icon,
    this.onIconTap,
    this.onLabelChanged,
    this.leading,
  });
}
