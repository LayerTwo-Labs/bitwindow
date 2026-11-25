package engines

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestSimpleSplitKeepsValueForEachRemainingHop(t *testing.T) {
	t.Parallel()

	for hops := int32(1); hops <= 6; hops++ {
		for percentage := 10; percentage < 90; percentage++ {
			tip := DenialMinValue(hops)
			for done := int32(0); done < hops; done++ {
				require.GreaterOrEqual(t, tip, uint64(denialHopFee+denialDustLimit), "hop %d of %d at %d%%", done+1, hops, percentage)
				available := tip - denialHopFee
				hopsAfter := hops - done - 1

				sent := simpleSplitAmount(available, percentage, hopsAfter)

				require.GreaterOrEqual(t, available-sent, uint64(denialDustLimit), "change of hop %d of %d at %d%%", done+1, hops, percentage)
				if hopsAfter > 0 {
					require.GreaterOrEqual(t, sent, DenialMinValue(hopsAfter), "tip after hop %d of %d at %d%%", done+1, hops, percentage)
				}
				tip = sent
			}
		}
	}
}

func TestSimpleSplitKeepsThePercentageOfALargeCoin(t *testing.T) {
	t.Parallel()

	require.Equal(t, uint64(25_000_000), simpleSplitAmount(100_000_000, 25, 5))
}

func TestSimpleSplitOfACoinBelowTheMinimumUsesTheDustFloor(t *testing.T) {
	t.Parallel()

	require.Equal(t, uint64(1_500), simpleSplitAmount(15_000, 10, 2))
}
