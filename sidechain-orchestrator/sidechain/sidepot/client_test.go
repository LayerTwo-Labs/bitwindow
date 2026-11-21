package sidepot

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// fakeRPC answers each JSON-RPC method with its canned result and records the
// params it was sent.
func fakeRPC(t *testing.T, results map[string]any, params map[string]json.RawMessage) *httptest.Server {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var req struct {
			Method string          `json:"method"`
			Params json.RawMessage `json:"params"`
		}
		require.NoError(t, json.NewDecoder(r.Body).Decode(&req))
		result, ok := results[req.Method]
		if !ok {
			t.Errorf("unexpected method: %s", req.Method)
		}
		if params != nil {
			params[req.Method] = req.Params
		}
		raw, err := json.Marshal(result)
		require.NoError(t, err)
		w.Header().Set("Content-Type", "application/json")
		require.NoError(t, json.NewEncoder(w).Encode(rpcResponse{Result: raw}))
	}))
	t.Cleanup(srv.Close)
	return srv
}

func clientFromServer(srv *httptest.Server) *Client {
	return &Client{baseURL: srv.URL, http: srv.Client()}
}

func TestBalance(t *testing.T) {
	srv := fakeRPC(t, map[string]any{
		"balance": BalanceResponse{TotalSats: 100_000, AvailableSats: 80_000},
	}, nil)

	bal, err := clientFromServer(srv).Balance(context.Background())
	require.NoError(t, err)
	assert.Equal(t, int64(100_000), bal.TotalSats)
	assert.Equal(t, int64(80_000), bal.AvailableSats)
}

func TestGetBlockCount(t *testing.T) {
	srv := fakeRPC(t, map[string]any{"getblockcount": 42}, nil)

	count, err := clientFromServer(srv).GetBlockCount(context.Background())
	require.NoError(t, err)
	assert.Equal(t, 42, count)
}

func TestConnectPeerSendsPositionalParams(t *testing.T) {
	params := map[string]json.RawMessage{}
	srv := fakeRPC(t, map[string]any{"connect_peer": nil}, params)

	require.NoError(t, clientFromServer(srv).ConnectPeer(context.Background(), "127.0.0.1:4088"))
	assert.JSONEq(t, `["127.0.0.1:4088"]`, string(params["connect_peer"]))
}

func TestGameStateReturnsTheNodeReply(t *testing.T) {
	params := map[string]json.RawMessage{}
	srv := fakeRPC(t, map[string]any{"game_state": map[string]any{"round": 3}}, params)

	state, err := clientFromServer(srv).GameState(context.Background())
	require.NoError(t, err)
	assert.JSONEq(t, `{"round":3}`, string(state))
	assert.JSONEq(t, `[]`, string(params["game_state"]))
}

func TestRPCErrorNamesTheNode(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"jsonrpc":"2.0","id":"orchestrator","error":{"code":-32601,"message":"Method not found"}}`))
	}))
	t.Cleanup(srv.Close)

	_, err := clientFromServer(srv).CallRaw(context.Background(), "nope", nil)
	require.EqualError(t, err, "sidepot RPC error -32601: Method not found")
}
