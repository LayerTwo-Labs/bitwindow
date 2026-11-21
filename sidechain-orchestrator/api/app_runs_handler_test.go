package api

import (
	"context"
	"io"
	"net/http"
	"testing"
	"time"

	"connectrpc.com/connect/v2"
	"connectrpc.com/connect/v2/connecthttp"
	"github.com/rs/zerolog"
	"github.com/stretchr/testify/require"

	orchestrator "github.com/LayerTwo-Labs/sidesail/sidechain-orchestrator"
	pb "github.com/LayerTwo-Labs/sidesail/sidechain-orchestrator/gen/orchestrator/v1"
	rpc "github.com/LayerTwo-Labs/sidesail/sidechain-orchestrator/gen/orchestrator/v1/orchestratorv1connect"
)

func appRunsClient(t *testing.T, orch *orchestrator.Orchestrator) rpc.OrchestratorServiceClient {
	t.Helper()
	mux := http.NewServeMux()
	rpcServer := connect.NewServer()
	rpc.RegisterOrchestratorServiceHandler(rpcServer, NewHandler(orch))
	connecthttp.Mount(mux, rpcServer)
	srv := h2cServer(mux)
	t.Cleanup(srv.Close)
	return rpc.NewOrchestratorServiceClient(connect.NewClient(connecthttp.NewTransport(h2cClient(), srv.URL, connecthttp.WithGRPC())))
}

func TestWatchAppRunsStreamsARunAndItsExit(t *testing.T) {
	orch := orchestrator.New(t.TempDir(), "regtest", t.TempDir(), nil, zerolog.New(io.Discard))
	runs := orchestrator.NewAppRuns("thunder")
	orch.SetAppRuns(runs)
	client := appRunsClient(t, orch)

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	stream, err := client.WatchAppRuns(ctx, &pb.WatchAppRunsRequest{})
	require.NoError(t, err)
	first, err := stream.Receive()
	require.NoError(t, err)
	require.Empty(t, first.GetRuns())

	id, exited, err := runs.Start("thunder", []string{"--headless"}, map[string]string{"A": "1"}, "/logs/thunder.log")
	require.NoError(t, err)
	next, err := stream.Receive()
	require.NoError(t, err)
	require.Len(t, next.GetRuns(), 1)
	run := next.GetRuns()[0]
	require.Equal(t, id, run.GetId())
	require.Equal(t, "thunder", run.GetName())
	require.Equal(t, []string{"--headless"}, run.GetArgs())
	require.Equal(t, map[string]string{"A": "1"}, run.GetEnv())
	require.Equal(t, "/logs/thunder.log", run.GetLogPath())
	require.False(t, run.GetStop())

	_, err = client.ReportAppRunExit(ctx, &pb.ReportAppRunExitRequest{Id: id, Error: "boom"})
	require.NoError(t, err)
	require.EqualError(t, <-exited, "boom")

	_, err = client.ReportAppRunExit(ctx, &pb.ReportAppRunExitRequest{Id: id})
	require.Equal(t, connect.CodeNotFound, connect.CodeOf(err))
}

func TestWatchAppRunsRefusesAnOrchestratorWithNoAppRuns(t *testing.T) {
	orch := orchestrator.New(t.TempDir(), "regtest", t.TempDir(), nil, zerolog.New(io.Discard))
	client := appRunsClient(t, orch)

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	stream, err := client.WatchAppRuns(ctx, &pb.WatchAppRunsRequest{})
	if err == nil {
		_, err = stream.Receive()
	}
	require.Equal(t, connect.CodeFailedPrecondition, connect.CodeOf(err))
	_, err = client.ReportAppRunExit(ctx, &pb.ReportAppRunExitRequest{Id: "x"})
	require.Equal(t, connect.CodeFailedPrecondition, connect.CodeOf(err))
}
