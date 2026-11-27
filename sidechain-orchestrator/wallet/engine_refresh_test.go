package wallet

import (
	"context"
	"sync/atomic"
	"testing"

	"github.com/btcsuite/btcd/chaincfg"
	"github.com/rs/zerolog"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestRefreshElectrumScanReadsOnlyElectrumWallets(t *testing.T) {
	svc := newTestService(t)
	core, err := svc.GenerateWallet("Core", "", "", nil)
	require.NoError(t, err)
	require.Equal(t, WalletTypeBitcoinCore, core.WalletType)
	electrum, err := svc.CreateElectrumWallet("Electrum", nil, nil, "", "", "", "", 0, "")
	require.NoError(t, err)

	esplora := &countingEsplora{ChainDataSource: newFakeEsplora()}
	log := zerolog.New(zerolog.NewTestWriter(t))
	eb := NewElectrumBackend(svc, esplora, StaticParams(&chaincfg.SigNetParams), log)
	engine := NewWalletEngine(svc, NewBackendRouter(svc, nil, eb), StaticParams(&chaincfg.SigNetParams), log)
	ctx := context.Background()

	require.NoError(t, engine.RefreshElectrumScan(ctx, core.ID))
	assert.Zero(t, atomic.LoadInt32(&esplora.statsCalls), "a Core wallet sends none of its addresses to Esplora")

	require.NoError(t, engine.RefreshElectrumScan(ctx, electrum.ID))
	assert.NotZero(t, atomic.LoadInt32(&esplora.statsCalls), "an electrum wallet scans over Esplora")

	assert.Error(t, engine.RefreshElectrumScan(ctx, "no-such-wallet"))
}
