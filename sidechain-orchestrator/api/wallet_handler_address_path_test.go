package api

import (
	"context"
	"testing"

	"connectrpc.com/connect/v2"
	"github.com/btcsuite/btcd/chaincfg"
	"github.com/rs/zerolog"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	pb "github.com/LayerTwo-Labs/sidesail/sidechain-orchestrator/gen/walletmanager/v1"
	"github.com/LayerTwo-Labs/sidesail/sidechain-orchestrator/wallet"
)

type addressPathBackend struct {
	wallet.Backend
	paths map[string]string
}

func (b *addressPathBackend) AddressHDPath(_ context.Context, _, address string) (string, error) {
	return b.paths[address], nil
}

func TestGetAddressDerivationPath(t *testing.T) {
	log := zerolog.New(zerolog.NewTestWriter(t))
	svc := wallet.NewService(t.TempDir(), log)
	svc.SetNetwork("regtest")
	require.NoError(t, svc.Init())
	t.Cleanup(func() { svc.Close() })
	w, err := svc.GenerateWallet("Core", "", "", nil)
	require.NoError(t, err)

	backend := &addressPathBackend{paths: map[string]string{"far": "m/84h/1h/0h/0/106"}}
	h := NewWalletHandler(svc)
	h.SetEngine(wallet.NewWalletEngine(svc, wallet.NewBackendRouter(svc, backend, nil), wallet.StaticParams(&chaincfg.RegressionNetParams), log))
	ctx := context.Background()

	resp, err := h.GetAddressDerivationPath(ctx, &pb.GetAddressDerivationPathRequest{WalletId: w.ID, Address: " far "})
	require.NoError(t, err)
	assert.Equal(t, "m/84h/1h/0h/0/106", resp.DerivationPath)

	_, err = h.GetAddressDerivationPath(ctx, &pb.GetAddressDerivationPathRequest{WalletId: w.ID, Address: "stranger"})
	assert.Equal(t, connect.CodeNotFound, connect.CodeOf(err))
	assert.Contains(t, err.Error(), "the wallet holds no key for address stranger")

	_, err = h.GetAddressDerivationPath(ctx, &pb.GetAddressDerivationPathRequest{WalletId: w.ID, Address: " "})
	assert.Equal(t, connect.CodeInvalidArgument, connect.CodeOf(err))
}
