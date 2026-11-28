package api

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"connectrpc.com/connect/v2"
	"github.com/rs/zerolog"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	pb "github.com/LayerTwo-Labs/sidesail/sidechain-orchestrator/gen/walletmanager/v1"
	"github.com/LayerTwo-Labs/sidesail/sidechain-orchestrator/wallet"
)

func TestUpdateWalletMetadataCodes(t *testing.T) {
	dir := t.TempDir()
	svc := wallet.NewService(dir, zerolog.New(zerolog.NewTestWriter(t)))
	require.NoError(t, svc.Init())
	t.Cleanup(func() { svc.Close() })
	w, err := svc.GenerateWallet("Alpha", "", "", nil)
	require.NoError(t, err)
	h := NewWalletHandler(svc)
	ctx := context.Background()

	_, err = h.UpdateWalletMetadata(ctx, &pb.UpdateWalletMetadataRequest{WalletId: "missing", Name: "x"})
	assert.Equal(t, connect.CodeNotFound, connect.CodeOf(err))

	require.NoError(t, os.Mkdir(filepath.Join(dir, "wallet.json.prev.tmp"), 0o700))
	_, err = h.UpdateWalletMetadata(ctx, &pb.UpdateWalletMetadataRequest{WalletId: w.ID, Name: "Beta"})
	require.Error(t, err)
	assert.Equal(t, connect.CodeInternal, connect.CodeOf(err))
}
