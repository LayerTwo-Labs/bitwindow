package wallet

import (
	"context"
	"sync/atomic"
	"testing"
	"time"

	"github.com/btcsuite/btcd/chaincfg"
	"github.com/rs/zerolog"
	"github.com/samber/lo"
	"github.com/stretchr/testify/require"
)

func historyTxids(t *testing.T, p *ElectrumBackend, walletID string) []string {
	t.Helper()
	rows, err := p.ListTransactions(context.Background(), walletID, 100)
	require.NoError(t, err)
	return lo.Uniq(lo.Map(rows, func(r WalletTransaction, _ int) string { return r.TxID }))
}

// After a fee bump the history lists the replacement, not the transaction it
// pushed out, before and after the next walk of the chain.
func TestElectrumHistoryShowsTheReplacementAfterABump(t *testing.T) {
	p, fake, w, txid, changeAddr := bumpFeeFixture(t)
	ctx := context.Background()
	require.Contains(t, historyTxids(t, p, w.ID), txid)

	result, err := p.BumpFee(ctx, w.ID, BumpFeeRequest{TxID: txid, NewFeeRate: 10})
	require.NoError(t, err)

	got := historyTxids(t, p, w.ID)
	require.Contains(t, got, result.NewTxID, "the cache carries the replacement at once")
	require.NotContains(t, got, txid, "the replaced transaction leaves the cache at once")

	// The server now serves the replacement in place of the original.
	original := fake.txByID[txid]
	replacement := original
	replacement.TxID = result.NewTxID
	replacement.Fee = result.Plan.NewFeeSats
	replacement.Vout = append([]EsploraVout(nil), original.Vout...)
	replacement.Vout[1].Value = result.Plan.AmountAfter
	fake.mu.Lock()
	fake.txByID[result.NewTxID] = replacement
	delete(fake.txByID, txid)
	for addr, txs := range fake.txs {
		fake.txs[addr] = lo.Map(txs, func(tx EsploraTx, _ int) EsploraTx {
			if tx.TxID == txid {
				return replacement
			}
			return tx
		})
	}
	change := fake.stats[changeAddr]
	change.MempoolStats.FundedTxoSum = result.Plan.AmountAfter
	fake.stats[changeAddr] = change
	fake.utxos[changeAddr] = []EsploraUTXO{{TxID: result.NewTxID, Vout: 1, Value: result.Plan.AmountAfter}}
	fake.mu.Unlock()

	p.mu.Lock()
	p.scanAt[w.ID] = time.Now().Add(-time.Hour)
	p.mu.Unlock()

	got = historyTxids(t, p, w.ID)
	require.Contains(t, got, result.NewTxID, "the walk finds the replacement")
	require.NotContains(t, got, txid, "the walk drops the replaced transaction")
}

// A replacement keeps the totals of the address it spends from, so a walk that
// reused the history behind equal totals kept the replaced transaction.
func TestElectrumWalkRereadsMempoolHistoryBehindEqualTotals(t *testing.T) {
	p, fake, w, txid, _ := bumpFeeFixture(t)
	require.Contains(t, historyTxids(t, p, w.ID), txid)

	replacement := fake.txByID[txid]
	replacement.TxID = "2222222222222222222222222222222222222222222222222222222222222222"
	fake.mu.Lock()
	fake.txByID[replacement.TxID] = replacement
	for addr, txs := range fake.txs {
		fake.txs[addr] = lo.Map(txs, func(tx EsploraTx, _ int) EsploraTx {
			if tx.TxID == txid {
				return replacement
			}
			return tx
		})
	}
	fake.mu.Unlock()

	p.mu.Lock()
	p.scanAt[w.ID] = time.Now().Add(-time.Hour)
	p.mu.Unlock()

	got := historyTxids(t, p, w.ID)
	require.Contains(t, got, replacement.TxID)
	require.NotContains(t, got, txid)
}

// gatedEsplora holds one AddressStats call until the test releases it.
type gatedEsplora struct {
	*fakeEsplora
	armed   atomic.Bool
	held    chan struct{}
	release chan struct{}
}

func (g *gatedEsplora) AddressStats(ctx context.Context, address string) (EsploraAddressStats, error) {
	if g.armed.CompareAndSwap(true, false) {
		close(g.held)
		<-g.release
	}
	return g.fakeEsplora.AddressStats(ctx, address)
}

// A walk that began before a fee bump must not put the replaced transaction
// back into the cache when it ends.
func TestElectrumWalkDuringABumpKeepsTheReplacement(t *testing.T) {
	p0, fake, w, txid, _ := bumpFeeFixture(t)
	gated := &gatedEsplora{fakeEsplora: fake, held: make(chan struct{}), release: make(chan struct{})}
	p := NewElectrumBackend(p0.svc, gated, StaticParams(&chaincfg.SigNetParams), zerolog.New(zerolog.NewTestWriter(t)))
	ctx := context.Background()
	require.Contains(t, historyTxids(t, p, w.ID), txid)

	gated.armed.Store(true)
	walked := make(chan error, 1)
	go func() {
		_, err := p.scan(ctx, w.ID, false)
		walked <- err
	}()
	<-gated.held

	result, err := p.BumpFee(ctx, w.ID, BumpFeeRequest{TxID: txid, NewFeeRate: 10})
	require.NoError(t, err)
	close(gated.release)
	require.NoError(t, <-walked)

	got := historyTxids(t, p, w.ID)
	require.Contains(t, got, result.NewTxID)
	require.NotContains(t, got, txid)
}
