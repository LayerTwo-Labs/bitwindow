package daemon

import (
	"context"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"

	"connectrpc.com/connect/v2"
	"connectrpc.com/connect/v2/connecthttp"
	"github.com/rs/zerolog"
	"github.com/stretchr/testify/require"

	pb "github.com/LayerTwo-Labs/sidesail/sidechain-orchestrator/gen/orchestrator/v1"
	rpc "github.com/LayerTwo-Labs/sidesail/sidechain-orchestrator/gen/orchestrator/v1/orchestratorv1connect"
	"github.com/LayerTwo-Labs/sidesail/sidechain-orchestrator/localauth"
)

func freeAddr(t *testing.T) string {
	t.Helper()
	lis, err := net.Listen("tcp", "127.0.0.1:0")
	require.NoError(t, err)
	addr := lis.Addr().String()
	require.NoError(t, lis.Close())
	return addr
}

func testConfig(t *testing.T) Config {
	t.Helper()
	home := t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv("BITWINDOW_HOME", home)
	dir := filepath.Join(home, "bitwindow")
	require.NoError(t, os.MkdirAll(dir, 0o755))
	return Config{
		DataDir:      dir,
		Network:      "signet",
		ListenAddr:   freeAddr(t),
		BitwindowDir: dir,
		AppHome:      home,
		LocalAuth:    true,
		OwnerPID:     os.Getpid(),
		Log:          zerolog.Nop(),
	}
}

func startRun(t *testing.T, ctx context.Context, cfg Config) <-chan error {
	t.Helper()
	done := make(chan error, 1)
	go func() { done <- Run(ctx, cfg) }()
	client := orchestratorClient(cfg)
	require.Eventually(t, func() bool {
		_, err := client.ListBinaries(ctx, &pb.ListBinariesRequest{})
		return err == nil
	}, 30*time.Second, 50*time.Millisecond, "drivechaind never served")
	return done
}

func orchestratorClient(cfg Config) rpc.OrchestratorServiceClient {
	return rpc.NewOrchestratorServiceClient(connect.NewClient(
		connecthttp.NewTransport(http.DefaultClient, "http://"+cfg.ListenAddr, connecthttp.WithGRPC()),
		localauth.ClientInterceptor(cfg.BitwindowDir),
	))
}

func awaitRun(t *testing.T, done <-chan error) {
	t.Helper()
	select {
	case err := <-done:
		require.NoError(t, err)
	case <-time.After(30 * time.Second):
		t.Fatal("Run did not return")
	}
}

func TestRunReturnsWhenTheContextEnds(t *testing.T) {
	cfg := testConfig(t)
	ctx, cancel := context.WithCancel(t.Context())
	done := startRun(t, ctx, cfg)

	cancel()
	awaitRun(t, done)

	conn, err := net.DialTimeout("tcp", cfg.ListenAddr, time.Second)
	if err == nil {
		_ = conn.Close()
	}
	require.Error(t, err, "the RPC port must be free after Run returns")
}

func TestRunReturnsAfterTheShutdownRPC(t *testing.T) {
	cfg := testConfig(t)
	done := startRun(t, t.Context(), cfg)

	_, err := orchestratorClient(cfg).Shutdown(t.Context(), &pb.ShutdownRequest{})
	require.NoError(t, err)
	awaitRun(t, done)
}

func TestRunServesAgainInTheSameProcess(t *testing.T) {
	cfg := testConfig(t)
	for range 2 {
		ctx, cancel := context.WithCancel(t.Context())
		done := startRun(t, ctx, cfg)
		cancel()
		awaitRun(t, done)
	}
}

func TestShutdownServerCompletesTheResponse(t *testing.T) {
	release := make(chan struct{})
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Length", "2")
		_, err := io.WriteString(w, "a")
		if err != nil {
			return
		}
		w.(http.Flusher).Flush()
		<-release
		_, err = io.WriteString(w, "b")
		if err != nil {
			return
		}
	}))
	t.Cleanup(srv.Close)
	t.Cleanup(func() { close(release) })
	resp, err := srv.Client().Get(srv.URL)
	require.NoError(t, err)
	t.Cleanup(func() { require.NoError(t, resp.Body.Close()) })

	done := make(chan error, 1)
	go func() { done <- shutdownServer(srv.Config) }()
	select {
	case err := <-done:
		t.Fatalf("shutdown returned before the response: %v", err)
	case <-time.After(50 * time.Millisecond):
	}
	release <- struct{}{}
	body, err := io.ReadAll(resp.Body)
	require.NoError(t, err)
	require.Equal(t, "ab", string(body))
	awaitRun(t, done)
}

func TestShutdownServerClosesAnOpenStream(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Length", "2")
		_, err := io.WriteString(w, "a")
		if err != nil {
			return
		}
		w.(http.Flusher).Flush()
		<-r.Context().Done()
	}))
	t.Cleanup(srv.Close)
	resp, err := srv.Client().Get(srv.URL)
	require.NoError(t, err)
	t.Cleanup(func() { require.NoError(t, resp.Body.Close()) })

	done := make(chan error, 1)
	go func() { done <- shutdownServer(srv.Config) }()
	awaitRun(t, done)
	body, err := io.ReadAll(resp.Body)
	require.ErrorIs(t, err, io.ErrUnexpectedEOF)
	require.Equal(t, "a", string(body))
}
