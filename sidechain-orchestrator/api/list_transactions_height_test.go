package api

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	wpb "github.com/LayerTwo-Labs/sidesail/sidechain-orchestrator/gen/walletmanager/v1"
	"github.com/LayerTwo-Labs/sidesail/sidechain-orchestrator/wallet"
)

func TestListTransactionsGivesTheBlockHeight(t *testing.T) {
	raw, _, tx := warningTransaction(t, warningOutputs(t)[:1])
	var rows []wallet.WalletTransaction
	require.NoError(t, json.Unmarshal(
		[]byte(`[{"txid":"`+tx.TxID+`","category":"receive","confirmations":3,"blockheight":102}]`), &rows))
	backend := &warningBackend{hexByID: map[string]string{tx.TxID: raw}, transactions: rows}
	h, walletID := newWarningHandler(t, backend)

	resp, err := h.ListTransactions(context.Background(), &wpb.ListTransactionsRequest{WalletId: walletID})
	require.NoError(t, err)
	require.Len(t, resp.Transactions, 1)
	assert.Equal(t, uint32(102), resp.Transactions[0].BlockHeight)
	assert.Equal(t, int32(3), resp.Transactions[0].Confirmations)
}
