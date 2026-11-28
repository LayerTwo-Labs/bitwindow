import 'package:flutter/widgets.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:zside/widgets/v2_parts.dart';

/// A square action dialog: title and × in the head, the form, and one full-width action.
class DashboardActionModal extends StatelessWidget {
  const DashboardActionModal(
    this.title, {
    super.key,
    required this.children,
    required this.endActionButton,
  });

  final String title;
  final List<Widget> children;
  final Widget endActionButton;

  @override
  Widget build(BuildContext context) {
    return SailModal(
      constraints: const BoxConstraints(maxWidth: 540),
      child: SailCard(
        title: title,
        withCloseButton: true,
        child: ActionForm(action: endActionButton, children: children),
      ),
    );
  }
}

/// The body of a zSide action: fields, the read-only values in one grey group, notes, and the action at full width.
class ActionForm extends StatelessWidget {
  final List<Widget> children;
  final Widget action;

  const ActionForm({super.key, required this.children, required this.action});

  @override
  Widget build(BuildContext context) {
    final parts = <Widget>[];
    var group = <Widget>[];
    void closeGroup() {
      if (group.isNotEmpty) {
        parts.add(SailDetailGroup(fill: SailDetailFill.canvas, children: group));
        group = [];
      }
    }

    for (final child in children) {
      if (child is StaticActionField) {
        group.add(SailDetailLine(wrap: true, label: child.label ?? '', value: child.value, copyable: child.copyable));
        continue;
      }
      closeGroup();
      parts.add(child is StaticActionInfo ? DetailNote(child.text) : child);
    }
    closeGroup();

    return SailColumn(
      spacing: SailStyleValues.padding12,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...parts,
        SizedBox(width: double.infinity, child: action),
      ],
    );
  }
}
