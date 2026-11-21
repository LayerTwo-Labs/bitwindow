package orchestrator

import (
	"context"
	"crypto/rand"
	"fmt"
	"slices"
	"time"

	"github.com/LayerTwo-Labs/sidesail/sidechain-orchestrator/config"
)

// startInApp hands the binary to the app, which runs it in its own process.
// The run writes its log lines to the stdout log of a child, so the same tail reads them.
func (pm *ProcessManager) startInApp(
	ctx context.Context, cfg BinaryConfig, processName string,
	args []string, env map[string]string, opts ProcessStartOptions,
) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	logFile, err := openBinaryLog(pm.dataDir, processName, "stdout")
	if err != nil {
		return fmt.Errorf("open stdout log: %w", err)
	}
	if err := logFile.Close(); err != nil {
		return fmt.Errorf("close stdout log: %w", err)
	}
	// A child finds its datadir under the HOME of its environment. The app
	// process keeps its own HOME, so the run gets the datadir as a flag.
	if dirs, ok := config.DirConfigByName(cfg.Name); ok && !hasCLIFlag(args, "--datadir") {
		args = append(slices.Clone(args), "--datadir="+dirs.RootDir())
	}
	id, exited, err := pm.AppRuns.Start(processName, args, env, binaryLogPath(pm.dataDir, processName, "stdout"))
	if err != nil {
		return fmt.Errorf("start %s: %w", processName, err)
	}

	runtimeConfig := cfg
	runtimeConfig.Name = processName
	proc := &ManagedProcess{
		Config:       runtimeConfig,
		AppRunID:     id,
		Started:      time.Now(),
		ForceBackend: opts.ForceBackend,
		runID:        rand.Text(),
		logs:         make([]LogEntry, 0, 256),
		exitCh:       make(chan struct{}),
	}
	pm.mu.Lock()
	pm.processes[processName] = proc
	delete(pm.lastExited, processName)
	pm.mu.Unlock()

	proc.addLog(LogEntry{
		Timestamp: time.Now(),
		Stream:    "marker",
		Line:      fmt.Sprintf("=== %s started in the app (run %s) ===", processName, id),
	})

	stopTail := make(chan struct{})
	stdoutDone := pm.tailBinaryLog(proc, processName, "stdout", 0, stopTail, pm.startupLogCapture(cfg, processName), nil)

	go func() {
		runErr := <-exited
		close(stopTail)
		<-stdoutDone

		exitCode := 0
		errMsg := ""
		if runErr != nil {
			exitCode = 1
			errMsg = runErr.Error()
		}
		proc.mu.Lock()
		proc.exitCode = exitCode
		proc.exitErr = errMsg
		proc.exitDetails = errMsg
		proc.mu.Unlock()

		proc.addLog(LogEntry{
			Timestamp: time.Now(),
			Stream:    "marker",
			Line:      fmt.Sprintf("=== %s exited (code %d) ===", processName, exitCode),
		})

		pm.mu.Lock()
		delete(pm.processes, processName)
		pm.lastExited[processName] = proc
		pm.mu.Unlock()

		pm.log.Info().Str("binary", processName).Str("run", id).Str("error", errMsg).Msg("app run exited")

		proc.closeExit()
		if pm.OnExit != nil {
			pm.OnExit(ProcessExitInfo{Name: processName, ExitCode: exitCode, ErrMsg: errMsg})
		}
	}()

	pm.log.Info().Str("binary", processName).Str("run", id).Msg("asked the app to start")
	return nil
}

// stopInApp asks the app to stop the run and waits for its exit. An app run
// cannot get a kill signal, so a forced stop waits the same way.
func (pm *ProcessManager) stopInApp(name string, proc *ManagedProcess) error {
	pm.log.Info().Str("binary", name).Str("run", proc.AppRunID).Msg("asking the app to stop")
	if err := pm.AppRuns.Stop(proc.AppRunID); err != nil {
		return fmt.Errorf("stop %s: %w", name, err)
	}
	select {
	case <-proc.exitCh:
		return nil
	case <-time.After(appRunStopTimeout):
		return fmt.Errorf("stop %s: the app did not stop it in %s", name, appRunStopTimeout)
	}
}

// appRunStopTimeout covers a node that writes its database to disk before it exits.
const appRunStopTimeout = 60 * time.Second
