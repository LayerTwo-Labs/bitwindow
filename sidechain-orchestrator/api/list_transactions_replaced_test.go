package api

import (
	"context"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	wpb "github.com/LayerTwo-Labs/sidesail/sidechain-orchestrator/gen/walletmanager/v1"
	"github.com/LayerTwo-Labs/sidesail/sidechain-orchestrator/wallet"
)

func TestListTransactionsMarksAReplacedTransaction(t *testing.T) {
	oldRaw, _, oldTx := warningTransaction(t, warningOutputs(t)[:1])
	newRaw, _, newTx := warningTransaction(t, warningOutputs(t)[1:])
	require.NotEqual(t, oldTx.TxID, newTx.TxID)
	backend := &warningBackend{
		hexByID: map[string]string{oldTx.TxID: oldRaw, newTx.TxID: newRaw},
		transactions: []wallet.WalletTransaction{
			{TxID: oldTx.TxID, Category: "send", MempoolConflicts: []string{newTx.TxID}},
			{TxID: newTx.TxID, Category: "send"},
		},
	}
	h, walletID := newWarningHandler(t, backend)

	resp, err := h.ListTransactions(context.Background(), &wpb.ListTransactionsRequest{WalletId: walletID})
	require.NoError(t, err)
	replaced := map[string]bool{}
	for _, entry := range resp.Transactions {
		replaced[entry.Txid] = entry.ReplacedByTxid
	}
	assert.Equal(t, map[string]bool{oldTx.TxID: true, newTx.TxID: false}, replaced)
}

func TestListTransactionsKeepsTheAbandonedFee(t *testing.T) {
	raw, _, tx := warningTransaction(t, warningOutputs(t)[:1])
	backend := &warningBackend{
		hexByID: map[string]string{tx.TxID: raw},
		transactions: []wallet.WalletTransaction{
			{TxID: tx.TxID, Category: "send", Amount: -0.00257963, Fee: -0.00000282, Abandoned: true},
		},
	}
	h, walletID := newWarningHandler(t, backend)

	resp, err := h.ListTransactions(t.Context(), &wpb.ListTransactionsRequest{WalletId: walletID})
	require.NoError(t, err)
	require.Len(t, resp.Transactions, 1)
	entry := resp.Transactions[0]
	assert.True(t, entry.Abandoned)
	assert.False(t, entry.ReplacedByTxid)
	assert.Equal(t, int64(-257_963), entry.AmountSats)
	assert.Equal(t, -0.00000282, entry.Fee)
}
