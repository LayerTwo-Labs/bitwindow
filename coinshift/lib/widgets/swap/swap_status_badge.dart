import 'package:flutter/widgets.dart';
import 'package:sail_ui/pages/sidechains/sidechain_overview_page.dart';
import 'package:sail_ui/sail_ui.dart';

/// The status of a swap as a dot and a label.
class SwapStatusBadge extends StatelessWidget {
  final SwapState state;

  const SwapStatusBadge({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return SidechainStatusText(tone: swapStatusTone(state), text: swapStatusLabel(state));
  }
}

String swapStatusLabel(SwapState state) {
  if (state.isPending) {
    return 'Pending';
  }
  if (state.isWaitingConfirmations) {
    return '${state.currentConfirmations ?? 0}/${state.requiredConfirmations ?? 6} confirmations';
  }
  if (state.isReadyToClaim) {
    return 'Ready to Claim';
  }
  if (state.isCompleted) {
    return 'Completed';
  }
  if (state.isCancelled) {
    return 'Cancelled';
  }
  return state.state;
}

SailStatusTone swapStatusTone(SwapState state) {
  if (state.isPending) {
    return SailStatusTone.warning;
  }
  if (state.isWaitingConfirmations) {
    return SailStatusTone.info;
  }
  if (state.isReadyToClaim) {
    return SailStatusTone.success;
  }
  if (state.isCancelled) {
    return SailStatusTone.error;
  }
  return SailStatusTone.neutral;
}
