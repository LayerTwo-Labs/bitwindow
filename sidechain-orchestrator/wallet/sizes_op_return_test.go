package wallet

import (
	"bytes"
	"encoding/hex"
	"testing"

	"github.com/btcsuite/btcd/chaincfg"
	"github.com/btcsuite/btcd/wire"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestOutputVsizeOfOpReturnMatchesTheBuiltOutput(t *testing.T) {
	for _, size := range []int{1, 20, 75, 76, 252, 253, 255, 256, 520, 521, 65535, 65536} {
		spec := TxOutSpec{OpReturnHex: hex.EncodeToString(bytes.Repeat([]byte{0xab}, size))}
		in := []RawInput{{TxID: "7777777777777777777777777777777777777777777777777777777777777777"}}
		rawHex, err := BuildUnsignedTransaction(in, []TxOutSpec{spec}, &chaincfg.RegressionNetParams)
		require.NoError(t, err, "payload of %d bytes", size)
		raw, err := hex.DecodeString(rawHex)
		require.NoError(t, err)
		var tx wire.MsgTx
		require.NoError(t, tx.Deserialize(bytes.NewReader(raw)))
		require.Len(t, tx.TxOut, 1)

		got, err := outputVsize(spec, &chaincfg.RegressionNetParams)
		require.NoError(t, err)
		assert.Equal(t, tx.TxOut[0].SerializeSize(), got, "payload of %d bytes", size)
	}
}

func TestOutputVsizeRefusesBadOpReturnHex(t *testing.T) {
	_, err := outputVsize(TxOutSpec{OpReturnHex: "zz"}, &chaincfg.RegressionNetParams)
	require.Error(t, err)
}
