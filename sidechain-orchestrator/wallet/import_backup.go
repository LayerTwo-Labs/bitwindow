package wallet

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
)

var (
	// ErrBackupPasswordRequired reports a backup that opens only with a password.
	ErrBackupPasswordRequired = errors.New("the backup needs a password")
	// ErrBackupHasNoNewWallet reports a backup whose wallets are all here already.
	ErrBackupHasNoNewWallet = errors.New("every wallet of the backup is here already")
)

// ImportWalletBackup adds the wallets of a backup wallet file to the wallets of
// this install and returns the IDs of the added wallets. A wallet whose ID is
// here already stays as it is. The first added wallet becomes the active one.
// encryptionJSON and password open a backup that has a password.
func (s *Service) ImportWalletBackup(walletJSON, encryptionJSON []byte, password string) ([]string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if s.locked() {
		return nil, fmt.Errorf("wallet is locked, unlock before restoring a backup")
	}

	backup, err := s.readBackupWalletFile(walletJSON, encryptionJSON, password)
	if err != nil {
		return nil, err
	}
	if len(backup.Wallets) == 0 {
		return nil, errors.New("the backup holds no wallet")
	}

	before := s.wallets
	beforeActive, beforeStarter := s.activeWalletID, s.starterWalletID
	wallets := append([]WalletData(nil), s.wallets...)
	var added []string
	for _, w := range backup.Wallets {
		if w.ID == "" || containsWalletID(wallets, w.ID) {
			continue
		}
		w.Name = freeWalletName(w.Name, wallets)
		wallets = append(wallets, w)
		added = append(added, w.ID)
	}
	if len(added) == 0 {
		return nil, ErrBackupHasNoNewWallet
	}

	s.wallets = wallets
	s.activeWalletID = added[0]
	_, err = s.normalizeWallets()
	if err == nil {
		err = s.saveWalletFile()
	}
	if err != nil {
		s.wallets, s.activeWalletID, s.starterWalletID = before, beforeActive, beforeStarter
		return nil, fmt.Errorf("add the wallets of the backup: %w", err)
	}
	s.log.Info().Int("added", len(added)).Int("in_backup", len(backup.Wallets)).Msg("added the wallets of a backup")
	return added, nil
}

// readBackupWalletFile decodes the wallet file of a backup. A backup with no
// encryption metadata of its own opens with the key of this install. Must be
// called with mu held.
func (s *Service) readBackupWalletFile(walletJSON, encryptionJSON []byte, password string) (*WalletFile, error) {
	plain := string(walletJSON)
	if !isPlaintextWalletFile(walletJSON) {
		key := s.encryptionKey
		if len(encryptionJSON) > 0 {
			if password == "" {
				return nil, ErrBackupPasswordRequired
			}
			meta, err := UnmarshalEncryptionMetadata(encryptionJSON)
			if err != nil {
				return nil, fmt.Errorf("read the encryption metadata of the backup: %w", err)
			}
			salt, err := base64.StdEncoding.DecodeString(meta.Salt)
			if err != nil {
				return nil, fmt.Errorf("decode the salt of the backup: %w", err)
			}
			key = DeriveKey(password, salt, meta.Iterations)
		}
		if key == nil {
			return nil, errors.New("the backup is not a wallet file")
		}
		decrypted, err := Decrypt(plain, key)
		if err != nil {
			if len(encryptionJSON) > 0 {
				return nil, ErrIncorrectPassword
			}
			return nil, errors.New("the backup is not a wallet file")
		}
		plain = decrypted
	}

	var wf WalletFile
	if err := json.Unmarshal([]byte(plain), &wf); err != nil {
		return nil, fmt.Errorf("parse the wallet file of the backup: %w", err)
	}
	return &wf, nil
}

func containsWalletID(wallets []WalletData, id string) bool {
	for i := range wallets {
		if wallets[i].ID == id {
			return true
		}
	}
	return false
}

// freeWalletName returns name, or the first free "walletN" when another wallet
// has that name.
func freeWalletName(name string, wallets []WalletData) string {
	taken := func(candidate string) bool {
		for i := range wallets {
			if strings.EqualFold(strings.TrimSpace(wallets[i].Name), strings.TrimSpace(candidate)) {
				return true
			}
		}
		return false
	}
	if strings.TrimSpace(name) != "" && !taken(name) {
		return name
	}
	for i := 1; ; i++ {
		candidate := fmt.Sprintf("wallet%d", i)
		if !taken(candidate) {
			return candidate
		}
	}
}
