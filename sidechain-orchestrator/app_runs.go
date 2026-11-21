package orchestrator

import (
	"context"
	"crypto/rand"
	"errors"
	"fmt"
	"slices"
	"strings"
	"sync"
)

// AppRun is one run of a binary that the app holds in its own process.
type AppRun struct {
	ID   string
	Name string
	Args []string
	Env  map[string]string
	// LogPath is the file that the run writes its log lines to.
	LogPath string
	// Stop is true after the orchestrator asks the app to stop the run.
	Stop bool
}

// AppRuns gives the app the binaries that it runs in its own process. A phone
// cannot start a child process, so the app starts each run it gets from Watch
// and reports the exit with Exited.
type AppRuns struct {
	names   map[string]bool
	mu      sync.Mutex
	runs    map[string]*appRun
	changed changeBroadcast
}

type appRun struct {
	AppRun
	exited chan error
}

// NewAppRuns returns the app runs of the binaries names.
func NewAppRuns(names ...string) *AppRuns {
	set := make(map[string]bool, len(names))
	for _, name := range names {
		set[name] = true
	}
	return &AppRuns{names: set, runs: map[string]*appRun{}}
}

// Hosts reports whether the app runs the binary name.
func (a *AppRuns) Hosts(name string) bool {
	return a != nil && a.names[name]
}

// Start asks the app to run name. The channel gets the exit error of the run,
// nil for a clean exit.
func (a *AppRuns) Start(name string, args []string, env map[string]string, logPath string) (string, <-chan error, error) {
	if !a.Hosts(name) {
		return "", nil, fmt.Errorf("the app does not run %s", name)
	}
	a.mu.Lock()
	defer a.mu.Unlock()
	for _, run := range a.runs {
		if run.Name == name {
			return "", nil, fmt.Errorf("the app runs %s already", name)
		}
	}
	run := &appRun{
		AppRun: AppRun{
			ID:      rand.Text(),
			Name:    name,
			Args:    slices.Clone(args),
			Env:     env,
			LogPath: logPath,
		},
		exited: make(chan error, 1),
	}
	a.runs[run.ID] = run
	a.changed.notify()
	return run.ID, run.exited, nil
}

// Stop asks the app to stop the run id.
func (a *AppRuns) Stop(id string) error {
	a.mu.Lock()
	defer a.mu.Unlock()
	run, ok := a.runs[id]
	if !ok {
		return fmt.Errorf("no app run %s", id)
	}
	run.Stop = true
	a.changed.notify()
	return nil
}

// ErrUnknownAppRun reports an exit of a run that the orchestrator did not ask for.
var ErrUnknownAppRun = errors.New("unknown app run")

// Exited records that the run id ended. An empty errMsg is a clean exit.
func (a *AppRuns) Exited(id, errMsg string) error {
	a.mu.Lock()
	defer a.mu.Unlock()
	run, ok := a.runs[id]
	if !ok {
		return fmt.Errorf("%w: %s", ErrUnknownAppRun, id)
	}
	delete(a.runs, id)
	if errMsg != "" {
		run.exited <- errors.New(errMsg)
	}
	close(run.exited)
	a.changed.notify()
	return nil
}

// Runs returns the runs that did not exit, sorted by name.
func (a *AppRuns) Runs() []AppRun {
	a.mu.Lock()
	defer a.mu.Unlock()
	out := make([]AppRun, 0, len(a.runs))
	for _, run := range a.runs {
		r := run.AppRun
		r.Args = slices.Clone(r.Args)
		out = append(out, r)
	}
	slices.SortFunc(out, func(x, y AppRun) int { return strings.Compare(x.Name, y.Name) })
	return out
}

// Subscribe wakes the channel when the runs change. The channel lives until ctx is done.
func (a *AppRuns) Subscribe(ctx context.Context) <-chan struct{} {
	return a.changed.subscribe(ctx)
}
