package wallet

import (
	"bytes"
	"context"
	"encoding/hex"
	"encoding/json"
	"strings"
	"testing"

	pb "github.com/LayerTwo-Labs/sidesail/sidechain-orchestrator/gen/walletmanager/v1"
	"github.com/btcsuite/btcd/chaincfg"
	"github.com/btcsuite/btcd/wire"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func satsCoins(values ...int64) []orderedCoin[int64] {
	coins := make([]orderedCoin[int64], len(values))
	for i, v := range values {
		coins[i] = orderedCoin[int64]{coin: v, sats: v}
	}
	return coins
}

// needPlusFee asks for target sats plus 10 sats per input and 5 for change.
func needPlusFee(target int64) func([]int64, bool) int64 {
	return func(selected []int64, withChange bool) int64 {
		fee := int64(10 * len(selected))
		if withChange {
			fee += 5
		}
		return target + fee
	}
}

func TestPickCoins(t *testing.T) {
	coins := satsCoins(300, 100, 5000, 2000)
	cases := map[string]struct {
		order  CoinOrder
		target int64
		want   []int64
	}{
		"largest first":          {CoinOrderLargestFirst, 1000, []int64{5000}},
		"backend is largest":     {CoinOrderBackend, 1000, []int64{5000}},
		"smallest first":         {CoinOrderSmallestFirst, 350, []int64{100, 300}},
		"smallest first adds":    {CoinOrderSmallestFirst, 2500, []int64{100, 300, 2000, 5000}},
		"exact match":            {CoinOrderBranchAndBound, 2280, []int64{2000, 300}},
		"no exact match is big":  {CoinOrderBranchAndBound, 4000, []int64{5000}},
		"exact match of the sum": {CoinOrderBranchAndBound, 7360, []int64{5000, 2000, 300, 100}},
	}
	for name, tc := range cases {
		t.Run(name, func(t *testing.T) {
			got, err := pickCoins(coins, tc.order, needPlusFee(tc.target), 30)
			require.NoError(t, err)
			assert.Equal(t, tc.want, got)
		})
	}
}

func TestPickCoinsRandomPaysTheSend(t *testing.T) {
	coins := satsCoins(300, 100, 5000, 2000)
	seen := map[int64]bool{}
	for range 200 {
		got, err := pickCoins(coins, CoinOrderRandom, needPlusFee(250), 0)
		require.NoError(t, err)
		var sum int64
		for _, v := range got {
			sum += v
		}
		assert.GreaterOrEqual(t, sum, needPlusFee(250)(got, false))
		seen[got[0]] = true
	}
	assert.Len(t, seen, 4, "a random order starts with each coin")
}

func TestPickCoinsPaysWithNoChange(t *testing.T) {
	got, err := pickCoins(satsCoins(410), CoinOrderLargestFirst, needPlusFee(400), 0)
	require.NoError(t, err)
	assert.Equal(t, []int64{410}, got, "the coin pays the send and its fee with no change")
}

func TestPickCoinsShortOfFunds(t *testing.T) {
	_, err := pickCoins(satsCoins(100, 200), CoinOrderSmallestFirst, needPlusFee(400), 0)
	require.ErrorContains(t, err, "insufficient funds: need 420 sats, have 300 sats")
}

func TestCoinOrderMatchesTheProto(t *testing.T) {
	assert.Equal(t, CoinOrderBackend, CoinOrder(pb.CoinOrder_COIN_ORDER_UNSPECIFIED))
	assert.Equal(t, CoinOrderLargestFirst, CoinOrder(pb.CoinOrder_COIN_ORDER_LARGEST_FIRST))
	assert.Equal(t, CoinOrderSmallestFirst, CoinOrder(pb.CoinOrder_COIN_ORDER_SMALLEST_FIRST))
	assert.Equal(t, CoinOrderRandom, CoinOrder(pb.CoinOrder_COIN_ORDER_RANDOM))
	assert.Equal(t, CoinOrderBranchAndBound, CoinOrder(pb.CoinOrder_COIN_ORDER_BRANCH_AND_BOUND))
}

const p2wpkhCoinDesc = "wpkh([d34db33f/84h/1h/0h/0/0]02c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5)#8fhd9pwu"

func stubOrderCoins(fake *fakeBitcoind) {
	fake.handle("listunspent", func(bitcoindCall) (any, string) {
		return []map[string]any{
			{"txid": strings.Repeat("11", 32), "vout": 0, "amount": 50.0, "spendable": true, "safe": true, "desc": p2wpkhCoinDesc},
			{"txid": strings.Repeat("22", 32), "vout": 1, "amount": 1.0, "spendable": true, "safe": true, "desc": p2wpkhCoinDesc},
			{"txid": strings.Repeat("33", 32), "vout": 2, "amount": 0.2, "spendable": true, "safe": false, "desc": p2wpkhCoinDesc},
			{"txid": strings.Repeat("44", 32), "vout": 3, "amount": 2.0, "spendable": true, "safe": true, "desc": p2wpkhCoinDesc},
		}, ""
	})
}

func TestCoreBackendCreatePSBTSpendsTheCoinOrder(t *testing.T) {
	backend, fake, coreID := newCoreBackendFixture(t)
	fake.stubEnsureFlow()
	stubOrderCoins(fake)
	calls := stubFundedPSBT(t, fake, nil)
	dest := p2wpkhAddr(t, fixedKey(0xAA), &chaincfg.RegressionNetParams)

	_, err := backend.CreatePSBT(context.Background(), coreID, SendRequest{
		DestinationsSats: map[string]int64{dest: 50_000_000},
		FeeRateSatPerVB:  3,
		CoinOrder:        CoinOrderSmallestFirst,
	})
	require.NoError(t, err)

	require.Len(t, *calls, 1)
	call := (*calls)[0]
	var inputs []RawInput
	require.NoError(t, json.Unmarshal([]byte(call.rawInputs), &inputs))
	assert.Equal(t, []RawInput{{TxID: strings.Repeat("22", 32), Vout: 1}}, inputs,
		"the smallest safe coin pays; the unsafe coin stays")
	assert.Equal(t, false, call.options["add_inputs"], "Core adds no coin of its own")
}

func TestCoreBackendCreatePSBTLeavesBranchAndBoundToCore(t *testing.T) {
	backend, fake, coreID := newCoreBackendFixture(t)
	fake.stubEnsureFlow()
	stubOrderCoins(fake)
	calls := stubFundedPSBT(t, fake, nil)
	dest := p2wpkhAddr(t, fixedKey(0xAA), &chaincfg.RegressionNetParams)

	_, err := backend.CreatePSBT(context.Background(), coreID, SendRequest{
		DestinationsSats: map[string]int64{dest: 50_000_000},
		FeeRateSatPerVB:  3,
		CoinOrder:        CoinOrderBranchAndBound,
	})
	require.NoError(t, err)
	require.Len(t, *calls, 1)
	assert.Equal(t, "[]", (*calls)[0].rawInputs, "Core runs its own branch and bound")
}

func TestCoreBackendFixedFeeSpendsTheCoinOrder(t *testing.T) {
	cases := map[string]struct {
		order CoinOrder
		want  []RawInput
	}{
		"smallest first": {CoinOrderSmallestFirst, []RawInput{{TxID: strings.Repeat("22", 32), Vout: 1}}},
		"largest first":  {CoinOrderLargestFirst, []RawInput{{TxID: strings.Repeat("11", 32), Vout: 0}}},
		"exact match": {CoinOrderBranchAndBound, []RawInput{
			{TxID: strings.Repeat("44", 32), Vout: 3}, {TxID: strings.Repeat("22", 32), Vout: 1},
		}},
	}
	for name, tc := range cases {
		t.Run(name, func(t *testing.T) {
			backend, fake, coreID := newCoreBackendFixture(t)
			fake.stubEnsureFlow()
			stubOrderCoins(fake)
			needed := int64(299_999_800)
			if tc.order != CoinOrderBranchAndBound {
				needed = 50_000_000
			}
			got, _, err := backend.selectInputsForFixedFee(context.Background(), coreID, needed, tc.order)
			require.NoError(t, err)
			assert.Equal(t, tc.want, got)
		})
	}
}

func TestElectrumSendSpendsTheCoinOrder(t *testing.T) {
	cases := map[string]struct {
		order CoinOrder
		sats  int64
		want  []string
	}{
		"backend is largest first": {CoinOrderBackend, 50_000, []string{strings.Repeat("aa", 32)}},
		"smallest first":           {CoinOrderSmallestFirst, 50_000, []string{strings.Repeat("cc", 32)}},
		"smallest first adds":      {CoinOrderSmallestFirst, 150_000, []string{strings.Repeat("cc", 32), strings.Repeat("bb", 32)}},
		"exact match":              {CoinOrderBranchAndBound, 159_000, []string{strings.Repeat("bb", 32), strings.Repeat("cc", 32)}},
	}
	for name, tc := range cases {
		t.Run(name, func(t *testing.T) {
			p, fake, w, addr := newElectrumFixture(t)
			fake.stats[addr] = EsploraAddressStats{
				Address:    addr,
				ChainStats: EsploraTxoStats{FundedTxoCount: 3, FundedTxoSum: 1_260_000, TxCount: 3},
			}
			coin := func(txid string, sats int64) EsploraUTXO {
				return EsploraUTXO{TxID: txid, Vout: 0, Value: sats, Status: EsploraStatus{Confirmed: true, BlockHeight: 100}}
			}
			fake.utxos[addr] = []EsploraUTXO{
				coin(strings.Repeat("aa", 32), 1_000_000),
				coin(strings.Repeat("bb", 32), 100_000),
				coin(strings.Repeat("cc", 32), 60_000),
			}

			_, err := p.Send(context.Background(), w.ID, SendRequest{
				DestinationsSats: map[string]int64{"tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx": tc.sats},
				FixedFeeSats:     1_000,
				CoinOrder:        tc.order,
			})
			require.NoError(t, err)
			require.Len(t, fake.broadcast, 1)
			raw, err := hex.DecodeString(fake.broadcast[0])
			require.NoError(t, err)
			var tx wire.MsgTx
			require.NoError(t, tx.Deserialize(bytes.NewReader(raw)))
			var spent []string
			for _, in := range tx.TxIn {
				spent = append(spent, in.PreviousOutPoint.Hash.String())
			}
			assert.ElementsMatch(t, tc.want, spent)
			if tc.order == CoinOrderBranchAndBound {
				assert.Len(t, tx.TxOut, 1, "an exact match keeps no change")
			}
		})
	}
}

func TestElectrumSendWithNoRoomForChangeKeepsNoChange(t *testing.T) {
	p, fake, w, addr := newElectrumFixture(t)
	fake.stats[addr] = EsploraAddressStats{
		Address:    addr,
		ChainStats: EsploraTxoStats{FundedTxoCount: 1, FundedTxoSum: 112_000, TxCount: 1},
	}
	fake.utxos[addr] = []EsploraUTXO{{
		TxID: strings.Repeat("aa", 32), Vout: 0, Value: 112_000,
		Status: EsploraStatus{Confirmed: true, BlockHeight: 100},
	}}

	_, err := p.Send(context.Background(), w.ID, SendRequest{
		DestinationsSats: map[string]int64{"tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx": 100_000},
		FeeRateSatPerVB:  100,
		CoinOrder:        CoinOrderSmallestFirst,
	})
	require.NoError(t, err)
	require.Len(t, fake.broadcast, 1)
	raw, err := hex.DecodeString(fake.broadcast[0])
	require.NoError(t, err)
	var tx wire.MsgTx
	require.NoError(t, tx.Deserialize(bytes.NewReader(raw)))
	assert.Len(t, tx.TxOut, 1, "change the fee cannot pay for goes to the fee")
}

func TestElectrumSendPinnedCoinPaysWithNoChange(t *testing.T) {
	p, fake, w, addr := newElectrumFixture(t)
	fake.stats[addr] = EsploraAddressStats{
		Address:    addr,
		ChainStats: EsploraTxoStats{FundedTxoCount: 1, FundedTxoSum: 112_000, TxCount: 1},
	}
	fake.utxos[addr] = []EsploraUTXO{{
		TxID: strings.Repeat("aa", 32), Vout: 0, Value: 112_000,
		Status: EsploraStatus{Confirmed: true, BlockHeight: 100},
	}}

	_, err := p.Send(context.Background(), w.ID, SendRequest{
		DestinationsSats: map[string]int64{"tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx": 100_000},
		FeeRateSatPerVB:  100,
		RequiredInputs:   []RequiredInput{{TxID: strings.Repeat("aa", 32), Vout: 0, AmountSats: 112_000}},
	})
	require.NoError(t, err, "the pinned coin of a preview pays the same send")
	require.Len(t, fake.broadcast, 1)
	raw, err := hex.DecodeString(fake.broadcast[0])
	require.NoError(t, err)
	var tx wire.MsgTx
	require.NoError(t, tx.Deserialize(bytes.NewReader(raw)))
	assert.Len(t, tx.TxOut, 1)
}
