package wallet_test

import (
	"context"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.uber.org/mock/gomock"

	"github.com/LayerTwo-Labs/sidesail/bitwindow/server/database"
	walletpb "github.com/LayerTwo-Labs/sidesail/bitwindow/server/gen/wallet/v1"
	"github.com/LayerTwo-Labs/sidesail/bitwindow/server/gen/wallet/v1/walletv1connect"
	"github.com/LayerTwo-Labs/sidesail/bitwindow/server/tests/apitests"
	"github.com/LayerTwo-Labs/sidesail/bitwindow/server/tests/mocks"
	orchpb "github.com/LayerTwo-Labs/sidesail/sidechain-orchestrator/gen/walletmanager/v1"
	orchrpc "github.com/LayerTwo-Labs/sidesail/sidechain-orchestrator/gen/walletmanager/v1/walletmanagerv1connect"
)

// coreStatsOrchestrator serves the history of one Bitcoin Core wallet.
type coreStatsOrchestrator struct {
	orchrpc.WalletManagerServiceClient

	transactions []*orchpb.TransactionEntry
	unspent      []*orchpb.UnspentOutput
}

func (o coreStatsOrchestrator) ListTransactions(context.Context, *orchpb.ListTransactionsRequest) (*orchpb.ListTransactionsResponse, error) {
	return &orchpb.ListTransactionsResponse{Transactions: o.transactions}, nil
}

func (o coreStatsOrchestrator) ListUnspent(context.Context, *orchpb.ListUnspentRequest) (*orchpb.ListUnspentResponse, error) {
	return &orchpb.ListUnspentResponse{Utxos: o.unspent}, nil
}

func (coreStatsOrchestrator) GetSidechainDepositTotals(context.Context, *orchpb.GetSidechainDepositTotalsRequest) (*orchpb.GetSidechainDepositTotalsResponse, error) {
	return &orchpb.GetSidechainDepositTotalsResponse{}, nil
}

func coreStats(t *testing.T, txs []*orchpb.TransactionEntry, utxos []*orchpb.UnspentOutput) *walletpb.GetStatsResponse {
	t.Helper()
	core := mocks.NewMockBitcoinServiceClient(gomock.NewController(t))
	apitests.ExpectCoreWalletSetup(core)
	orch := coreStatsOrchestrator{
		WalletManagerServiceClient: apitests.OpenWallet(apitests.CoreWalletOrchestrator(t), &orchpb.WalletMetadata{Id: testWalletID, WalletType: orchpb.WalletType_WALLET_TYPE_BITCOIN_CORE}),
		transactions:               txs,
		unspent:                    utxos,
	}
	client := walletv1connect.NewWalletServiceClient(apitests.RPC(t, database.Test(t), apitests.WithCoreWallet(), apitests.WithBitcoind(core), apitests.WithOrchestrator(orch)))
	response, err := client.GetStats(t.Context(), &walletpb.GetStatsRequest{WalletId: testWalletID})
	require.NoError(t, err)
	return response
}

func TestStatsCountTheRowsOfTheHistory(t *testing.T) {
	t.Run("a replaced send counts no fee and no transaction", func(t *testing.T) {
		response := coreStats(t, []*orchpb.TransactionEntry{
			{Txid: "replaced", Category: "send", AmountSats: -50_000_000, Fee: -0.00000282, ReplacedByTxid: true},
			{Txid: "replacement", Category: "send", AmountSats: -50_000_000, Fee: -0.0000282},
			{Txid: "conflicted", Category: "send", AmountSats: -1_000, Fee: -0.00000100, Confirmations: -1},
		}, nil)
		assert.Equal(t, int64(1), response.TransactionCountTotal)
		assert.Equal(t, int64(2_820), response.TotalFeesSats)
	})

	t.Run("an abandoned send counts as a row without a paid fee", func(t *testing.T) {
		response := coreStats(t, []*orchpb.TransactionEntry{
			{Txid: "confirmed", Category: "send", AmountSats: -1_000, Fee: -0.00000282, Confirmations: 1},
			{Txid: "pending", Category: "send", AmountSats: -2_000, Fee: -0.00000282},
			{Txid: "abandoned", Category: "send", AmountSats: -3_000, Fee: -0.00000416, Abandoned: true},
			{Txid: "abandoned", Category: "send", AmountSats: -4_000, Fee: -0.00000416, Abandoned: true},
			{Txid: "abandoned", Category: "receive", AmountSats: 4_000},
		}, nil)
		assert.Equal(t, int64(3), response.TransactionCountTotal)
		assert.Equal(t, int64(564), response.TotalFeesSats)
	})

	t.Run("unconfirmed change counts as a UTXO", func(t *testing.T) {
		response := coreStats(t, nil, []*orchpb.UnspentOutput{
			{Txid: "send", Vout: 1, Address: "bcrt1qchange", AmountSats: 4_949_999_718},
		})
		assert.Equal(t, uint64(1), response.UtxosCurrent)
		assert.Equal(t, uint64(1), response.UtxosUniqueAddresses)
	})
}

func TestStatsLastActivityIsTheNewestBlock(t *testing.T) {
	const sameTime = int64(1795035587)
	response := coreStats(t, []*orchpb.TransactionEntry{
		{Txid: "block-98", Category: "generate", AmountSats: 5_000_000_000, Confirmations: 3, BlockHeight: 98, BlockTime: sameTime},
		{Txid: "block-99", Category: "generate", AmountSats: 5_000_000_000, Confirmations: 2, BlockHeight: 99, BlockTime: sameTime},
		{Txid: "block-100", Category: "immature", AmountSats: 5_000_000_000, Confirmations: 1, BlockHeight: 100, BlockTime: sameTime},
	}, nil)
	assert.Equal(t, uint32(100), response.LastTxBlockHeight)
	assert.Equal(t, sameTime, response.LastTxAt.Seconds)
	assert.Equal(t, int64(3), response.TransactionCountTotal)
}
