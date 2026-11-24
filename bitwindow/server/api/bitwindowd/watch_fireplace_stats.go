package bitwindowd

import (
	"context"
	"time"

	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/emptypb"

	pb "github.com/LayerTwo-Labs/sidesail/bitwindow/server/gen/bitwindowd/v1"
	rpc "github.com/LayerTwo-Labs/sidesail/bitwindow/server/gen/bitwindowd/v1/bitwindowdv1connect"
	"github.com/LayerTwo-Labs/sidesail/sidechain-orchestrator/watch"
)

// fireplaceStatsRecheckInterval is long: a new block and the window edge wake the stream.
const fireplaceStatsRecheckInterval = time.Hour

func (s *Server) WatchFireplaceStats(ctx context.Context, _ *emptypb.Empty, stream rpc.BitwindowdServiceWatchFireplaceStatsServerStream) error {
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()

	var tip <-chan struct{}
	if s.tipChanged != nil {
		tip = s.tipChanged(ctx)
	}
	changed := make(chan struct{}, 1)
	edges := make(chan time.Time, 1)
	go func() {
		var edge <-chan time.Time
		for {
			select {
			case <-ctx.Done():
				return
			case at := <-edges:
				edge = nil
				if !at.IsZero() {
					edge = time.After(time.Until(at))
				}
				continue
			case <-tip:
			case <-edge:
				edge = nil
			}
			select {
			case changed <- struct{}{}:
			default:
			}
		}
	}()

	read := func() (*pb.GetFireplaceStatsResponse, error) {
		stats, next, err := s.fireplaceStats(ctx, time.Now())
		if err != nil {
			return nil, err
		}
		// Only this read sends, so the drain leaves room for the newest edge.
		select {
		case <-edges:
		default:
		}
		edges <- next
		return stats, nil
	}

	return watch.Changes(ctx, changed, fireplaceStatsRecheckInterval, syncInfoHeartbeatInterval,
		read,
		func(a, b *pb.GetFireplaceStatsResponse) bool { return proto.Equal(a, b) },
		func(stats *pb.GetFireplaceStatsResponse) error {
			return stream.Send(&pb.WatchFireplaceStatsResponse{Stats: stats})
		},
		func() error { return stream.Send(&pb.WatchFireplaceStatsResponse{Heartbeat: true}) },
	)
}
