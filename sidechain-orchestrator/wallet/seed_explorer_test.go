package wallet

import (
	"encoding/hex"
	"testing"

	"github.com/btcsuite/btcd/chaincfg"
	"github.com/stretchr/testify/require"

	"github.com/LayerTwo-Labs/sidesail/sidechain-orchestrator/wallet/bip47"
)

// Values that the Dart HD Explorer gave for the same seed. The mainnet rows are the BIP44, 49, 84 and 86 vectors.
func TestExploreSeedMatchesFrontend(t *testing.T) {
	out, err := ExploreSeed(testMnemonic, "", "m/84'/0'/0'/0", 0, 1, &chaincfg.MainNetParams)
	require.NoError(t, err)
	require.Equal(t, "5eb00bbddcf069084889a8ab9155568165f5c453ccb85e70811aaed6f6da5fc19a5ac40b389cd370d086206dec8aa6c43daea6690f20ad3d8d48b2d2ce9e38e4", out.SeedHex)
	require.Equal(t, "xprv9s21ZrQH143K3GJpoapnV8SFfukcVBSfeCficPSGfubmSFDxo1kuHnLisriDvSnRRuL2Qrg5ggqHKNVpxR86QEC8w35uxmGoggxtQTPvfUu", out.Xprv)
	require.Equal(t, "xpub661MyMwAqRbcFkPHucMnrGNzDwb6teAX1RbKQmqtEF8kK3Z7LZ59qafCjB9eCRLiTVG3uxBxgKvRgbubRhqSKXnGGb1aoaqLrpMBDrVxga8", out.Xpub)
	require.Equal(t, "PM8TJdJWQ5c9XJUMuNBBaJ7Zq9GnjfYtQk7PJn9n4jt8qdgRFBB9TUkAGGd4mK1VRLekUt3ifC9aGVRLYYmLb9WhsvsUrFin1FUBzEoyPxBnmVExHAjE", out.PaymentCode)
	require.Equal(t, "m/84'/0'/0'/0", out.BasePath)

	cases := []struct {
		base string
		net  *chaincfg.Params
		keys []ExploredKey
	}{
		{"m/44'/0'/0'/0", &chaincfg.MainNetParams, []ExploredKey{
			{Path: "m/44'/0'/0'/0/0", Address: "1LqBGSKuX5yYUonjxT5qGfpUsXKYYWeabA", PublicKey: "03aaeb52dd7494c361049de67cc680e83ebcbbbdbeb13637d92cd845f70308af5e", WIF: "L4p2b9VAf8k5aUahF1JCJUzZkgNEAqLfq8DDdQiyAprQAKSbu8hf"},
			{Path: "m/44'/0'/0'/0/1", Address: "1Ak8PffB2meyfYnbXZR9EGfLfFZVpzJvQP", PublicKey: "02dfcaec532010d704860e20ad6aff8cf3477164ffb02f93d45c552dadc70ed24f", WIF: "KzJgGiEeGUVWmPR97pVWDnCVraZvM2fnrCVrg2irV4353HciE6Un"},
		}},
		{"m/49'/0'/0'/0", &chaincfg.MainNetParams, []ExploredKey{
			{Path: "m/49'/0'/0'/0/0", Address: "37VucYSaXLCAsxYyAPfbSi9eh4iEcbShgf", PublicKey: "039b3b694b8fc5b5e07fb069c783cac754f5d38c3e08bed1960e31fdb1dda35c24", WIF: "KyvHbRLNXfXaHuZb3QRaeqA5wovkjg4RuUpFGCxdH5UWc1Foih9o"},
			{Path: "m/49'/0'/0'/0/1", Address: "3LtMnn87fqUeHBUG414p9CWwnoV6E2pNKS", PublicKey: "022a421fa4a65a87d1c3e4238155d85f7bd2c5bb87632f331b5722f110586aa198", WIF: "KyaMvgopkPDQMQUx2w9a8AiEtA7A84hYzASJWGQiKZ8AJUEj77iV"},
		}},
		{"m/84'/0'/0'/0", &chaincfg.MainNetParams, []ExploredKey{
			{Path: "m/84'/0'/0'/0/0", Address: "bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu", PublicKey: "0330d54fd0dd420a6e5f8d3624f5f3482cae350f79d5f0753bf5beef9c2d91af3c", WIF: "KyZpNDKnfs94vbrwhJneDi77V6jF64PWPF8x5cdJb8ifgg2DUc9d"},
			{Path: "m/84'/0'/0'/0/1", Address: "bc1qnjg0jd8228aq7egyzacy8cys3knf9xvrerkf9g", PublicKey: "03e775fd51f0dfb8cd865d9ff1cca2a158cf651fe997fdc9fee9c1d3b5e995ea77", WIF: "Kxpf5b8p3qX56DKEe5NqWbNUP9MnqoRFzZwHRtsFqhzuvUJsYZCy"},
		}},
		{"m/86'/0'/0'/0", &chaincfg.MainNetParams, []ExploredKey{
			{Path: "m/86'/0'/0'/0/0", Address: "bc1p5cyxnuxmeuwuvkwfem96lqzszd02n6xdcjrs20cac6yqjjwudpxqkedrcr", PublicKey: "03cc8a4bc64d897bddc5fbc2f670f7a8ba0b386779106cf1223c6fc5d7cd6fc115", WIF: "KyRv5iFPHG7iB5E4CqvMzH3WFJVhbfYK4VY7XAedd9Ys69mEsPLQ"},
			{Path: "m/86'/0'/0'/0/1", Address: "bc1p4qhjn9zdvkux4e44uhx8tc55attvtyu358kutcqkudyccelu0was9fqzwh", PublicKey: "0283dfe85a3151d2517290da461fe2815591ef69f2b18a2ce63f01697a8b313145", WIF: "L1jhNnZZAAAppoSYQuaAQEj935VpmishMomuWXgJ3Qy5HNqkhhus"},
		}},
		{"m/84'/1'/0'/1", &chaincfg.SigNetParams, []ExploredKey{
			{Path: "m/84'/1'/0'/1/0", Address: "tb1q9u62588spffmq4dzjxsr5l297znf3z6j5p2688", PublicKey: "035d49eccd54d0099e43676277c7a6d4625d611da88a5df49bf9517a7791a777a5", WIF: "cQ5TcujvBuw5bZfEVJmXZw5Ac1mQ6ryAjHeDrJcmn6oDyhfva5by"},
			{Path: "m/84'/1'/0'/1/1", Address: "tb1qkwgskuzmmwwvqajnyr7yp9hgvh5y45kg8wvdmd", PublicKey: "03f37f9607be4661510885f4f960954dadfc0af91ea722fe2935ca39c1e54c2948", WIF: "cVg4cGUL42Kf2XVPC5Uqa7ggsqqWHsKjnZgU6f7nARFoYCVxzh2Y"},
		}},
		{"m/0'/5", &chaincfg.RegressionNetParams, []ExploredKey{
			{Path: "m/0'/5/0", Address: "mtQdnjWTUrXyyvyoJ5D8NHpnnECAGS4yeq", PublicKey: "02298ea8b212b03c5bbc175ef4ed5756ebfe52d3425ee541a2852808d04cf2ca76", WIF: "cRKT73EjMZx28m5YThCXg7jUj8PKrrd52XP8ZfVC2sNrLNbiUgPF"},
			{Path: "m/0'/5/1", Address: "mtaAQzC2L35JWvRLmsu2jCNxLyzF4BufZh", PublicKey: "03efa7212cf6e3923830e27ad9d79d05ddab0e9a1568b5c378b0e32e728b1ae601", WIF: "cQjx3p49Kvv8Zgso6H788DxcjjxLFDJD2zaAP61uQt96PSmLcB63"},
		}},
	}
	for _, c := range cases {
		got, err := ExploreSeed(testMnemonic, "", c.base, 0, 2, c.net)
		require.NoError(t, err, c.base)
		require.Equal(t, c.keys, got.Keys, c.base)
	}
}

func TestExploreSeedPage(t *testing.T) {
	all, err := ExploreSeed(testMnemonic, "", "84h/0h/0h/0", 0, 12, &chaincfg.MainNetParams)
	require.NoError(t, err)
	page, err := ExploreSeed(testMnemonic, "", "m/84'/0'/0'/0", 10, 2, &chaincfg.MainNetParams)
	require.NoError(t, err)
	require.Equal(t, all.Keys[10:], page.Keys)
	require.Equal(t, "m/84'/0'/0'/0/10", page.Keys[0].Path)
}

func TestExploreSeedPassphraseChangesTheSeed(t *testing.T) {
	plain, err := ExploreSeed(testMnemonic, "", "m/84'/0'/0'/0", 0, 1, &chaincfg.MainNetParams)
	require.NoError(t, err)
	salted, err := ExploreSeed(testMnemonic, "TREZOR", "m/84'/0'/0'/0", 0, 1, &chaincfg.MainNetParams)
	require.NoError(t, err)
	require.NotEqual(t, plain.SeedHex, salted.SeedHex)
	require.NotEqual(t, plain.Keys, salted.Keys)
}

func TestExploreSeedRefusesBadInput(t *testing.T) {
	net := &chaincfg.MainNetParams
	_, err := ExploreSeed("abandon abandon", "", "m/84'/0'/0'/0", 0, 1, net)
	require.ErrorContains(t, err, "invalid mnemonic")
	_, err = ExploreSeed(testMnemonic, "", "m/84'/x'/0'", 0, 1, net)
	require.ErrorContains(t, err, "not a number")
	_, err = ExploreSeed(testMnemonic, "", "m/84'/0'/0'/0", 0, MaxExploredKeys+1, net)
	require.ErrorContains(t, err, "above the limit")
	_, err = ExploreSeed(testMnemonic, "", "m/84'/0'/0'/0", 1<<31-1, 2, net)
	require.ErrorContains(t, err, "non-hardened range")
	_, err = ExploreSeed(testMnemonic, "", "m/84'/0'/0'/0", 0, 1, nil)
	require.ErrorContains(t, err, "no chain params")
}

func TestExploreSeedGivesTheWalletPaymentCode(t *testing.T) {
	net := &chaincfg.RegressionNetParams
	out, err := ExploreSeed(testMnemonic, "", "m/84'/1'/0'/0", 0, 1, net)
	require.NoError(t, err)
	want, err := Bip47PaymentCodeFromSeed(out.SeedHex, net)
	require.NoError(t, err)
	require.Equal(t, want, out.PaymentCode)
	_, err = bip47.ParsePaymentCode(out.PaymentCode)
	require.NoError(t, err)
}

func explorerTestWallet(passphrase string, account uint32) *WalletData {
	return &WalletData{
		ID:           "explored",
		WalletType:   WalletTypeBitcoinCore,
		Master:       MasterWallet{Mnemonic: testMnemonic, SeedHex: hex.EncodeToString(MnemonicToSeed(testMnemonic, passphrase))},
		AccountIndex: account,
	}
}

func walletReceiveAddress(t *testing.T, w *WalletData, net *chaincfg.Params, index uint32) string {
	t.Helper()
	d, err := DescriptorFor(w, ReceiveKinds(w)[0], net)
	require.NoError(t, err)
	ds, _, err := d.DeriveScript(false, index, net)
	require.NoError(t, err)
	return ds.address.EncodeAddress()
}

func TestExploreWalletGivesTheWalletAddresses(t *testing.T) {
	net := &chaincfg.RegressionNetParams
	for _, c := range []struct {
		name     string
		w        *WalletData
		basePath string
	}{
		{"standard", explorerTestWallet("", 0), "m/84'/1'/0'/0"},
		{"passphrase", explorerTestWallet("TREZOR", 0), "m/84'/1'/0'/0"},
		{"account 2", explorerTestWallet("", 2), "m/84'/1'/2'/0"},
	} {
		out, err := ExploreWallet(c.w, "", 3, 2, net)
		require.NoError(t, err, c.name)
		require.Equal(t, c.basePath, out.BasePath, c.name)
		require.Equal(t, c.w.Master.SeedHex, out.SeedHex, c.name)
		require.Equal(t, walletReceiveAddress(t, c.w, net, 3), out.Keys[0].Address, c.name)
		require.Equal(t, walletReceiveAddress(t, c.w, net, 4), out.Keys[1].Address, c.name)
		want, err := Bip47PaymentCodeFromSeed(c.w.Master.SeedHex, net)
		require.NoError(t, err)
		require.Equal(t, want, out.PaymentCode, c.name)
	}
}

func TestExploreWalletTakesAnOtherPath(t *testing.T) {
	net := &chaincfg.RegressionNetParams
	out, err := ExploreWallet(explorerTestWallet("", 0), "m/86'/1'/0'/1", 0, 1, net)
	require.NoError(t, err)
	require.Equal(t, "m/86'/1'/0'/1/0", out.Keys[0].Path)
	require.Regexp(t, "^bcrt1p", out.Keys[0].Address)
}

func TestExploreWalletRefusesAWalletWithNoSeed(t *testing.T) {
	net := &chaincfg.RegressionNetParams
	_, err := ExploreWallet(&WalletData{ID: "watch"}, "", 0, 1, net)
	require.ErrorContains(t, err, "holds no single seed")
	multisig := explorerTestWallet("", 0)
	multisig.Multisig = &MultisigWalletData{M: 1, N: 2}
	_, err = ExploreWallet(multisig, "", 0, 1, net)
	require.ErrorContains(t, err, "holds no single seed")
}

func TestExploreWalletUsesScriptTypeForCustomPath(t *testing.T) {
	net := &chaincfg.RegressionNetParams
	w := explorerTestWallet("", 0)
	w.DerivationPath = "m/7'/2'"
	w.ScriptType = "native-segwit"
	descriptor, err := DescriptorFor(w, ScriptNativeSegwit, net)
	require.NoError(t, err)

	for _, tc := range []struct {
		name   string
		path   string
		branch string
		change bool
	}{
		{name: "default", branch: "0"},
		{name: "receive", path: "M/7h/2H/0", branch: "0"},
		{name: "change", path: "m/7'/2'/1", branch: "1", change: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			out, err := ExploreWallet(w, tc.path, 10, 1, net)
			require.NoError(t, err)
			require.Len(t, out.Keys, 1)
			want, _, err := descriptor.DeriveScript(tc.change, 10, net)
			require.NoError(t, err)
			require.Equal(t, w.DerivationPath+"/"+tc.branch+"/10", out.Keys[0].Path)
			require.Equal(t, want.address.EncodeAddress(), out.Keys[0].Address)
		})
	}
}
