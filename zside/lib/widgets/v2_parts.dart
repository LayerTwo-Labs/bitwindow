import 'package:flutter/widgets.dart';
import 'package:sail_ui/sail_ui.dart';

/// A short grey line of help text.
class DetailNote extends StatelessWidget {
  final String text;

  const DetailNote(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return SailText.primary12(text, color: SailTheme.of(context).colors.textSecondary, overflow: TextOverflow.visible);
  }
}

/// A 40 px amount or address field of a zSide form.
class ZSideField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final String? suffixText;
  final bool bitcoinInput;
  final bool autofocus;
  final bool disabled;

  const ZSideField({
    super.key,
    required this.controller,
    required this.hintText,
    this.suffixText,
    this.bitcoinInput = false,
    this.autofocus = false,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    return SailTextField(
      controller: controller,
      hintText: hintText,
      suffix: suffixText,
      autofocus: autofocus,
      enabled: !disabled,
      textFieldType: bitcoinInput ? TextFieldType.bitcoin : TextFieldType.text,
      inputFormatters: bitcoinInput ? [CommaReplacerInputFormatter()] : null,
    );
  }
}

/// A help text in a square dialog with a title and a ×.
class ZSideHelpDialog extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const ZSideHelpDialog({super.key, required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return SailModal(
      constraints: const BoxConstraints(maxWidth: 540, maxHeight: 640),
      child: SingleChildScrollView(
        child: SailCard(
          title: title,
          withCloseButton: true,
          child: SailColumn(
            spacing: SailStyleValues.padding08,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ),
    );
  }
}
