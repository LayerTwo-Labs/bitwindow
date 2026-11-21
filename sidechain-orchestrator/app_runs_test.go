package orchestrator

import (
	"context"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/LayerTwo-Labs/sidesail/sidechain-orchestrator/config"
)

func TestAppRunsStartStopAndExit(t *testing.T) {
	runs := NewAppRuns("thunder")
	require.True(t, runs.Hosts("thunder"))
	require.False(t, runs.Hosts("bitnames"))

	id, exited, err := runs.Start("thunder", []string{"--headless"}, map[string]string{"A": "1"}, "/logs/thunder.log")
	require.NoError(t, err)
	require.Equal(t, []AppRun{{
		ID: id, Name: "thunder", Args: []string{"--headless"}, Env: map[string]string{"A": "1"}, LogPath: "/logs/thunder.log",
	}}, runs.Runs())

	_, _, err = runs.Start("thunder", nil, nil, "")
	require.ErrorContains(t, err, "runs thunder already")

	require.NoError(t, runs.Stop(id))
	require.True(t, runs.Runs()[0].Stop)

	require.NoError(t, runs.Exited(id, "the node panicked"))
	require.EqualError(t, <-exited, "the node panicked")
	_, open := <-exited
	require.False(t, open)
	require.Empty(t, runs.Runs())

	require.ErrorIs(t, runs.Exited(id, ""), ErrUnknownAppRun)
	require.Error(t, runs.Stop(id))
}

func TestAppRunsRefuseABinaryTheAppDoesNotRun(t *testing.T) {
	_, _, err := NewAppRuns("thunder").Start("bitnames", nil, nil, "")
	require.ErrorContains(t, err, "does not run bitnames")

	var none *AppRuns
	require.False(t, none.Hosts("thunder"))
}

func TestAppRunsWakeASubscriber(t *testing.T) {
	runs := NewAppRuns("thunder")
	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)
	changed := runs.Subscribe(ctx)

	id, _, err := runs.Start("thunder", nil, nil, "")
	require.NoError(t, err)
	requireWake(t, changed)
	require.NoError(t, runs.Stop(id))
	requireWake(t, changed)
	require.NoError(t, runs.Exited(id, ""))
	requireWake(t, changed)
}

func requireWake(t *testing.T, changed <-chan struct{}) {
	t.Helper()
	select {
	case <-changed:
	case <-time.After(5 * time.Second):
		t.Fatal("no wake")
	}
}

func TestProcessManagerHandsAnAppRunToTheApp(t *testing.T) {
	pm, dir := newTestProcessManager(t)
	pm.AppRuns = NewAppRuns("thunder")
	exits := make(chan ProcessExitInfo, 1)
	pm.OnExit = func(info ProcessExitInfo) { exits <- info }
	cfg := BinaryConfig{Name: "thunder", BinaryName: "thunder-no-such-binary", ChainLayer: 2}

	pid, err := pm.StartWithOptions(context.Background(), cfg, []string{"--network=regtest"}, nil, ProcessStartOptions{})
	require.NoError(t, err, "an app run needs no binary on disk")
	require.Zero(t, pid)
	require.True(t, pm.IsRunning("thunder"))

	runs := pm.AppRuns.Runs()
	require.Len(t, runs, 1)
	run := runs[0]
	require.Equal(t, []string{"--network=regtest", "--datadir=" + config.ThunderDirs.RootDir()}, run.Args)
	require.Equal(t, binaryLogPath(dir, "thunder", "stdout"), run.LogPath)

	require.NoError(t, os.WriteFile(run.LogPath, []byte("node is up\n"), 0o644))
	require.Eventually(t, func() bool {
		for _, entry := range pm.Get("thunder").RecentLogs(10) {
			if strings.Contains(entry.Line, "node is up") {
				return true
			}
		}
		return false
	}, 5*time.Second, 20*time.Millisecond, "the tail reads the run's log file")

	stopped := make(chan error, 1)
	go func() { stopped <- pm.Stop(context.Background(), "thunder", false) }()
	require.Eventually(t, func() bool {
		runs := pm.AppRuns.Runs()
		return len(runs) == 1 && runs[0].Stop
	}, 5*time.Second, 20*time.Millisecond, "the stop reaches the app")

	require.NoError(t, pm.AppRuns.Exited(run.ID, "lost the database"))
	require.NoError(t, <-stopped)
	assert.False(t, pm.IsRunning("thunder"))
	assert.Equal(t, ProcessExitInfo{Name: "thunder", ExitCode: 1, ErrMsg: "lost the database"}, <-exits)
}

func TestStatusOfAnAppRunNeedsNoDownload(t *testing.T) {
	o := newTestOrchestrator(t)
	o.SetAppRuns(NewAppRuns("thunder"))

	status := o.Status("thunder")
	assert.True(t, status.Downloaded)
	assert.False(t, status.Downloadable)
	assert.Empty(t, status.BinaryPath)

	_, err := o.Download(context.Background(), "thunder", false)
	require.ErrorContains(t, err, "runs in the app")
}
