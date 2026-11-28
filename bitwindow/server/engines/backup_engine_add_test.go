package engines

import (
	"archive/zip"
	"bytes"
	"errors"
	"os"
	"path/filepath"
	"testing"

	"connectrpc.com/connect/v2"
	"github.com/stretchr/testify/require"

	"github.com/LayerTwo-Labs/sidesail/bitwindow/server/database"
	"github.com/LayerTwo-Labs/sidesail/bitwindow/server/models/multisig"
)

const (
	currentWalletFile = `{"version":1,"wallets":[{"id":"current","master":{},"l1":{}}]}`
	backupWalletFile  = `{"version":1,"wallets":[{"id":"backup","master":{},"l1":{}}]}`
)

func backupZIP(t *testing.T, files map[string]string) []byte {
	t.Helper()
	var buf bytes.Buffer
	archive := zip.NewWriter(&buf)
	for name, content := range files {
		require.NoError(t, addToZip(archive, name, []byte(content)))
	}
	require.NoError(t, archive.Close())
	return buf.Bytes()
}

func TestAddBackupKeepsTheWalletFile(t *testing.T) {
	dir := t.TempDir()
	db := database.Test(t)
	walletPath := filepath.Join(dir, "wallet.json")
	require.NoError(t, os.WriteFile(walletPath, []byte(currentWalletFile), 0600))
	engine := NewBackupEngine(db, dir, "")
	data := backupZIP(t, map[string]string{
		"wallet.json":            backupWalletFile,
		"wallet_encryption.json": `{"salt":"c2FsdA==","iterations":1,"encrypted":false,"version":"1"}`,
		"multisig/multisig.json": `{"groups":[{"id":"group","name":"from backup","n":2,"m":2}]}`,
	})

	var gotWallet, gotEncryption []byte
	err := engine.AddBackup(t.Context(), data, "backup.zip", func(walletJSON, encryptionJSON []byte) error {
		gotWallet, gotEncryption = walletJSON, encryptionJSON
		return nil
	})
	require.NoError(t, err)

	require.JSONEq(t, backupWalletFile, string(gotWallet))
	require.NotEmpty(t, gotEncryption)
	after, err := os.ReadFile(walletPath)
	require.NoError(t, err)
	require.Equal(t, currentWalletFile, string(after))
	_, err = os.Stat(filepath.Join(dir, "wallet_encryption.json"))
	require.True(t, os.IsNotExist(err))
	groups, err := multisig.NewStore(db).ListGroups(t.Context())
	require.NoError(t, err)
	require.Len(t, groups, 1)
	require.Equal(t, "from backup", groups[0].Name)
}

func TestAddBackupDropsTheRowsWhenTheWalletsDoNotGoIn(t *testing.T) {
	dir := t.TempDir()
	db := database.Test(t)
	require.NoError(t, os.WriteFile(filepath.Join(dir, "wallet.json"), []byte(currentWalletFile), 0600))
	engine := NewBackupEngine(db, dir, "")
	data := backupZIP(t, map[string]string{
		"wallet.json":            backupWalletFile,
		"multisig/multisig.json": `{"groups":[{"id":"group","name":"from backup","n":2,"m":2}]}`,
	})
	refused := errors.New("incorrect password")

	err := engine.AddBackup(t.Context(), data, "backup.zip", func(_, _ []byte) error { return refused })

	require.ErrorIs(t, err, refused)
	groups, err := multisig.NewStore(db).ListGroups(t.Context())
	require.NoError(t, err)
	require.Empty(t, groups)
}

func TestAddBackupTakesAWalletJSONFile(t *testing.T) {
	engine := NewBackupEngine(database.Test(t), t.TempDir(), "")

	var gotWallet, gotEncryption []byte
	err := engine.AddBackup(t.Context(), []byte(backupWalletFile), "wallet.json", func(walletJSON, encryptionJSON []byte) error {
		gotWallet, gotEncryption = walletJSON, encryptionJSON
		return nil
	})

	require.NoError(t, err)
	require.Equal(t, backupWalletFile, string(gotWallet))
	require.Nil(t, gotEncryption)
}

func TestAddBackupKeepsAGroupThatIsHere(t *testing.T) {
	dir := t.TempDir()
	db := database.Test(t)
	store := multisig.NewStore(db)
	current := multisig.Group{ID: "group", Name: "current", N: 2, M: 2, NextReceiveIndex: 10}
	require.NoError(t, store.SaveGroupAtomic(t.Context(), multisig.SaveGroupAtomicParams{Group: current}))
	engine := NewBackupEngine(db, dir, "")
	data := backupZIP(t, map[string]string{
		"wallet.json": backupWalletFile,
		"multisig/multisig.json": `{"groups":[
			{"id":"group","name":"old copy","n":2,"m":2,"next_receive_index":1},
			{"id":"other","name":"from backup","n":2,"m":2}]}`,
		"transactions.json": `[{"id":"tx-old","groupId":"group"},{"id":"tx-new","groupId":"other"}]`,
	})

	err := engine.AddBackup(t.Context(), data, "backup.zip", func(_, _ []byte) error { return nil })
	require.NoError(t, err)

	groups, err := store.ListGroups(t.Context())
	require.NoError(t, err)
	require.Len(t, groups, 2)
	byID := map[string]multisig.Group{groups[0].ID: groups[0], groups[1].ID: groups[1]}
	require.Equal(t, current, byID["group"])
	require.Equal(t, "from backup", byID["other"].Name)
	var txIDs []string
	rows, err := db.QueryContext(t.Context(), `SELECT id FROM multisig_transactions ORDER BY id`)
	require.NoError(t, err)
	defer rows.Close()
	for rows.Next() {
		var id string
		require.NoError(t, rows.Scan(&id))
		txIDs = append(txIDs, id)
	}
	require.NoError(t, rows.Err())
	require.Equal(t, []string{"tx-new"}, txIDs)
}

func TestAddBackupKeepsTheRecordsWhenEveryWalletIsHere(t *testing.T) {
	db := database.Test(t)
	engine := NewBackupEngine(db, t.TempDir(), "")
	data := backupZIP(t, map[string]string{
		"wallet.json":            backupWalletFile,
		"multisig/multisig.json": `{"groups":[{"id":"group","name":"from backup","n":2,"m":2}]}`,
	})
	here := connect.NewError(connect.CodeAlreadyExists, "every wallet of the backup is here already")

	err := engine.AddBackup(t.Context(), data, "backup.zip", func(_, _ []byte) error { return here })

	require.NoError(t, err)
	groups, err := multisig.NewStore(db).ListGroups(t.Context())
	require.NoError(t, err)
	require.Len(t, groups, 1)
}

func TestAddBackupRefusesAWalletFileWithNoNewWallet(t *testing.T) {
	engine := NewBackupEngine(database.Test(t), t.TempDir(), "")
	here := connect.NewError(connect.CodeAlreadyExists, "every wallet of the backup is here already")

	err := engine.AddBackup(t.Context(), []byte(backupWalletFile), "wallet.json", func(_, _ []byte) error { return here })

	require.Equal(t, connect.CodeAlreadyExists, connect.CodeOf(err))
}
