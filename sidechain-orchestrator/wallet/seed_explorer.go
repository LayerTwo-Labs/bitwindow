package wallet

import (
	"encoding/hex"
	"errors"
	"fmt"
	"strconv"
	"strings"

	"github.com/btcsuite/btcd/btcutil"
	"github.com/btcsuite/btcd/btcutil/hdkeychain"
	"github.com/btcsuite/btcd/chaincfg"
)

// MaxExploredKeys caps the keys that one ExploreSeed call derives.
const MaxExploredKeys = 100

// ErrNoSingleSeed is the error for a watch-only, multisig or electrum wallet.
var ErrNoSingleSeed = errors.New("holds no single seed to explore")

// ExploredKey is one child key of a seed, for display.
type ExploredKey struct {
	Path      string
	Address   string
	PublicKey string // compressed, hex
	WIF       string // compressed
}

// SeedExplorer holds the master keys of a seed and one page of child keys.
type SeedExplorer struct {
	SeedHex     string
	Xprv        string
	Xpub        string
	PaymentCode string // BIP47 v1, as the wallet gives it
	BasePath    string // canonical parent path of Keys
	// WatchDescriptor is the watch-only descriptor of the account of BasePath.
	// It is empty when BasePath is not a receive or change chain.
	WatchDescriptor string
	// WalletReceiveChain is true when Keys are on the receive chain of the
	// explored wallet, so the wallet lists what each address received.
	WalletReceiveChain bool
	Keys               []ExploredKey
}

// ExploreSeed derives the master keys of a mnemonic and the keys at
// basePath/start to basePath/start+count-1. The purpose level of basePath
// picks the address: 49 nested segwit, 84 segwit, 86 taproot, others P2PKH.
func ExploreSeed(mnemonic, passphrase, basePath string, start, count uint32, net *chaincfg.Params) (SeedExplorer, error) {
	normal, err := ParseMnemonic(mnemonic)
	if err != nil {
		return SeedExplorer{}, err
	}
	return exploreSeedBytes(MnemonicToSeed(normal, passphrase), nil, basePath, start, count, net)
}

// ExploreWallet explores the seed of w, passphrase included. An empty basePath
// takes the receive chain of the default address type of w.
func ExploreWallet(w *WalletData, basePath string, start, count uint32, net *chaincfg.Params) (SeedExplorer, error) {
	if w.Multisig != nil || w.Master.SeedHex == "" {
		return SeedExplorer{}, fmt.Errorf("wallet %s %w", w.ID, ErrNoSingleSeed)
	}
	seed, err := hex.DecodeString(w.Master.SeedHex)
	if err != nil {
		return SeedExplorer{}, fmt.Errorf("decode seed of wallet %s: %w", w.ID, err)
	}
	return exploreSeedBytes(seed, w, basePath, start, count, net)
}

func exploreSeedBytes(seed []byte, w *WalletData, basePath string, start, count uint32, net *chaincfg.Params) (SeedExplorer, error) {
	if net == nil {
		return SeedExplorer{}, errors.New("no chain params")
	}
	if count > MaxExploredKeys {
		return SeedExplorer{}, fmt.Errorf("count %d is above the limit of %d", count, MaxExploredKeys)
	}
	if uint64(start)+uint64(count) > hdkeychain.HardenedKeyStart {
		return SeedExplorer{}, fmt.Errorf("index %d+%d is out of the non-hardened range", start, count)
	}
	var walletAccount string
	if w != nil {
		account, err := accountPathFor(w, w.scriptKind(), net)
		if err != nil {
			return SeedExplorer{}, err
		}
		walletAccount = account.String()
		if strings.TrimSpace(basePath) == "" {
			basePath = walletAccount + "/0"
		}
	}
	path, err := ParseAccountPath(basePath)
	if err != nil {
		return SeedExplorer{}, err
	}
	base := path.String()
	levels := path.Indices()
	kind, ok := purposeToCoreKind(levels[0] &^ hdkeychain.HardenedKeyStart)
	if !ok {
		kind = ScriptLegacy
	}
	if w != nil && (base == walletAccount+"/0" || base == walletAccount+"/1") {
		kind = w.scriptKind()
	}

	master, err := hdkeychain.NewMaster(seed, net)
	if err != nil {
		return SeedExplorer{}, fmt.Errorf("create master key: %w", err)
	}
	masterPub, err := master.Neuter()
	if err != nil {
		return SeedExplorer{}, fmt.Errorf("neuter master key: %w", err)
	}
	seedHex := hex.EncodeToString(seed)
	paymentCode, err := Bip47PaymentCodeFromSeed(seedHex, net)
	if err != nil {
		return SeedExplorer{}, err
	}

	parent := master
	account := master
	for _, level := range levels {
		account = parent
		parent, err = parent.Derive(level)
		if err != nil {
			return SeedExplorer{}, fmt.Errorf("derive %s: %w", base, err)
		}
	}
	watchDescriptor, err := accountWatchDescriptor(account, path, kind, seedHex, net)
	if err != nil {
		return SeedExplorer{}, err
	}

	keys := make([]ExploredKey, 0, count)
	for i := start; i < start+count; i++ {
		key, err := exploreChild(parent, i, kind, net)
		if err != nil {
			return SeedExplorer{}, fmt.Errorf("derive %s/%d: %w", base, i, err)
		}
		key.Path = base + "/" + strconv.FormatUint(uint64(i), 10)
		keys = append(keys, key)
	}

	return SeedExplorer{
		SeedHex:            seedHex,
		Xprv:               master.String(),
		Xpub:               masterPub.String(),
		PaymentCode:        paymentCode,
		BasePath:           base,
		WatchDescriptor:    watchDescriptor,
		WalletReceiveChain: w != nil && base == walletAccount+"/0",
		Keys:               keys,
	}, nil
}

// accountWatchDescriptor gives the watch-only descriptor of account, the parent
// key of the chain that chainPath ends with. It is empty unless that chain is
// the receive chain or the change chain of an account.
func accountWatchDescriptor(account *hdkeychain.ExtendedKey, chainPath AccountPath, kind ScriptKind, seedHex string, net *chaincfg.Params) (string, error) {
	steps := chainPath.steps()
	chain := steps[len(steps)-1]
	if len(steps) < 2 || chain.Hardened || chain.Index > 1 {
		return "", nil
	}
	accountPub, err := account.Neuter()
	if err != nil {
		return "", fmt.Errorf("neuter account key: %w", err)
	}
	fingerprint, err := seedMasterFingerprint(seedHex, net)
	if err != nil {
		return "", fmt.Errorf("master fingerprint: %w", err)
	}
	origin := AccountPath{Steps: steps[:len(steps)-1]}.Origin("'")
	return singleSigWatchDescriptor(kind, fingerprint, origin, accountPub.String())
}

func exploreChild(parent *hdkeychain.ExtendedKey, index uint32, kind ScriptKind, net *chaincfg.Params) (ExploredKey, error) {
	child, err := parent.Derive(index)
	if err != nil {
		return ExploredKey{}, err
	}
	priv, err := child.ECPrivKey()
	if err != nil {
		return ExploredKey{}, err
	}
	pub := priv.PubKey()
	output, err := singleSigOutput(kind, pub, net)
	if err != nil {
		return ExploredKey{}, err
	}
	wif, err := btcutil.NewWIF(priv, net, true)
	if err != nil {
		return ExploredKey{}, err
	}
	return ExploredKey{
		Address:   output.address.EncodeAddress(),
		PublicKey: hex.EncodeToString(pub.SerializeCompressed()),
		WIF:       wif.String(),
	}, nil
}
