package sidepot

import (
	"context"
	"encoding/json"
	"net"
	"strconv"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	pb "github.com/LayerTwo-Labs/sidesail/sidechain-orchestrator/gen/sidepot/v1"
	"github.com/LayerTwo-Labs/sidesail/sidechain-orchestrator/sidechain"
)

func handlerFor(t *testing.T, results map[string]any, params map[string]json.RawMessage) *Handler {
	t.Helper()
	srv := fakeRPC(t, results, params)
	host, portText, err := net.SplitHostPort(srv.Listener.Addr().String())
	require.NoError(t, err)
	port, err := strconv.Atoi(portText)
	require.NoError(t, err)
	return NewHandler(sidechain.NewJSONRPCProxy(host, port))
}

func TestCallRawPassesGameMethodsThrough(t *testing.T) {
	params := map[string]json.RawMessage{}
	h := handlerFor(t, map[string]any{
		"game_state":   map[string]any{"round": 3},
		"game_account": map[string]any{"keys": 2},
	}, params)

	state, err := h.CallRaw(context.Background(), &pb.CallRawRequest{Method: "game_state", ParamsJson: "[]"})
	require.NoError(t, err)
	assert.JSONEq(t, `{"round":3}`, state.ResultJson)
	assert.JSONEq(t, `[]`, string(params["game_state"]))

	account, err := h.CallRaw(context.Background(), &pb.CallRawRequest{Method: "game_account", ParamsJson: `["ab"]`})
	require.NoError(t, err)
	assert.JSONEq(t, `{"keys":2}`, account.ResultJson)
	assert.JSONEq(t, `["ab"]`, string(params["game_account"]))
}

func TestCallRawRefusesBrokenParams(t *testing.T) {
	h := handlerFor(t, nil, nil)
	_, err := h.CallRaw(context.Background(), &pb.CallRawRequest{Method: "game_state", ParamsJson: "{"})
	require.ErrorContains(t, err, "unmarshal params")
}

func TestBalanceAndBlockCountReadTheNode(t *testing.T) {
	h := handlerFor(t, map[string]any{
		"balance":       map[string]int64{"total_sats": 7000, "available_sats": 6000},
		"getblockcount": 12,
	}, nil)

	total, available, err := h.WalletBalance(context.Background())
	require.NoError(t, err)
	assert.Equal(t, [2]int64{7000, 6000}, [2]int64{total, available})

	count, err := h.GetBlockCount(context.Background(), &pb.GetBlockCountRequest{})
	require.NoError(t, err)
	assert.Equal(t, int64(12), count.Count)
}

func TestConnectPeerSendsOneAddress(t *testing.T) {
	params := map[string]json.RawMessage{}
	h := handlerFor(t, map[string]any{"connect_peer": nil}, params)

	_, err := h.ConnectPeer(context.Background(), &pb.ConnectPeerRequest{Address: "127.0.0.1:4088"})
	require.NoError(t, err)
	assert.JSONEq(t, `["127.0.0.1:4088"]`, string(params["connect_peer"]))
}
