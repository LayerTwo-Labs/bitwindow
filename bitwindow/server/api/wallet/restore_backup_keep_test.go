package wallet_test

import (
	"context"
	"testing"

	"connectrpc.com/connect/v2"
	"github.com/stretchr/testify/require"
	"go.uber.org/mock/gomock"

	"github.com/LayerTwo-Labs/sidesail/bitwindow/server/database"
	walletv1 "github.com/LayerTwo-Labs/sidesail/bitwindow/server/gen/wallet/v1"
	walletv1connect "github.com/LayerTwo-Labs/sidesail/bitwindow/server/gen/wallet/v1/walletv1connect"
	"github.com/LayerTwo-Labs/sidesail/bitwindow/server/tests/apitests"
	"github.com/LayerTwo-Labs/sidesail/bitwindow/server/tests/mocks"
	orchpb "github.com/LayerTwo-Labs/sidesail/sidechain-orchestrator/gen/walletmanager/v1"
)

const backupWalletFile = `{"version":1,"wallets":[{"id":"backup","master":{},"l1":{}}]}`

// The test server has no L1 stack to restart, so a restore that replaces the
// wallets fails here. A restore that keeps them must not restart it.
func TestRestoreBackupThatKeepsWalletsHandsTheWalletFileToTheOrchestrator(t *testing.T) {
	orch := mocks.NewMockWalletManagerServiceClient(gomock.NewController(t))
	apitests.ExpectOrchestratorReads(orch)
	var got *orchpb.ImportWalletBackupRequest
	orch.EXPECT().ImportWalletBackup(gomock.Any(), gomock.Any()).DoAndReturn(
		func(_ context.Context, req *orchpb.ImportWalletBackupRequest) (*orchpb.ImportWalletBackupResponse, error) {
			got = req
			return &orchpb.ImportWalletBackupResponse{WalletIds: []string{"backup"}}, nil
		},
	).Times(1)
	cli := walletv1connect.NewWalletServiceClient(apitests.RPC(t, database.Test(t), apitests.WithOrchestrator(orch)))

	_, err := cli.RestoreBackup(t.Context(), &walletv1.RestoreBackupRequest{
		BackupData:  []byte(backupWalletFile),
		Filename:    "wallet.json",
		KeepWallets: true,
		Password:    "backup horse",
	})

	require.NoError(t, err)
	require.Equal(t, backupWalletFile, string(got.WalletJson))
	require.Equal(t, "backup horse", got.Password)
}

func TestRestoreBackupThatKeepsWalletsReturnsTheOrchestratorError(t *testing.T) {
	orch := mocks.NewMockWalletManagerServiceClient(gomock.NewController(t))
	apitests.ExpectOrchestratorReads(orch)
	orch.EXPECT().ImportWalletBackup(gomock.Any(), gomock.Any()).Return(
		nil, connect.NewError(connect.CodeUnauthenticated, "incorrect password"),
	).Times(1)
	cli := walletv1connect.NewWalletServiceClient(apitests.RPC(t, database.Test(t), apitests.WithOrchestrator(orch)))

	_, err := cli.RestoreBackup(t.Context(), &walletv1.RestoreBackupRequest{
		BackupData:  []byte(backupWalletFile),
		Filename:    "wallet.json",
		KeepWallets: true,
		Password:    "wrong horse",
	})

	require.Equal(t, connect.CodeUnauthenticated, connect.CodeOf(err))
	require.ErrorContains(t, err, "incorrect password")
}
