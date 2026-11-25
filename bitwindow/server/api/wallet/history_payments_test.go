package wallet_test

import (
	"testing"

	connectv1 "connectrpc.com/connect"
	corepb "github.com/barebitcoin/btc-buf/gen/bitcoin/bitcoind/v1alpha"
	"github.com/samber/lo"
	"github.com/stretchr/testify/require"
	"go.uber.org/mock/gomock"

	"github.com/LayerTwo-Labs/sidesail/bitwindow/server/database"
	walletv1 "github.com/LayerTwo-Labs/sidesail/bitwindow/server/gen/wallet/v1"
	walletv1connect "github.com/LayerTwo-Labs/sidesail/bitwindow/server/gen/wallet/v1/walletv1connect"
	"github.com/LayerTwo-Labs/sidesail/bitwindow/server/tests/apitests"
	"github.com/LayerTwo-Labs/sidesail/bitwindow/server/tests/mocks"
	orchpb "github.com/LayerTwo-Labs/sidesail/sidechain-orchestrator/gen/walletmanager/v1"
)

type payment struct {
	address string
	sats    uint64
}

func paymentsOf(tx *walletv1.WalletTransaction) []payment {
	return lo.Map(tx.Payments, func(p *walletv1.TransactionPayment, _ int) payment {
		return payment{p.Address, p.AmountSats}
	})
}

func TestHistoryPayments(t *testing.T) {
	t.Parallel()

	t.Run("orchestrator rows name each payment of a transaction", func(t *testing.T) {
		t.Parallel()

		db := database.Test(t)
		mockOrch := mocks.NewMockWalletManagerServiceClient(gomock.NewController(t))
		mockOrch.EXPECT().
			ListTransactions(gomock.Any(), gomock.Any()).
			Return(&orchpb.ListTransactionsResponse{
				Transactions: []*orchpb.TransactionEntry{
					{Txid: "many", Vout: 3, Address: "small", Category: "send", AmountSats: -50_000, Confirmations: 1},
					{Txid: "many", Vout: 1, Address: "large", Category: "send", AmountSats: -200_000_000, Confirmations: 1},
					{Txid: "many", Vout: 0, Address: "middle", Category: "send", AmountSats: -100_000_000, Confirmations: 1},
					{Txid: "mixed", Vout: 2, Address: "own", Label: "savings", Category: "receive", AmountSats: 20_000, Confirmations: 1},
					{Txid: "mixed", Vout: 2, Address: "own", Label: "savings", Category: "send", AmountSats: -20_000, Confirmations: 1},
					{Txid: "mixed", Vout: 1, Address: "shop", Category: "send", AmountSats: -10_000, Confirmations: 1},
					{Txid: "self", Vout: 1, Address: "own", Label: "savings", Category: "receive", AmountSats: 50_000_000, Confirmations: 1},
					{Txid: "self", Vout: 1, Address: "own", Label: "savings", Category: "send", AmountSats: -50_000_000, Confirmations: 1},
					{Txid: "incoming", Vout: 0, Address: "first", Category: "receive", AmountSats: 10_000_000, Confirmations: 1},
					{Txid: "incoming", Vout: 1, Address: "second", Category: "receive", AmountSats: 20_000_000, Confirmations: 1},
				},
			}, nil)
		apitests.ExpectOrchestratorReads(mockOrch)
		cli := walletv1connect.NewWalletServiceClient(apitests.RPC(t, db, apitests.WithOrchestrator(mockOrch)))

		resp, err := cli.ListTransactions(t.Context(), &walletv1.ListTransactionsRequest{WalletId: testWalletID})
		require.NoError(t, err)
		byTxid := lo.KeyBy(resp.Transactions, func(tx *walletv1.WalletTransaction) string { return tx.Txid })

		require.Equal(t, "large", byTxid["many"].Address)
		require.Equal(t, []payment{{"large", 200_000_000}, {"middle", 100_000_000}, {"small", 50_000}}, paymentsOf(byTxid["many"]))

		require.Equal(t, "shop", byTxid["mixed"].Address)
		require.Empty(t, byTxid["mixed"].AddressLabel)
		require.Equal(t, []payment{{"shop", 10_000}}, paymentsOf(byTxid["mixed"]))

		require.Equal(t, "own", byTxid["self"].Address)
		require.Equal(t, "savings", byTxid["self"].AddressLabel)
		require.Equal(t, []payment{{"own", 50_000_000}}, paymentsOf(byTxid["self"]))

		require.Equal(t, []payment{{"second", 20_000_000}, {"first", 10_000_000}}, paymentsOf(byTxid["incoming"]))
	})

	t.Run("core rows name each payment of a transaction", func(t *testing.T) {
		t.Parallel()

		db := database.Test(t)
		send := func(address string, vout uint32, amount float64) *corepb.GetTransactionResponse {
			return &corepb.GetTransactionResponse{
				Txid: "many", Amount: amount, Fee: -0.00000406, Confirmations: 1,
				Details: []*corepb.GetTransactionResponse_Details{{
					Address: address, Vout: vout, Amount: amount, Category: corepb.GetTransactionResponse_CATEGORY_SEND,
				}},
			}
		}
		mockBitcoind := mocks.NewMockBitcoinServiceClient(gomock.NewController(t))
		mockBitcoind.EXPECT().
			ListTransactions(gomock.Any(), gomock.Any()).
			Return(connectv1.NewResponse(&corepb.ListTransactionsResponse{
				Transactions: []*corepb.GetTransactionResponse{send("small", 3, -0.0005), send("large", 1, -2)},
			}), nil)
		mockBitcoind.EXPECT().
			GetBlockchainInfo(gomock.Any(), gomock.Any()).
			Return(connectv1.NewResponse(&corepb.GetBlockchainInfoResponse{Blocks: 102}), nil)
		apitests.ExpectCoreWalletSetup(mockBitcoind)
		cli := walletv1connect.NewWalletServiceClient(apitests.RPC(t, db, apitests.WithCoreWallet(), apitests.WithBitcoind(mockBitcoind)))

		resp, err := cli.ListTransactions(t.Context(), &walletv1.ListTransactionsRequest{WalletId: testWalletID})
		require.NoError(t, err)
		require.Len(t, resp.Transactions, 1)
		require.Equal(t, "large", resp.Transactions[0].Address)
		require.Equal(t, []payment{{"large", 200_000_000}, {"small", 50_000}}, paymentsOf(resp.Transactions[0]))
		require.Equal(t, uint64(406), resp.Transactions[0].FeeSats)
	})
}
