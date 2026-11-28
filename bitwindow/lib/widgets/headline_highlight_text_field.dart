import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:sail_ui/sail_ui.dart';

/// The largest headline the backend accepts, in UTF-8 bytes.
const headlineMaxBytes = 64;

/// The end index in [text] of the headline: the first line, cut at [headlineMaxBytes] UTF-8 bytes on a character boundary.
int headlineEndIndex(String text) {
  var bytes = 0;
  var index = 0;
  for (final char in text.characters) {
    if (char.startsWith('\n') || char.startsWith('\r')) {
      return index;
    }
    final charBytes = utf8.encode(char).length;
    if (bytes + charBytes > headlineMaxBytes) {
      return index;
    }
    bytes += charBytes;
    index += char.length;
  }
  return index;
}

/// The text after the headline, without the line break that ends the headline.
String storyBody(String text) {
  final rest = text.substring(headlineEndIndex(text));
  for (final lineBreak in const ['\r\n', '\n', '\r']) {
    if (rest.startsWith(lineBreak)) {
      return rest.substring(lineBreak.length);
    }
  }
  return rest;
}

/// A TextEditingController that highlights the headline portion with a green background.
class HeadlineHighlightController extends TextEditingController {
  HeadlineHighlightController({super.text});

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    final text = this.text;
    if (text.isEmpty) {
      return TextSpan(style: style, text: text);
    }

    final headlineEnd = headlineEndIndex(text);
    final headlinePart = text.substring(0, headlineEnd);
    final restPart = text.substring(headlineEnd);

    return TextSpan(
      style: style,
      children: [
        TextSpan(
          text: headlinePart,
          style: TextStyle(backgroundColor: SailTheme.of(context).colors.success.withValues(alpha: 0.3)),
        ),
        if (restPart.isNotEmpty) TextSpan(text: restPart),
      ],
    );
  }
}

/// A text field that highlights the headline portion with a green background directly in the text field.
class HeadlineHighlightTextField extends StatefulWidget {
  final HeadlineHighlightController controller;
  final String hintText;
  final int minLines;
  final int? maxLines;
  final String? label;

  const HeadlineHighlightTextField({
    super.key,
    required this.controller,
    required this.hintText,
    this.minLines = 1,
    this.maxLines,
    this.label,
  });

  @override
  State<HeadlineHighlightTextField> createState() => _HeadlineHighlightTextFieldState();
}

class _HeadlineHighlightTextFieldState extends State<HeadlineHighlightTextField> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.controller.text;
    final headlineBytes = utf8.encode(text.substring(0, headlineEndIndex(text))).length;

    return SailColumn(
      spacing: SailStyleValues.padding08,
      children: [
        if (widget.label != null) SailText.primary13(widget.label!, bold: true),
        SailTextField(
          controller: widget.controller,
          hintText: widget.hintText,
          minLines: widget.minLines,
          maxLines: widget.maxLines,
        ),
        SailText.secondary12(
          'Headline: $headlineBytes/$headlineMaxBytes bytes',
        ),
      ],
    );
  }
}
