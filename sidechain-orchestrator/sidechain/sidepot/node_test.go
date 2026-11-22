package sidepot

import (
	"context"
	"errors"
	"net/http/httptest"
	"net/url"
	"strconv"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/LayerTwo-Labs/sidesail/sidechain-orchestrator/sidechain"
)

type fakeHost struct {
	sidechain.Host
	esplora   string
	rpcErr    error
	readerErr error
}

func (h fakeHost) MainchainEsplora() string { return h.esplora }

func (h fakeHost) MainchainRPC() (string, int, error) { return "127.0.0.1", 8332, h.rpcErr }

func (h fakeHost) MainchainReader(context.Context) (string, error) {
	return "/data/mainchain-reader.cookie", h.readerErr
}

func mainnetNode(seed string) *Node {
	proxy := sidechain.NewJSONRPCProxy("127.0.0.1", 6088)
	proxy.SeedPeer = seed
	return NewNode(proxy, "mainnet")
}

func TestLightModeReadsBlocksFromEsplora(t *testing.T) {
	args, err := mainnetNode("").Args(context.Background(), fakeHost{esplora: "https://esplora.example"})
	require.NoError(t, err)
	assert.Equal(t, []string{
		"--headless",
		"--l1-rpc-url=http://unused.invalid",
		"--l1-esplora-url=https://esplora.example",
	}, args)
}

func TestFullModeReadsBlocksFromTheLocalNode(t *testing.T) {
	args, err := mainnetNode("").Args(context.Background(), fakeHost{})
	require.NoError(t, err)
	assert.Equal(t, []string{
		"--headless",
		"--l1-rpc-url=http://127.0.0.1:8332",
		"--l1-rpc-cookie=/data/mainchain-reader.cookie",
	}, args)
}

func TestSeedPeerIsDialedWhenTheNetworkNamesOne(t *testing.T) {
	args, err := mainnetNode("seed.example:4088").Args(context.Background(), fakeHost{esplora: "https://esplora.example"})
	require.NoError(t, err)
	assert.Contains(t, args, "--add-peer=seed.example:4088")
}

func TestNoBlockSourceStopsTheStart(t *testing.T) {
	noNode := errors.New("no local mainchain node")
	_, err := mainnetNode("").Args(context.Background(), fakeHost{rpcErr: noNode})
	require.ErrorIs(t, err, noNode)

	refused := errors.New("reader refused")
	_, err = mainnetNode("").Args(context.Background(), fakeHost{readerErr: refused})
	require.ErrorIs(t, err, refused)
}

func TestOtherNetworksAreRefused(t *testing.T) {
	for _, network := range []string{"", "signet", "regtest", "betanet"} {
		node := NewNode(sidechain.NewJSONRPCProxy("127.0.0.1", 6088), network)
		_, err := node.Args(context.Background(), fakeHost{esplora: "https://esplora.example"})
		require.ErrorContains(t, err, "eCash mainnet only", network)
	}
}

func TestModeArgsCoverEveryBlockSourceFlag(t *testing.T) {
	node := mainnetNode("")
	owned := node.ModeArgs()
	for _, host := range []fakeHost{{esplora: "https://esplora.example"}, {}} {
		args, err := node.Args(context.Background(), host)
		require.NoError(t, err)
		for _, arg := range args[1:] {
			name, _, _ := strings.Cut(arg, "=")
			assert.Contains(t, owned, name)
		}
	}
}

func TestNodeIsBmmNode(t *testing.T) {
	var node sidechain.Node = mainnetNode("")
	_, isBMM := node.(sidechain.BMMNode)
	assert.True(t, isBMM, "the BMM engine drives the node")
}

// nodeFromServer points a node at a fake JSON-RPC server.
func nodeFromServer(t *testing.T, srv *httptest.Server) *Node {
	t.Helper()
	address, err := url.Parse(srv.URL)
	require.NoError(t, err)
	port, err := strconv.Atoi(address.Port())
	require.NoError(t, err)
	return NewNode(sidechain.NewJSONRPCProxy(address.Hostname(), port), "mainnet")
}

func TestBlockTemplateCountsTheBlockBonus(t *testing.T) {
	tests := []struct {
		name        string
		game        any
		wantWorth   int64
		wantOpening int64
	}{
		{
			name: "the bonus is 5% of the pool as of the latest mainchain block",
			game: map[string]any{
				"bonus_pool_sats": 9_000_000,
				"preview":         map[string]any{"bonus_pool_sats": 1_130_019},
			},
			wantWorth:   300 + 56_500,
			wantOpening: 28_250,
		},
		{
			name:        "a small pool still takes the minimum bid",
			game:        map[string]any{"bonus_pool_sats": 186_915},
			wantWorth:   300 + 9_345,
			wantOpening: 10_000,
		},
		{
			name:        "an odd cap rounds the bid up, so it earns the whole cap",
			game:        map[string]any{"bonus_pool_sats": 500_020},
			wantWorth:   300 + 25_001,
			wantOpening: 12_501,
		},
		{
			name:        "no game, no bonus",
			game:        nil,
			wantWorth:   300,
			wantOpening: 10_000,
		},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			node := nodeFromServer(t, fakeRPC(t, map[string]any{
				"get_block_template": map[string]any{
					"critical_hash": "ab", "block": map[string]any{}, "fees_sats": 300,
				},
				"game_state": test.game,
			}, nil))

			template, err := node.GetBlockTemplate(context.Background())
			require.NoError(t, err)
			assert.Equal(t, test.wantWorth, template.FeesSats)
			assert.Equal(t, test.wantOpening, template.OpeningBidSats)
		})
	}
}
