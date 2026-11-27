package wallet

import (
	"bytes"
	"encoding/base64"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/btcsuite/btcd/btcec/v2"
	"github.com/btcsuite/btcd/btcutil"
	"github.com/btcsuite/btcd/btcutil/psbt"
	"github.com/btcsuite/btcd/chaincfg"
	"github.com/btcsuite/btcd/chaincfg/chainhash"
	"github.com/btcsuite/btcd/txscript"
	"github.com/btcsuite/btcd/wire"
	"github.com/stretchr/testify/require"
)

func readPSBTFixture(t *testing.T, name string) string {
	t.Helper()
	raw, err := os.ReadFile(filepath.Join("testdata", "psbt", name+".b64"))
	require.NoError(t, err)
	return strings.TrimSpace(string(raw))
}

// The fixtures are regtest PSBTs from Bitcoin Core 29. The unsigned sizes are
// the estimated_vsize of analyzepsbt. The signed sizes are the vsize, size and
// weight of decoderawtransaction after walletprocesspsbt and finalizepsbt.
func TestDecodeTransactionPSBTSizeMatchesCore(t *testing.T) {
	tests := []struct {
		name        string
		unsignedVsz int32
		signedVsz   int32
		signedSize  int32
		signedWt    int32
	}{
		{name: "legacy", unsignedVsz: 219, signedVsz: 219, signedSize: 219, signedWt: 876},
		{name: "nested", unsignedVsz: 164, signedVsz: 164, signedSize: 245, signedWt: 653},
		{name: "wpkh", unsignedVsz: 141, signedVsz: 141, signedSize: 222, signedWt: 561},
		{name: "tr", unsignedVsz: 130, signedVsz: 130, signedSize: 181, signedWt: 520},
		{name: "wsh", unsignedVsz: 137, signedVsz: 137, signedSize: 302, signedWt: 548},
		{name: "mixed", unsignedVsz: 436, signedVsz: 436, signedSize: 648, signedWt: 1743},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			unsigned, err := DecodeTransaction(readPSBTFixture(t, tt.name+".psbt"), &chaincfg.RegressionNetParams)
			require.NoError(t, err)
			require.Equal(t, tt.unsignedVsz, unsigned.VsizeVBytes)
			require.True(t, unsigned.HasFee)
			require.InDelta(t, float64(unsigned.FeeSats)/float64(tt.unsignedVsz), unsigned.FeeRateSatVB, 1e-9)

			signed, err := DecodeTransaction(readPSBTFixture(t, tt.name+".signed"), &chaincfg.RegressionNetParams)
			require.NoError(t, err)
			require.Equal(t, tt.signedVsz, signed.VsizeVBytes)
			require.Equal(t, tt.signedSize, signed.SizeBytes)
			require.Equal(t, tt.signedWt, signed.WeightWU)
		})
	}
}

func TestDecodeTransactionPSBTSizeUnknownForAnUnsizedInput(t *testing.T) {
	packet, err := psbt.NewFromRawBytes(strings.NewReader(readPSBTFixture(t, "wsh.psbt")), true)
	require.NoError(t, err)
	packet.Inputs[0].WitnessScript = nil
	var buf bytes.Buffer
	require.NoError(t, packet.Serialize(&buf))

	got, err := DecodeTransaction(base64.StdEncoding.EncodeToString(buf.Bytes()), &chaincfg.RegressionNetParams)
	require.NoError(t, err)
	require.True(t, got.HasFee)
	require.Zero(t, got.VsizeVBytes)
	require.Zero(t, got.SizeBytes)
	require.Zero(t, got.WeightWU)
	require.Zero(t, got.FeeRateSatVB)
}

func TestDecodeTransactionPSBTSizeTaprootSighashByte(t *testing.T) {
	packet, err := psbt.NewFromRawBytes(strings.NewReader(readPSBTFixture(t, "tr.psbt")), true)
	require.NoError(t, err)
	packet.Inputs[0].SighashType = txscript.SigHashAll
	var buf bytes.Buffer
	require.NoError(t, packet.Serialize(&buf))

	got, err := DecodeTransaction(base64.StdEncoding.EncodeToString(buf.Bytes()), &chaincfg.RegressionNetParams)
	require.NoError(t, err)
	require.Equal(t, int32(521), got.WeightWU)
	require.Equal(t, int32(131), got.VsizeVBytes)
}

// wsh-half holds one of the two signatures that a 2-of-2 P2WSH input needs, and
// analyzepsbt names the second key as missing. wpkh-partial holds the one
// signature of its input, not finalized.
func TestDecodeTransactionPSBTSignedNeedsEachSignature(t *testing.T) {
	tests := []struct {
		name   string
		signed int
	}{
		{name: "wsh.psbt", signed: 0},
		{name: "wsh-half.signed", signed: 0},
		{name: "wsh.signed", signed: 1},
		{name: "wpkh-partial.signed", signed: 1},
		{name: "mixed.psbt", signed: 0},
		{name: "mixed.signed", signed: 4},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := DecodeTransaction(readPSBTFixture(t, tt.name), &chaincfg.RegressionNetParams)
			require.NoError(t, err)
			require.Equal(t, tt.signed, got.SignedInputs)
		})
	}
}

// A signature that the PSBT holds sizes the input, also a 72 byte high-R one.
func TestDecodeTransactionPSBTSizeUsesHeldSignatures(t *testing.T) {
	net := &chaincfg.RegressionNetParams
	key, err := btcec.NewPrivateKey()
	require.NoError(t, err)
	pubKey := key.PubKey().SerializeCompressed()
	address, err := btcutil.NewAddressWitnessPubKeyHash(btcutil.Hash160(pubKey), net)
	require.NoError(t, err)
	pkScript, err := txscript.PayToAddrScript(address)
	require.NoError(t, err)
	prev := wire.NewTxOut(100_000, pkScript)

	for lockTime := uint32(0); lockTime < 64; lockTime++ {
		tx := wire.NewMsgTx(2)
		tx.LockTime = lockTime
		tx.AddTxIn(wire.NewTxIn(wire.NewOutPoint(&chainhash.Hash{1}, 0), nil, nil))
		tx.AddTxOut(wire.NewTxOut(90_000, pkScript))
		hashes := txscript.NewTxSigHashes(tx, txscript.NewCannedPrevOutputFetcher(pkScript, prev.Value))
		sig, err := txscript.RawTxInWitnessSignature(tx, hashes, 0, prev.Value, pkScript, txscript.SigHashAll, key)
		require.NoError(t, err)
		if len(sig) != 72 {
			continue
		}

		packet, err := psbt.NewFromUnsignedTx(tx)
		require.NoError(t, err)
		packet.Inputs[0].WitnessUtxo = prev
		packet.Inputs[0].PartialSigs = []*psbt.PartialSig{{PubKey: pubKey, Signature: sig}}
		held, err := packet.B64Encode()
		require.NoError(t, err)
		require.NoError(t, psbt.MaybeFinalizeAll(packet))
		final, err := packet.B64Encode()
		require.NoError(t, err)

		gotHeld, err := DecodeTransaction(held, net)
		require.NoError(t, err)
		gotFinal, err := DecodeTransaction(final, net)
		require.NoError(t, err)
		require.Equal(t, gotFinal.WeightWU, gotHeld.WeightWU)
		require.Equal(t, gotFinal.SizeBytes, gotHeld.SizeBytes)
		return
	}
	t.Fatal("no 72 byte signature in 64 tries")
}
