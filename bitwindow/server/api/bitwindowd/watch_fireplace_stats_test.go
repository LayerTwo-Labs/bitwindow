package bitwindowd_test

import (
	"context"
	"database/sql"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"connectrpc.com/connect/v2"
	"connectrpc.com/connect/v2/connecthttp"
	corerpc "github.com/barebitcoin/btc-buf/gen/bitcoin/bitcoind/v1alpha/bitcoindv1alphaconnect"
	"github.com/btcsuite/btcd/chaincfg/chainhash"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/types/known/emptypb"

	api_bitwindowd "github.com/LayerTwo-Labs/sidesail/bitwindow/server/api/bitwindowd"
	"github.com/LayerTwo-Labs/sidesail/bitwindow/server/config"
	"github.com/LayerTwo-Labs/sidesail/bitwindow/server/database"
	v1 "github.com/LayerTwo-Labs/sidesail/bitwindow/server/gen/bitwindowd/v1"
	"github.com/LayerTwo-Labs/sidesail/bitwindow/server/gen/bitwindowd/v1/bitwindowdv1connect"
	"github.com/LayerTwo-Labs/sidesail/bitwindow/server/models/blocks"
	"github.com/LayerTwo-Labs/sidesail/bitwindow/server/service"
)

func watchFireplaceStats(t *testing.T, server *api_bitwindowd.Server) bitwindowdv1connect.BitwindowdServiceWatchFireplaceStatsClientStream {
	t.Helper()
	srv := connect.NewServer()
	bitwindowdv1connect.RegisterBitwindowdServiceHandler(srv, server)
	mux := http.NewServeMux()
	connecthttp.Mount(mux, srv)
	httpServer := httptest.NewServer(mux)
	t.Cleanup(httpServer.Close)
	cli := bitwindowdv1connect.NewBitwindowdServiceClient(connect.NewClient(connecthttp.NewTransport(httpServer.Client(), httpServer.URL)))
	ctx, cancel := context.WithTimeout(t.Context(), 10*time.Second)
	t.Cleanup(cancel)
	stream, err := cli.WatchFireplaceStats(ctx, &emptypb.Empty{})
	require.NoError(t, err)
	t.Cleanup(func() { _ = stream.Close() })
	return stream
}

func nextStats(t *testing.T, stream bitwindowdv1connect.BitwindowdServiceWatchFireplaceStatsClientStream) *v1.GetFireplaceStatsResponse {
	t.Helper()
	for {
		msg, err := stream.Receive()
		require.NoError(t, err)
		if !msg.GetHeartbeat() {
			return msg.GetStats()
		}
	}
}

func statsServer(t *testing.T) (*api_bitwindowd.Server, *sql.DB) {
	t.Helper()
	db := database.Test(t)
	core := service.New("bitcoind", func(context.Context) (corerpc.BitcoinServiceClient, error) {
		return nil, assert.AnError
	})
	return api_bitwindowd.New(nil, db, core, nil, nil, nil, config.Config{BitcoinCoreNetwork: config.NetworkRegtest}, nil), db
}

func TestWatchFireplaceStats(t *testing.T) {
	t.Parallel()

	t.Run("a block that leaves the 24 hour window sends new stats", func(t *testing.T) {
		t.Parallel()
		server, db := statsServer(t)
		edge := time.Unix(time.Now().Unix(), 0).Add(-24*time.Hour + 2*time.Second)
		require.NoError(t, blocks.MarkBlocksProcessed(t.Context(), db, []blocks.ProcessedBlock{
			{Height: 1, Hash: chainhash.Hash{1}, BlockTime: edge, Txids: []chainhash.Hash{{1}, {2}}},
		}))
		stream := watchFireplaceStats(t, server)

		first := nextStats(t, stream)
		assert.EqualValues(t, 1, first.BlockCount_24H)
		assert.EqualValues(t, 1, first.TransactionCount_24H)

		next := nextStats(t, stream)
		assert.Zero(t, next.BlockCount_24H)
		assert.Zero(t, next.TransactionCount_24H)
	})

	t.Run("a new processed block sends new stats", func(t *testing.T) {
		t.Parallel()
		server, db := statsServer(t)
		tip := make(chan struct{}, 1)
		server.SetTipSource(func(context.Context) <-chan struct{} { return tip })
		stream := watchFireplaceStats(t, server)

		first := nextStats(t, stream)
		assert.Zero(t, first.BlockCount_24H)

		require.NoError(t, blocks.MarkBlocksProcessed(t.Context(), db, []blocks.ProcessedBlock{
			{Height: 1, Hash: chainhash.Hash{1}, BlockTime: time.Now(), Txids: []chainhash.Hash{{1}}},
		}))
		tip <- struct{}{}

		next := nextStats(t, stream)
		assert.EqualValues(t, 1, next.BlockCount_24H)
	})
}
