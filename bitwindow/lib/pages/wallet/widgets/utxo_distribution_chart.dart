import 'package:flutter/widgets.dart';
import 'package:sidechain_core/gen/wallet/v1/wallet.pb.dart';
import 'package:sail_ui/sail_ui.dart';

/// A group of coins in one value range.
class UtxoBucket {
  /// The value range without a unit, for example "0.01–0.1".
  final String label;
  int valueSats = 0;
  int count = 0;
  final List<String> outpoints = [];

  UtxoBucket(this.label);
}

/// Upper bounds in sats of the buckets: 0.001, 0.01, 0.1, 1 and 10 coins.
const List<int> utxoBucketBounds = [100000, 1000000, 10000000, 100000000, 1000000000];
const List<String> utxoBucketLabels = ['< 0.001', '0.001–0.01', '0.01–0.1', '0.1–1', '1–10', '> 10'];
const List<String> phoneUtxoBucketLabels = ['<.001', '.001–.01', '.01–.1', '.1–1', '1–10', '>10'];

/// The coins sorted into the six buckets, smallest first. A bucket with no coins stays in the list.
List<UtxoBucket> utxoBuckets(List<UnspentOutput> utxos, {List<String> labels = utxoBucketLabels}) {
  final buckets = [for (final label in labels) UtxoBucket(label)];
  for (final utxo in utxos) {
    final sats = utxo.valueSats.toInt();
    var index = utxoBucketBounds.indexWhere((bound) => sats < bound);
    if (index < 0) {
      index = utxoBucketBounds.length;
    }
    final bucket = buckets[index];
    bucket.valueSats += sats;
    bucket.count += 1;
    bucket.outpoints.add(utxo.output);
  }
  return buckets;
}

/// True when the buckets that hold less than 5% of the value hold more than one coin.
bool hasSmallUtxos(List<UtxoBucket> buckets) {
  final total = buckets.fold<int>(0, (sum, b) => sum + b.valueSats);
  if (total == 0) {
    return false;
  }
  final small = buckets.where((b) => b.count > 0 && b.valueSats * 100 < total * 5);
  return small.fold<int>(0, (sum, b) => sum + b.count) > 1;
}

/// The UTXO distribution: one bar per bucket, with the coin count above it.
class UTXOBars extends StatelessWidget {
  final List<UnspentOutput> utxos;
  final void Function(UtxoBucket bucket, Offset position)? onBucketContextMenu;
  final VoidCallback? onConsolidate;

  const UTXOBars({super.key, required this.utxos, this.onBucketContextMenu, this.onConsolidate});

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    final phone = SailStyleValues.phoneLayout(context);
    final buckets = utxoBuckets(utxos, labels: phone ? phoneUtxoBucketLabels : utxoBucketLabels);
    final most = buckets.fold<int>(0, (most, b) => b.count > most ? b.count : most);
    final barWidth = phone ? 38.0 : 160.0;
    final maxBarHeight = phone ? 100.0 : 120.0;

    final bars = SizedBox(
      height: phone ? 150 : 180,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < buckets.length; i++)
            Expanded(
              child: GestureDetector(
                key: ValueKey('utxo_bar_$i'),
                behavior: HitTestBehavior.opaque,
                onLongPressStart: buckets[i].count == 0
                    ? null
                    : (details) => onBucketContextMenu?.call(buckets[i], details.globalPosition),
                onSecondaryTapUp: buckets[i].count == 0
                    ? null
                    : (details) => onBucketContextMenu?.call(buckets[i], details.globalPosition),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (buckets[i].count > 0) ...[
                      SailText.primary12('${buckets[i].count}'),
                      const SizedBox(height: SailStyleValues.padding04),
                    ],
                    Container(
                      width: barWidth,
                      height: buckets[i].count == 0 ? 1 : maxBarHeight * buckets[i].count / most,
                      color: buckets[i].count == 0 ? theme.colors.divider : theme.colors.orange,
                    ),
                    const SizedBox(height: SailStyleValues.padding08),
                    SailText.secondary12(buckets[i].label),
                  ],
                ),
              ),
            ),
        ],
      ),
    );

    if (onConsolidate == null || !hasSmallUtxos(buckets)) {
      return bars;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        bars,
        const SizedBox(height: SailStyleValues.padding08),
        SailButton(
          label: 'Consolidate Small UTXOs',
          variant: ButtonVariant.secondary,
          small: true,
          onPressed: () async => onConsolidate!(),
        ),
      ],
    );
  }
}
