import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';

/// Prices a CoinNews action and warns the user the first time they pay for one.
class NewsCost {
  /// Estimated cost of the action for this body, or null when the server gives none.
  static Future<NewsFeeEstimate?> estimate(NewsAction action, {required String body}) async {
    try {
      return await GetIt.I.get<BitwindowRPC>().misc.estimateNewsFee(action, body: body);
    } catch (_) {
      // a missing estimate must not block a comment
      return null;
    }
  }

  /// Shows the on-chain warning, with the cost of [body], the first time the user comments.
  /// Returns false only when the user backs out.
  static Future<bool> confirmFirstComment(BuildContext context, {required String body}) async {
    final settings = GetIt.I.get<ClientSettings>();
    if ((await settings.getValue(CommentWarningSeenSetting())).value) {
      return true;
    }

    final estimate = await NewsCost.estimate(NewsAction.NEWS_ACTION_COMMENT, body: body);
    if (!context.mounted) {
      return false;
    }

    final confirmed = await _showWarning(context, estimate: estimate);
    if (!confirmed) {
      return false;
    }

    await settings.setValue(CommentWarningSeenSetting(newValue: true));
    return true;
  }

  static Future<bool> _showWarning(BuildContext context, {required NewsFeeEstimate? estimate}) async {
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
              if (estimate != null) SailText.primary13(formatFee(estimate), bold: true),
              SailText.secondary12('You only see this once.'),
            ],
          ),
        ),
      ),
    );

    return confirmed;
  }
}

/// Renders an estimate as the sats it costs, at the rate it assumes.
String formatFee(NewsFeeEstimate estimate) {
  final rate = estimate.feeSatPerVbyte.toStringAsFixed(1);
  return '≈ ${estimate.feeSats} sats  ·  ${estimate.vsize} vB at $rate sat/vB';
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
  NewsFeeEstimate? _estimate;
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
        _estimate = null;
        _checking = false;
      });
      return;
    }
    setState(() => _checking = true);
    final estimate = await NewsCost.estimate(widget.action, body: body);
    if (!mounted || body != _priced) {
      return;
    }
    setState(() {
      _estimate = estimate;
      _checking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final estimate = _estimate;
    return MouseRegion(
      onEnter: (_) {
        _hovered = true;
        _price();
      },
      onExit: (_) => _hovered = false,
      child: SailTooltip(
        message: _checking
            ? 'Checking the fee…'
            : estimate == null
            ? ''
            : formatFee(estimate),
        child: widget.child,
      ),
    );
  }
}
