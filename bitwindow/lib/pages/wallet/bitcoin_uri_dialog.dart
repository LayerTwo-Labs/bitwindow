import 'package:bitwindow/utils/bitcoin_uri.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';

class BitcoinURIDialog extends StatefulWidget {
  const BitcoinURIDialog({super.key});

  @override
  State<BitcoinURIDialog> createState() => _BitcoinURIDialogState();
}

class _BitcoinURIDialogState extends State<BitcoinURIDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _error;
  BitcoinURI? _parsedURI;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_parseURI);
  }

  void _parseURI() {
    if (_controller.text.trim().isEmpty) {
      setState(() {
        _error = null;
        _parsedURI = null;
      });
      return;
    }
    try {
      setState(() {
        _parsedURI = BitcoinURI.parse(_controller.text);
        _error = null;
      });
    } on FormatException catch (e) {
      setState(() {
        _error = e.message;
        _parsedURI = null;
      });
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_parseURI);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final formatter = GetIt.I<FormatterProvider>();

    return SailDialog(
      title: 'Open Bitcoin URI',
      withCloseButton: true,
      subtitle: 'Enter a Bitcoin URI to parse',
      error: _error,
      maxWidth: 520,
      maxHeight: 600,
      child: ListenableBuilder(
        listenable: formatter,
        builder: (context, child) => SailColumn(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: SailStyleValues.padding16,
          mainAxisSize: MainAxisSize.min,
          children: [
            SailTextField(
              label: 'Bitcoin URI',
              controller: _controller,
              hintText: 'bitcoin:<address>?amount=1.23',
            ),
            if (_parsedURI != null)
              Container(
                key: const Key('bitcoin-uri-parsed'),
                width: double.infinity,
                padding: const EdgeInsets.all(SailStyleValues.padding12),
                decoration: BoxDecoration(
                  color: context.sailTheme.colors.background,
                  borderRadius: context.sailTheme.chrome.radius,
                ),
                child: SailColumn(
                  spacing: SailStyleValues.padding04,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SailText.primary13('Address: ${_parsedURI!.address}', overflow: TextOverflow.visible),
                    if (_parsedURI!.amount != null)
                      SailText.primary13('Amount: ${formatter.formatBTC(_parsedURI!.amount!)}'),
                    if (_parsedURI!.label != null) SailText.primary13('Label: ${_parsedURI!.label}'),
                    if (_parsedURI!.message != null) SailText.primary13('Message: ${_parsedURI!.message}'),
                  ],
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: SailButton(
                label: 'Use',
                onPressed: () async {
                  if (_parsedURI != null) {
                    Navigator.of(context).pop(_parsedURI);
                  }
                },
                disabled: _parsedURI == null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
