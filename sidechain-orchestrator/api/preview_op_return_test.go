package api

import (
	"bytes"
	"context"
	"encoding/hex"
	"strings"
	"testing"

	"connectrpc.com/connect/v2"
	"github.com/btcsuite/btcd/chaincfg"
	"github.com/btcsuite/btcd/wire"
	"github.com/rs/zerolog"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	pb "github.com/LayerTwo-Labs/sidesail/sidechain-orchestrator/gen/walletmanager/v1"
	"github.com/LayerTwo-Labs/sidesail/sidechain-orchestrator/wallet"
)

// A preview of an OP_RETURN send with no rate shows the fee that the send pays.
func TestPreviewSendPricesAnOpReturn(t *testing.T) {
	log := zerolog.New(zerolog.NewTestWriter(t))
	svc := wallet.NewService(t.TempDir(), log)
	svc.SetNetwork("signet")
	require.NoError(t, svc.Init())
	t.Cleanup(func() { svc.Close() })

	w, err := svc.CreateElectrumWallet("E", nil, nil, "", "", "", "", 0, "")
	require.NoError(t, err)
	net := &chaincfg.SigNetParams
	addrs, err := wallet.DeriveBIP84Addresses(w.Master.SeedHex, net, 0, 1)
	require.NoError(t, err)

	chain := newBip47TestChain(t, addrs[0], 500_000, 5)
	eb := wallet.NewElectrumBackend(svc, chain, wallet.StaticParams(net), log)
	h := NewWalletHandler(svc)
	h.SetEngine(wallet.NewWalletEngine(svc, wallet.NewBackendRouter(svc, nil, eb), wallet.StaticParams(net), log))

	_, err = h.PreviewSend(context.Background(), &pb.PreviewSendRequest{WalletId: w.ID})
	require.Equal(t, connect.CodeInvalidArgument, connect.CodeOf(err))

	payload := strings.Repeat("ab", 120)
	preview, err := h.PreviewSend(context.Background(), &pb.PreviewSendRequest{WalletId: w.ID, OpReturnHex: payload})
	require.NoError(t, err)
	assert.Positive(t, preview.FeeSats)
	assert.Greater(t, preview.VsizeVbytes, int64(120), "the size counts the payload")
	assert.Empty(t, chain.broadcast)

	_, err = h.SendTransaction(context.Background(), &pb.SendTransactionRequest{WalletId: w.ID, OpReturnHex: payload})
	require.NoError(t, err)
	require.Len(t, chain.broadcast, 1)
	raw, err := hex.DecodeString(chain.broadcast[0])
	require.NoError(t, err)
	var tx wire.MsgTx
	require.NoError(t, tx.Deserialize(bytes.NewReader(raw)))
	paid := int64(500_000)
	for _, out := range tx.TxOut {
		paid -= out.Value
	}
	assert.Equal(t, preview.FeeSats, paid, "the send pays the fee the preview showed")
}
