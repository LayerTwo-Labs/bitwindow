package api

import (
	"context"
	"errors"

	"connectrpc.com/connect/v2"
	"google.golang.org/protobuf/proto"

	orchestrator "github.com/LayerTwo-Labs/sidesail/sidechain-orchestrator"
	pb "github.com/LayerTwo-Labs/sidesail/sidechain-orchestrator/gen/orchestrator/v1"
	rpc "github.com/LayerTwo-Labs/sidesail/sidechain-orchestrator/gen/orchestrator/v1/orchestratorv1connect"
	"github.com/LayerTwo-Labs/sidesail/sidechain-orchestrator/watch"
)

func (h *Handler) appRuns() (*orchestrator.AppRuns, error) {
	runs := h.orch.AppRuns()
	if runs == nil {
		return nil, connect.Errorf(connect.CodeFailedPrecondition, "this orchestrator starts every binary as a child process")
	}
	return runs, nil
}

func (h *Handler) WatchAppRuns(
	ctx context.Context, _ *pb.WatchAppRunsRequest, stream rpc.OrchestratorServiceWatchAppRunsServerStream,
) error {
	runs, err := h.appRuns()
	if err != nil {
		return err
	}
	changed := runs.Subscribe(ctx)
	read := func() ([]*pb.AppRun, error) {
		out := []*pb.AppRun{}
		for _, run := range runs.Runs() {
			out = append(out, &pb.AppRun{
				Id:      run.ID,
				Name:    run.Name,
				Args:    run.Args,
				Env:     run.Env,
				LogPath: run.LogPath,
				Stop:    run.Stop,
			})
		}
		return out, nil
	}
	same := func(a, b []*pb.AppRun) bool {
		if len(a) != len(b) {
			return false
		}
		for i := range a {
			if !proto.Equal(a[i], b[i]) {
				return false
			}
		}
		return true
	}
	return watch.Changes(ctx, changed, binariesRecheckInterval, WatchHeartbeatInterval, read, same,
		func(out []*pb.AppRun) error { return stream.Send(&pb.WatchAppRunsResponse{Runs: out}) },
		func() error { return stream.Send(&pb.WatchAppRunsResponse{Heartbeat: true}) },
	)
}

func (h *Handler) ReportAppRunExit(
	_ context.Context, req *pb.ReportAppRunExitRequest,
) (*pb.ReportAppRunExitResponse, error) {
	runs, err := h.appRuns()
	if err != nil {
		return nil, err
	}
	if err := runs.Exited(req.Id, req.Error); err != nil {
		if errors.Is(err, orchestrator.ErrUnknownAppRun) {
			return nil, connect.NewError(connect.CodeNotFound, err.Error())
		}
		return nil, err
	}
	return &pb.ReportAppRunExitResponse{}, nil
}
