package wallet

import (
	"os"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// backupOf makes a service with one wallet and returns its wallet file, its
// encryption metadata (nil with no password) and the ID of the wallet.
func backupOf(t *testing.T, name, password string) (walletJSON, encryptionJSON []byte, id string) {
	t.Helper()
	svc := newTestService(t)
	w, err := svc.GenerateWallet(name, "", "", testSlots)
	require.NoError(t, err)
	if password != "" {
		require.NoError(t, svc.EncryptWallet(password))
		encryptionJSON, err = os.ReadFile(svc.metadataFilePath())
		require.NoError(t, err)
	}
	walletJSON, err = os.ReadFile(svc.walletFilePath())
	require.NoError(t, err)
	return walletJSON, encryptionJSON, w.ID
}

func walletNames(svc *Service) []string {
	var names []string
	for _, w := range svc.ListWallets() {
		names = append(names, w.Name)
	}
	return names
}

func TestImportWalletBackupKeepsTheWalletsOfTheInstall(t *testing.T) {
	backup, _, backupID := backupOf(t, "old", "")

	svc := newTestService(t)
	first, err := svc.GenerateWallet("first", "", "", testSlots)
	require.NoError(t, err)
	_, err = svc.GenerateWallet("second", "", "", testSlots)
	require.NoError(t, err)

	added, err := svc.ImportWalletBackup(backup, nil, "")
	require.NoError(t, err)

	assert.Equal(t, []string{backupID}, added)
	assert.Equal(t, []string{"first", "second", "old"}, walletNames(svc))
	assert.Equal(t, backupID, svc.ActiveWalletID())
	assert.Equal(t, first.ID, svc.StarterWalletID())

	reloaded := NewService(svc.bitwindowDir, svc.log)
	require.NoError(t, reloaded.Init())
	t.Cleanup(reloaded.Close)
	assert.Equal(t, []string{"first", "second", "old"}, walletNames(reloaded))
}

func TestImportWalletBackupSkipsAWalletThatIsHere(t *testing.T) {
	svc := newTestService(t)
	_, err := svc.GenerateWallet("first", "", "", testSlots)
	require.NoError(t, err)
	own, err := os.ReadFile(svc.walletFilePath())
	require.NoError(t, err)

	_, err = svc.ImportWalletBackup(own, nil, "")

	require.ErrorIs(t, err, ErrBackupHasNoNewWallet)
	assert.Equal(t, []string{"first"}, walletNames(svc))
	after, err := os.ReadFile(svc.walletFilePath())
	require.NoError(t, err)
	assert.Equal(t, own, after)
}

func TestImportWalletBackupGivesAFreeNameToATakenName(t *testing.T) {
	backup, _, _ := backupOf(t, "wallet1", "")

	svc := newTestService(t)
	_, err := svc.GenerateWallet("Wallet1", "", "", testSlots)
	require.NoError(t, err)

	_, err = svc.ImportWalletBackup(backup, nil, "")
	require.NoError(t, err)

	assert.Equal(t, []string{"Wallet1", "wallet2"}, walletNames(svc))
}

func TestImportWalletBackupOpensABackupWithItsPassword(t *testing.T) {
	backup, encryption, backupID := backupOf(t, "old", "backup horse")

	svc := newTestService(t)
	_, err := svc.GenerateWallet("first", "", "", testSlots)
	require.NoError(t, err)
	require.NoError(t, svc.EncryptWallet("install horse"))
	before, err := os.ReadFile(svc.walletFilePath())
	require.NoError(t, err)

	_, err = svc.ImportWalletBackup(backup, encryption, "")
	require.ErrorIs(t, err, ErrBackupPasswordRequired)
	_, err = svc.ImportWalletBackup(backup, encryption, "wrong horse")
	require.ErrorIs(t, err, ErrIncorrectPassword)
	after, err := os.ReadFile(svc.walletFilePath())
	require.NoError(t, err)
	assert.Equal(t, before, after)

	added, err := svc.ImportWalletBackup(backup, encryption, "backup horse")
	require.NoError(t, err)
	assert.Equal(t, []string{backupID}, added)

	// The install keeps its own password.
	svc.LockWallet()
	require.ErrorIs(t, svc.UnlockWallet("backup horse"), ErrIncorrectPassword)
	require.NoError(t, svc.UnlockWallet("install horse"))
	assert.Equal(t, []string{"first", "old"}, walletNames(svc))
}

func TestImportWalletBackupRefusesWhileLocked(t *testing.T) {
	backup, _, _ := backupOf(t, "old", "")

	svc := newTestService(t)
	_, err := svc.GenerateWallet("first", "", "", testSlots)
	require.NoError(t, err)
	require.NoError(t, svc.EncryptWallet("install horse"))
	svc.LockWallet()

	_, err = svc.ImportWalletBackup(backup, nil, "")

	require.ErrorContains(t, err, "wallet is locked")
}
