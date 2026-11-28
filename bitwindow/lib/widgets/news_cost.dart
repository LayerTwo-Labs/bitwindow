import 'dart:async';

import 'package:bitwindow/utils/error_text.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';

/// Prices a CoinNews action and warns the user the first time they pay for one.
class NewsCost {
  /// The cost of the action for this body, or why the wallet could not price it.
  static Future<NewsFeeResult> estimate(NewsAction action, {required String body}) async {
    try {
      return (estimate: await GetIt.I.get<BitwindowRPC>().misc.estimateNewsFee(action, body: body), error: null);
    } catch (e) {
      return (estimate: null, error: errorText(e));
    }
  }

  /// Shows the on-chain warning, with the cost of [body], the first time the user comments.
  /// Returns false only when the user backs out.
  static Future<bool> confirmFirstComment(BuildContext context, {required String body}) async {
    final settings = GetIt.I.get<ClientSettings>();
    if ((await settings.getValue(CommentWarningSeenSetting())).value) {
      return true;
    }

    final fee = await NewsCost.estimate(NewsAction.NEWS_ACTION_COMMENT, body: body);
    if (!context.mounted) {
      return false;
    }

    final confirmed = await _showWarning(context, fee: fee);
    if (!confirmed) {
      return false;
    }

    await settings.setValue(CommentWarningSeenSetting(newValue: true));
    return true;
  }

  static Future<bool> _showWarning(BuildContext context, {required NewsFeeResult fee}) async {
    var confirmed = false;

    await showThemedDialog(
      context: context,
      builder: (context) => SailDialog(
        title: 'Commenting costs a fee',
        actions: [
          SailButton(label: 'Cancel', variant: ButtonVariant.ghost, onPressed: () async => Navigator.of(context).pop()),
          SailButton(
            label: 'Comment',
            onPressed: () async {
              confirmed = true;
              Navigator.of(context).pop();
            },
          ),
        ],
        child: SizedBox(
          width: 420,
          child: SailColumn(
            spacing: SailStyleValues.padding12,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SailText.secondary13(
                'Commenting writes a transaction to the chain, so it costs a network fee and lands in about ten minutes.',
              ),
              if (fee.estimate case final estimate?) SailText.primary13(formatFee(estimate), bold: true),
              if (fee.error case final error?) SailText.secondary12(error, color: context.sailTheme.colors.error),
              SailText.secondary12('You only see this once.'),
            ],
          ),
        ),
      ),
    );

    return confirmed;
  }
}

/// The fee of a news action, or why the wallet could not price it.
typedef NewsFeeResult = ({NewsFeeEstimate? estimate, String? error});

/// Renders an estimate in the unit of the fee field, at the rate it assumes.
String formatFee(NewsFeeEstimate estimate) {
  final fee = GetIt.I.get<FormatterProvider>().formatSats(estimate.feeSats.toInt());
  final rate = estimate.feeSatPerVbyte.toStringAsFixed(1);
  return '≈ $fee  ·  ${estimate.vsize} vB at $rate sat/vB';
}

/// Wraps a control that spends money, so hovering it reveals the cost of the text in [body].
class NewsCostTooltip extends StatefulWidget {
  final NewsAction action;
  final TextEditingController body;
  final Widget child;

  const NewsCostTooltip({super.key, required this.action, required this.body, required this.child});

  @override
  State<NewsCostTooltip> createState() => _NewsCostTooltipState();
}

class _NewsCostTooltipState extends State<NewsCostTooltip> {
  NewsFeeResult? _fee;
  String? _priced;
  bool _checking = false;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    widget.body.addListener(_price);
  }

  @override
  void didUpdateWidget(NewsCostTooltip old) {
    super.didUpdateWidget(old);
    if (old.body != widget.body) {
      old.body.removeListener(_price);
      widget.body.addListener(_price);
    }
  }

  @override
  void dispose() {
    widget.body.removeListener(_price);
    super.dispose();
  }

  Future<void> _price() async {
    final body = widget.body.text.trim();
    if (!_hovered || body == _priced) {
      return;
    }
    _priced = body;
    if (body.isEmpty) {
      setState(() {
        _fee = null;
        _checking = false;
      });
      return;
    }
    setState(() => _checking = true);
    final fee = await NewsCost.estimate(widget.action, body: body);
    if (!mounted || body != _priced) {
      return;
    }
    setState(() {
      _fee = fee;
      _checking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final fee = _fee;
    return MouseRegion(
      onEnter: (_) {
        _hovered = true;
        _price();
      },
      onExit: (_) => _hovered = false,
      child: SailTooltip(
        message: switch ((_checking, fee?.estimate, fee?.error)) {
          (true, _, _) => 'Checking the fee…',
          (_, final estimate?, _) => formatFee(estimate),
          (_, _, final error?) => error,
          _ => '',
        },
        child: widget.child,
      ),
    );
  }
}

/// The fee of one news action, read again a short time after each input.
class FeeQuote {
  final VoidCallback _onChanged;

  FeeQuote(this._onChanged);

  NewsFeeEstimate? estimate;
  String? error;

  /// True from an input until the wallet gives the fee of the changed action.
  bool pending = false;

  Timer? _timer;
  int _reads = 0;
  bool _disposed = false;

  /// Prices [load] a short time after the last call. A null [load] clears the quote.
  void update(Future<NewsFeeEstimate> Function()? load) {
    _timer?.cancel();
    final read = ++_reads;
    estimate = null;
    error = null;
    pending = load != null;
    if (load == null) {
      return;
    }
    _timer = Timer(const Duration(milliseconds: 400), () async {
      NewsFeeEstimate? result;
      String? reason;
      try {
        result = await load();
      } catch (e) {
        reason = errorText(e);
      }
      if (_disposed || read != _reads) {
        return;
      }
      estimate = result;
      error = reason;
      pending = false;
      _onChanged();
    });
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
  }
}

/// Shows the state of [quote] as one line, after [lead].
class FeeQuoteText extends StatelessWidget {
  final FeeQuote quote;
  final String lead;

  const FeeQuoteText({super.key, required this.quote, this.lead = ''});

  @override
  Widget build(BuildContext context) {
    if (quote.pending) {
      return SailText.secondary12('${lead}Checking the fee…');
    }
    if (quote.estimate case final estimate?) {
      return SailText.secondary12('${lead}Network fee: ${formatFee(estimate)}');
    }
    if (quote.error case final error?) {
      return SailText.secondary12('$lead$error', color: context.sailTheme.colors.error);
    }
    return const SizedBox.shrink();
  }
}
