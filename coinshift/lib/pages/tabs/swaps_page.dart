import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:sail_ui/sail_ui.dart';
import 'package:coinshift/providers/swap_provider.dart';
import 'package:coinshift/widgets/swap/swap_card.dart';
import 'package:coinshift/widgets/swap/swap_list.dart';

@RoutePage()
class SwapsTabPage extends StatelessWidget {
  const SwapsTabPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<SwapsPageViewModel>.reactive(
      viewModelBuilder: () => SwapsPageViewModel(),
      builder: (context, model, child) {
        return QtPage(
          child: SailColumn(
            spacing: SailStyleValues.padding12,
            children: [
              SwapStats(model: model),
              const Expanded(child: SwapList()),
            ],
          ),
        );
      },
    );
  }
}

@visibleForTesting
class SwapStats extends StatelessWidget {
  final SwapsPageViewModel model;

  const SwapStats({super.key, required this.model});

  @override
  Widget build(BuildContext context) {
    final items = [
      _StatItem(
        label: 'Total Swaps',
        value: model.totalSwaps.toString(),
      ),
      _StatItem(
        label: 'Active',
        value: model.activeSwaps.toString(),
      ),
      _StatItem(
        label: 'Ready to Claim',
        value: model.claimableSwaps.toString(),
      ),
      _StatItem(
        label: 'Completed',
        value: model.completedSwaps.toString(),
      ),
    ];

    final create = SailButton(label: 'Create Swap', onPressed: () => showCreateSwapDialog(context));
    if (SailStyleValues.phoneLayout(context)) {
      return SailCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(spacing: SailStyleValues.padding16, runSpacing: SailStyleValues.padding08, children: items),
            const SizedBox(height: SailStyleValues.padding12),
            create,
          ],
        ),
      );
    }

    return SailStrip(
      stats: [
        SailStat(label: 'Total Swaps', value: model.totalSwaps.toString()),
        SailStat(label: 'Active', value: model.activeSwaps.toString()),
        SailStat(label: 'Ready to Claim', value: model.claimableSwaps.toString()),
        SailStat(label: 'Completed', value: model.completedSwaps.toString()),
      ],
      actions: [create],
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;

  const _StatItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return SailColumn(
      spacing: SailStyleValues.padding04,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [SailText.secondary12(label), SailText.primary15(value, bold: true)],
    );
  }
}

class SwapsPageViewModel extends BaseViewModel {
  SwapProvider get _swapProvider => GetIt.I.get<SwapProvider>();

  int get totalSwaps => _swapProvider.swaps.length;
  int get activeSwaps => _swapProvider.activeSwaps.length;
  int get claimableSwaps => _swapProvider.claimableSwaps.length;
  int get completedSwaps => _swapProvider.completedSwaps.length;

  SwapsPageViewModel() {
    _swapProvider.addListener(notifyListeners);
  }

  @override
  void dispose() {
    _swapProvider.removeListener(notifyListeners);
    super.dispose();
  }
}
