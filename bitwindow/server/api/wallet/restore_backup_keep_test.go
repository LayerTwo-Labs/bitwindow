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
	orchctlpb "github.com/LayerTwo-Labs/sidesail/sidechain-orchestrator/gen/orchestrator/v1"
	orchctlrpc "github.com/LayerTwo-Labs/sidesail/sidechain-orchestrator/gen/orchestrator/v1/orchestratorv1connect"
	orchpb "github.com/LayerTwo-Labs/sidesail/sidechain-orchestrator/gen/walletmanager/v1"
)

const backupWalletFile = `{"version":1,"wallets":[{"id":"backup","master":{},"l1":{}}]}`

type l1Restarts struct {
	orchctlrpc.UnimplementedOrchestratorServiceHandler
	count int
}

func (r *l1Restarts) RestartL1(context.Context, *orchctlpb.RestartL1Request) (*orchctlpb.RestartL1Response, error) {
	r.count++
	return &orchctlpb.RestartL1Response{}, nil
}

func TestRestoreBackupIntoAnInstallWithAWalletAddsTheWalletsOfTheBackup(t *testing.T) {
	orch := mocks.NewMockWalletManagerServiceClient(gomock.NewController(t))
	apitests.ExpectOrchestratorReads(orch)
	var got *orchpb.ImportWalletBackupRequest
	orch.EXPECT().ImportWalletBackup(gomock.Any(), gomock.Any()).DoAndReturn(
		func(_ context.Context, req *orchpb.ImportWalletBackupRequest) (*orchpb.ImportWalletBackupResponse, error) {
			got = req
			return &orchpb.ImportWalletBackupResponse{WalletIds: []string{"backup"}}, nil
		},
	).Times(1)
	restarts := &l1Restarts{}
	cli := walletv1connect.NewWalletServiceClient(apitests.RPC(t, database.Test(t),
		apitests.WithOrchestrator(orch), apitests.WithOrchestratorControl(restarts)))

	_, err := cli.RestoreBackup(t.Context(), &walletv1.RestoreBackupRequest{
		BackupData: []byte(backupWalletFile),
		Filename:   "wallet.json",
		Password:   "backup horse",
	})

	require.NoError(t, err)
	require.Equal(t, backupWalletFile, string(got.WalletJson))
	require.Equal(t, "backup horse", got.Password)
	require.Zero(t, restarts.count)
}

func TestRestoreBackupIntoAnEmptyInstallWritesTheWalletsAndRestartsL1(t *testing.T) {
	orch := mocks.NewMockWalletManagerServiceClient(gomock.NewController(t))
	orch.EXPECT().GetWalletStatus(gomock.Any(), gomock.Any()).
		Return(&orchpb.GetWalletStatusResponse{State: orchpb.WalletState_WALLET_STATE_NO_WALLET}, nil).AnyTimes()
	apitests.ExpectOrchestratorReads(orch)
	orch.EXPECT().ImportWalletBackup(gomock.Any(), gomock.Any()).Times(0)
	restarts := &l1Restarts{}
	cli := walletv1connect.NewWalletServiceClient(apitests.RPC(t, database.Test(t),
		apitests.WithOrchestrator(orch), apitests.WithOrchestratorControl(restarts)))

	_, err := cli.RestoreBackup(t.Context(), &walletv1.RestoreBackupRequest{
		BackupData: []byte(backupWalletFile),
		Filename:   "wallet.json",
	})

	require.NoError(t, err)
	require.Equal(t, 1, restarts.count)
}

func TestRestoreBackupIntoALockedInstallNeverReplacesTheWallets(t *testing.T) {
	orch := mocks.NewMockWalletManagerServiceClient(gomock.NewController(t))
	orch.EXPECT().GetWalletStatus(gomock.Any(), gomock.Any()).
		Return(&orchpb.GetWalletStatusResponse{State: orchpb.WalletState_WALLET_STATE_LOCKED, Encrypted: true}, nil).AnyTimes()
	orch.EXPECT().ListWallets(gomock.Any(), gomock.Any()).Return(&orchpb.ListWalletsResponse{}, nil).AnyTimes()
	apitests.ExpectOrchestratorReads(orch)
	orch.EXPECT().ImportWalletBackup(gomock.Any(), gomock.Any()).Return(
		nil, connect.NewError(connect.CodeFailedPrecondition, "wallet is locked, unlock before restoring a backup"),
	).Times(1)
	restarts := &l1Restarts{}
	cli := walletv1connect.NewWalletServiceClient(apitests.RPC(t, database.Test(t),
		apitests.WithOrchestrator(orch), apitests.WithOrchestratorControl(restarts)))

	_, err := cli.RestoreBackup(t.Context(), &walletv1.RestoreBackupRequest{
		BackupData: []byte(backupWalletFile),
		Filename:   "wallet.json",
	})

	require.Equal(t, connect.CodeFailedPrecondition, connect.CodeOf(err))
	require.Zero(t, restarts.count)
}

func TestRestoreBackupIntoAnInstallWithAWalletReturnsTheOrchestratorError(t *testing.T) {
	orch := mocks.NewMockWalletManagerServiceClient(gomock.NewController(t))
	apitests.ExpectOrchestratorReads(orch)
	orch.EXPECT().ImportWalletBackup(gomock.Any(), gomock.Any()).Return(
		nil, connect.NewError(connect.CodeUnauthenticated, "incorrect password"),
	).Times(1)
	cli := walletv1connect.NewWalletServiceClient(apitests.RPC(t, database.Test(t), apitests.WithOrchestrator(orch)))

	_, err := cli.RestoreBackup(t.Context(), &walletv1.RestoreBackupRequest{
		BackupData: []byte(backupWalletFile),
		Filename:   "wallet.json",
		Password:   "wrong horse",
	})

	require.Equal(t, connect.CodeUnauthenticated, connect.CodeOf(err))
	require.ErrorContains(t, err, "incorrect password")
}
