package zside

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"net/http/httptest"
	"slices"
	"strconv"
	"testing"

	commonpb "github.com/LayerTwo-Labs/sidesail/sidechain-orchestrator/gen/cusf/common/v1"
	enforcerpb "github.com/LayerTwo-Labs/sidesail/sidechain-orchestrator/gen/cusf/mainchain/v1"
	enforcerrpc "github.com/LayerTwo-Labs/sidesail/sidechain-orchestrator/gen/cusf/mainchain/v1/mainchainv1connect"
	pb "github.com/LayerTwo-Labs/sidesail/sidechain-orchestrator/gen/zside/v1"
	"github.com/LayerTwo-Labs/sidesail/sidechain-orchestrator/sidechain"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/types/known/wrapperspb"
)

type maturityValidator struct {
	enforcerrpc.ValidatorServiceClient
	tip      uint32
	calls    int
	err      error
	blockErr error
}

func mainHash(height uint32) *commonpb.ReverseHex {
	return &commonpb.ReverseHex{Hex: wrapperspb.String(fmt.Sprintf("main-%d", height))}
}

func (v *maturityValidator) GetChainTip(context.Context, *enforcerpb.GetChainTipRequest) (*enforcerpb.GetChainTipResponse, error) {
	return &enforcerpb.GetChainTipResponse{BlockHeaderInfo: &enforcerpb.BlockHeaderInfo{BlockHash: mainHash(v.tip), Height: v.tip}}, v.err
}

func (v *maturityValidator) GetBlockInfo(_ context.Context, req *enforcerpb.GetBlockInfoRequest) (*enforcerpb.GetBlockInfoResponse, error) {
	v.calls++
	if v.blockErr != nil {
		return nil, v.blockErr
	}
	if req.GetSidechainId().GetValue() != 98 {
		return nil, fmt.Errorf("wrong sidechain slot")
	}
	var height uint32
	if _, err := fmt.Sscanf(req.GetBlockHash().GetHex().GetValue(), "main-%d", &height); err != nil {
		return nil, err
	}
	var infos []*enforcerpb.GetBlockInfoResponse_Info
	for range min(req.GetMaxAncestors()+1, 17) {
		info := &enforcerpb.GetBlockInfoResponse_Info{
			HeaderInfo: &enforcerpb.BlockHeaderInfo{BlockHash: mainHash(height), PrevBlockHash: mainHash(height - 1), Height: height},
			BlockInfo:  &enforcerpb.BlockInfo{},
		}
		if height == 100 {
			info.BlockInfo.Events = []*enforcerpb.BlockInfo_Event{{Event: &enforcerpb.BlockInfo_Event_Deposit{Deposit: &enforcerpb.Deposit{
				Outpoint: &enforcerpb.OutPoint{Txid: &commonpb.ReverseHex{Hex: wrapperspb.String("deposit")}, Vout: wrapperspb.UInt32(0)},
			}}}}
		}
		infos = append(infos, info)
		if height == 0 {
			break
		}
		height--
	}
	slices.Reverse(infos)
	return &enforcerpb.GetBlockInfoResponse{Infos: infos}, nil
}

func sideHeader(height int) maturityHeader {
	header := maturityHeader{MerkleRoot: fmt.Sprintf("%064x", height), PrevMainHash: fmt.Sprintf("%064x", height+1000)}
	if height > 0 {
		prev := fmt.Sprintf("%064x", height-1)
		header.PrevSideHash = &prev
	}
	return header
}

type maturityNode struct {
	sideTip    int
	blockCalls int
	coins      []any
	fail       bool
}

func maturityHandler(t *testing.T, node *maturityNode, validator *maturityValidator) *Handler {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var req struct {
			ID     json.RawMessage   `json:"id"`
			Method string            `json:"method"`
			Params []json.RawMessage `json:"params"`
		}
		require.NoError(t, json.NewDecoder(r.Body).Decode(&req))
		var result any
		switch req.Method {
		case "get_wallet_utxos":
			result = node.coins
		case "get_wallet_utxos_unconfirmed", "get_wallet_stxos_unconfirmed":
			result = []any{}
		case "balance":
			result = map[string]any{"total_transparent_sats": 200000, "available_transparent_sats": 200000}
		case "get_best_sidechain_block_hash":
			result = fmt.Sprintf("%064x", node.sideTip)
		case "get_block":
			node.blockCalls++
			var hash string
			require.NoError(t, json.Unmarshal(req.Params[0], &hash))
			height, err := strconv.ParseInt(hash, 16, 32)
			require.NoError(t, err)
			result = map[string]any{"header": sideHeader(int(height))}
		default:
			t.Errorf("unexpected node method %s", req.Method)
		}
		response := map[string]any{"jsonrpc": "2.0", "id": req.ID, "result": result}
		if node.fail {
			delete(response, "result")
			response["error"] = map[string]any{"code": -1, "message": "node failed"}
		}
		require.NoError(t, json.NewEncoder(w).Encode(response))
	}))
	t.Cleanup(srv.Close)
	host, portText, err := net.SplitHostPort(srv.Listener.Addr().String())
	require.NoError(t, err)
	port, err := strconv.Atoi(portText)
	require.NoError(t, err)
	return NewHandler(sidechain.NewJSONRPCProxy(host, port), func() (enforcerrpc.ValidatorServiceClient, error) { return validator, nil })
}

func TestMaturityUsesEachChainHeightAndCachesEachTip(t *testing.T) {
	coinbase, err := coinbaseTxid(sideHeader(100))
	require.NoError(t, err)
	deposit := utxoJSON("deposit", "address", 100000)
	deposit["outpoint"] = map[string]any{"Deposit": "deposit:0"}
	coin := utxoJSON(coinbase, "address", 100000)
	coin["outpoint"] = map[string]any{"Coinbase": map[string]any{"txid": coinbase, "vout": 0}}
	node := &maturityNode{sideTip: 148, coins: []any{deposit, coin}}
	validator := &maturityValidator{tip: 149}
	handler := maturityHandler(t, node, validator)
	ctx := context.Background()
	read := func(depositSpendable, coinbaseSpendable bool) {
		t.Helper()
		resp, err := handler.GetWalletUtxos(ctx, &pb.GetWalletUtxosRequest{})
		require.NoError(t, err)
		var rows []struct {
			Spendable bool `json:"spendable"`
		}
		require.NoError(t, json.Unmarshal([]byte(resp.UtxosJson), &rows))
		require.Len(t, rows, 2)
		assert.Equal(t, depositSpendable, rows[0].Spendable)
		assert.Equal(t, coinbaseSpendable, rows[1].Spendable)
		balance, err := handler.GetBalance(ctx, &pb.GetBalanceRequest{})
		require.NoError(t, err)
		var available int64
		if depositSpendable {
			available += 100000
		}
		if coinbaseSpendable {
			available += 100000
		}
		assert.EqualValues(t, 200000, balance.TotalTransparentSats)
		assert.Equal(t, available, balance.AvailableTransparentSats)
		total, walletAvailable, err := handler.WalletBalance(ctx)
		require.NoError(t, err)
		assert.EqualValues(t, 200000, total)
		assert.Equal(t, available, walletAvailable)
	}
	read(false, false)
	assert.Equal(t, 3, validator.calls)
	assert.Equal(t, 49, node.blockCalls)
	read(false, false)
	assert.Equal(t, 3, validator.calls)
	assert.Equal(t, 49, node.blockCalls)
	validator.tip = 150
	read(true, false)
	assert.Equal(t, 6, validator.calls)
	assert.Equal(t, 49, node.blockCalls)
	node.sideTip = 149
	read(true, true)
	assert.Equal(t, 6, validator.calls)
	assert.Equal(t, 98, node.blockCalls)
	validator.tip = 149
	node.sideTip = 148
	read(false, false)
}

func TestMaturityReturnsValidatorAndNodeErrors(t *testing.T) {
	deposit := utxoJSON("deposit", "address", 100000)
	deposit["outpoint"] = map[string]any{"Deposit": "deposit:0"}
	node := &maturityNode{coins: []any{deposit}}
	validator := &maturityValidator{err: fmt.Errorf("validator failed")}
	handler := maturityHandler(t, node, validator)
	_, err := handler.GetWalletUtxos(context.Background(), &pb.GetWalletUtxosRequest{})
	require.ErrorContains(t, err, "validator failed")
	validator.err = nil
	validator.tip = 149
	validator.blockErr = fmt.Errorf("block info failed")
	_, err = handler.GetWalletUtxos(context.Background(), &pb.GetWalletUtxosRequest{})
	require.ErrorContains(t, err, "block info failed")
	validator.blockErr = nil
	_, err = handler.GetWalletUtxos(context.Background(), &pb.GetWalletUtxosRequest{})
	require.NoError(t, err)
	assert.Equal(t, 4, validator.calls)
	node.fail = true
	_, err = handler.GetWalletUtxos(context.Background(), &pb.GetWalletUtxosRequest{})
	require.ErrorContains(t, err, "node failed")
}

func TestCoinbaseTxidMatchesBorshHash(t *testing.T) {
	previous := "404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f"
	header := maturityHeader{
		MerkleRoot:   "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f",
		PrevMainHash: "202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
		PrevSideHash: &previous,
	}
	txid, err := coinbaseTxid(header)
	require.NoError(t, err)
	assert.Equal(t, "2657ebc6309a297a7d339aeff8476f3516b3a6627af9d39dc9add8bbf47ea1e8", txid)
}

func TestMaturityRegularCoinsDoNotCallTheValidator(t *testing.T) {
	node := nodeServer(t, map[string]any{
		"get_wallet_utxos":             []any{utxoJSON("regular", "address", 100000)},
		"get_wallet_utxos_unconfirmed": []any{},
		"get_wallet_stxos_unconfirmed": []any{},
	})
	handler := NewHandler(node.JSONRPCProxy, nil)
	resp, err := handler.GetWalletUtxos(context.Background(), &pb.GetWalletUtxosRequest{})
	require.NoError(t, err)
	var rows []struct {
		Spendable bool `json:"spendable"`
	}
	require.NoError(t, json.Unmarshal([]byte(resp.UtxosJson), &rows))
	require.Len(t, rows, 1)
	assert.True(t, rows[0].Spendable)
}
