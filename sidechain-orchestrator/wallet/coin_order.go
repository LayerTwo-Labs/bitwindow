package wallet

import (
	"fmt"
	"math/rand/v2"
	"slices"
)

// CoinOrder selects the coins of a send that pins no input.
type CoinOrder int

const (
	// CoinOrderBackend keeps the backend selection: Bitcoin Core's own for a
	// fee rate, else largest first.
	CoinOrderBackend CoinOrder = iota
	CoinOrderLargestFirst
	CoinOrderSmallestFirst
	CoinOrderRandom
	// CoinOrderBranchAndBound looks for coins that pay the send with no change.
	CoinOrderBranchAndBound
)

// branchAndBoundTries caps the exact-match search, as Bitcoin Core does.
const branchAndBoundTries = 100_000

// orderedCoin is one coin a selection can spend.
type orderedCoin[T any] struct {
	coin T
	sats int64
}

// pickCoins selects coins in order until they pay needSats for the selection
// with no change. A send whose coins pay more keeps change.
// needSats gets the selected coins and whether the send keeps a change output.
// changeCostSats is what a change output costs. A branch-and-bound selection
// with no exact match falls back to largest first.
func pickCoins[T any](
	coins []orderedCoin[T], order CoinOrder, needSats func(selected []T, withChange bool) int64, changeCostSats int64,
) ([]T, error) {
	ordered := slices.Clone(coins)
	switch order {
	case CoinOrderSmallestFirst:
		slices.SortStableFunc(ordered, func(a, b orderedCoin[T]) int { return compareSats(a.sats, b.sats) })
	case CoinOrderRandom:
		rand.Shuffle(len(ordered), func(i, j int) { ordered[i], ordered[j] = ordered[j], ordered[i] })
	default:
		slices.SortStableFunc(ordered, func(a, b orderedCoin[T]) int { return compareSats(b.sats, a.sats) })
	}
	if order == CoinOrderBranchAndBound {
		if exact, ok := exactMatch(ordered, needSats, changeCostSats); ok {
			return exact, nil
		}
	}

	var selected []T
	var selectedSats int64
	for _, c := range ordered {
		selected = append(selected, c.coin)
		selectedSats += c.sats
		if selectedSats >= needSats(selected, false) {
			return selected, nil
		}
	}
	need := needSats(selected, false)
	return nil, fmt.Errorf("insufficient funds: need %d sats, have %d sats", need, selectedSats)
}

// exactMatch searches the coins, largest first, for a set worth at least the
// send with no change and less than that plus changeCostSats.
func exactMatch[T any](
	largestFirst []orderedCoin[T], needSats func(selected []T, withChange bool) int64, changeCostSats int64,
) ([]T, bool) {
	remaining := make([]int64, len(largestFirst)+1)
	for i := len(largestFirst) - 1; i >= 0; i-- {
		remaining[i] = remaining[i+1] + largestFirst[i].sats
	}
	var selected []T
	tries := 0
	var search func(i int, sum int64) bool
	search = func(i int, sum int64) bool {
		tries++
		if tries > branchAndBoundTries {
			return false
		}
		if len(selected) > 0 {
			need := needSats(selected, false)
			if sum >= need {
				return sum < need+changeCostSats
			}
		}
		if i == len(largestFirst) || sum+remaining[i] < needSats(append(selected, largestFirst[i].coin), false) {
			return false
		}
		selected = append(selected, largestFirst[i].coin)
		if search(i+1, sum+largestFirst[i].sats) {
			return true
		}
		selected = selected[:len(selected)-1]
		return search(i+1, sum)
	}
	if search(0, 0) {
		return selected, true
	}
	return nil, false
}

func compareSats(a, b int64) int {
	switch {
	case a < b:
		return -1
	case a > b:
		return 1
	default:
		return 0
	}
}
