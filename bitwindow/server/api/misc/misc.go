package misc

import (
	"cmp"
	"context"
	"database/sql"
	"errors"
	"fmt"
	"math"
	"slices"
	"strings"

	connectv1 "connectrpc.com/connect"
	"connectrpc.com/connect/v2"
	corepb "github.com/barebitcoin/btc-buf/gen/bitcoin/bitcoind/v1alpha"
	corerpc "github.com/barebitcoin/btc-buf/gen/bitcoin/bitcoind/v1alpha/bitcoindv1alphaconnect"
	"github.com/btcsuite/btcd/btcec/v2/schnorr"
	"github.com/rs/zerolog"
	"github.com/samber/lo"
	"google.golang.org/protobuf/types/known/emptypb"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/LayerTwo-Labs/sidesail/bitwindow/server/engines"
	miscv1 "github.com/LayerTwo-Labs/sidesail/bitwindow/server/gen/misc/v1"
	rpc "github.com/LayerTwo-Labs/sidesail/bitwindow/server/gen/misc/v1/miscv1connect"
	cnstore "github.com/LayerTwo-Labs/sidesail/bitwindow/server/models/coinnews"
	"github.com/LayerTwo-Labs/sidesail/bitwindow/server/models/opreturns"
	"github.com/LayerTwo-Labs/sidesail/bitwindow/server/models/timestamps"
	service "github.com/LayerTwo-Labs/sidesail/bitwindow/server/service"
	codec "github.com/LayerTwo-Labs/sidesail/coinnews/codec"
)

var _ rpc.MiscServiceHandler = new(Server)

// New creates a new misc Server.
func New(
	database *sql.DB,
	timestampEngine *engines.TimestampEngine,
	bitcoind *service.Service[corerpc.BitcoinServiceClient],
	walletEngine *engines.WalletEngine,
	remoteCoinNews engines.RemoteCoinNews,
) *Server {
	return &Server{
		database:        database,
		timestampEngine: timestampEngine,
		bitcoind:        bitcoind,
		walletEngine:    walletEngine,
		remoteCoinNews:  remoteCoinNews,
	}
}

type Server struct {
	database        *sql.DB
	timestampEngine *engines.TimestampEngine
	bitcoind        *service.Service[corerpc.BitcoinServiceClient]
	walletEngine    *engines.WalletEngine
	remoteCoinNews  engines.RemoteCoinNews
}

// listOPReturnLimit is the cap for the gRPC ListOPReturn handler. The
// UI is the only consumer and only renders the most-recent N; without
// a cap each poll dragged every row in the table back through the wire.
const listOPReturnLimit = 1000

// ListOPReturn implements miscv1connect.MiscServiceHandler.
func (s *Server) ListOPReturn(ctx context.Context, req *emptypb.Empty) (*miscv1.ListOPReturnResponse, error) {
	opReturns, err := opreturns.List(ctx, s.database, listOPReturnLimit)
	if err != nil {
		return nil, err
	}

	return &miscv1.ListOPReturnResponse{
		OpReturns: lo.Map(opReturns, opReturnToProto),
	}, nil
}

func opReturnToProto(opReturn opreturns.OPReturn, _ int) *miscv1.OPReturn {
	var height *int32
	if opReturn.Height != nil {
		height = lo.ToPtr(int32(*opReturn.Height))
	}
	return &miscv1.OPReturn{
		Id:         opReturn.ID,
		Message:    opreturns.OPReturnToReadable(opReturn.Data),
		Txid:       opReturn.TxID,
		Vout:       opReturn.Vout,
		Height:     height,
		CreateTime: timestamppb.New(lo.FromPtr(opReturn.CreatedAt)),
	}
}

// BroadcastNews implements miscv1connect.MiscServiceHandler.
func (s *Server) BroadcastNews(ctx context.Context, req *miscv1.BroadcastNewsRequest) (*miscv1.BroadcastNewsResponse, error) {
	if req.Topic == "" {
		err := errors.New("topic must be set")
		return nil, connect.NewError(connect.CodeInvalidArgument, err.Error()).WithCause(err)
	}
	topicID, err := opreturns.ValidNewsTopicID(req.Topic)
	if err != nil {
		return nil, connect.NewError(connect.CodeInvalidArgument, err.Error()).WithCause(err)
	}

	if strings.TrimSpace(req.Headline) == "" {
		err := errors.New("headline must be set")
		return nil, connect.NewError(connect.CodeInvalidArgument, err.Error()).WithCause(err)
	}
	if len([]byte(req.Headline)) > 64 {
		err := errors.New("headline cannot be longer than 64 bytes")
		return nil, connect.NewError(connect.CodeInvalidArgument, err.Error()).WithCause(err)
	}
	exists, err := opreturns.TopicExists(ctx, s.database, topicID)
	if err != nil {
		return nil, fmt.Errorf("check if topic exists: %w", err)
	}
	if !exists {
		err := errors.New("topic does not exist")
		return nil, connect.NewError(connect.CodeInvalidArgument, err.Error()).WithCause(err)
	}

	storyBytes, err := opreturns.EncodeNewsMessageWithOptions(topicID, req.Headline, req.Content, opreturns.StoryOptions{
		URL:     req.Url,
		Lang:    req.Lang,
		Subtype: req.Subtype,
		NSFW:    req.Nsfw,
	})
	if err != nil {
		return nil, connect.NewError(connect.CodeInvalidArgument, err.Error()).WithCause(err)
	}

	txid, err := s.walletEngine.BroadcastOpReturn(ctx, storyBytes, req.FeeSatPerVbyte, req.FeeSats)
	if err != nil {
		return nil, fmt.Errorf("broadcast news: %w", err)
	}

	log := zerolog.Ctx(ctx)
	log.Info().
		Hex("topic", topicID[:]).
		Str("headline", req.Headline).
		Str("txid", txid).
		Msg("broadcast news transaction")

	return &miscv1.BroadcastNewsResponse{
		Txid: txid,
	}, nil
}

func parseItemID(hexID, field string) (codec.ItemID, error) {
	id, err := codec.ParseItemID(hexID)
	if err != nil {
		return codec.ItemID{}, connect.NewError(connect.CodeInvalidArgument,
			fmt.Sprintf("%s must be %d-byte hex: %s", field, codec.ItemIDLen, err)).WithCause(err)
	}
	return id, nil
}

// EstimateNewsFee implements miscv1connect.MiscServiceHandler. It encodes the
// payload the action would broadcast and prices the transaction that holds it.
func (s *Server) EstimateNewsFee(ctx context.Context, req *miscv1.EstimateNewsFeeRequest) (*miscv1.EstimateNewsFeeResponse, error) {
	payload, err := newsPayloadFor(req)
	if err != nil {
		return nil, connect.NewError(connect.CodeInvalidArgument, err.Error()).WithCause(err)
	}

	rate, err := s.walletEngine.EstimateFeeRate(ctx, 6)
	if err != nil {
		return nil, connect.NewError(connect.CodeUnavailable, fmt.Sprintf("estimate fee rate: %s", err)).WithCause(err)
	}

	vsize := engines.OpReturnTxVbytes(len(payload))
	return &miscv1.EstimateNewsFeeResponse{
		Vsize:          vsize,
		FeeSatPerVbyte: rate,
		FeeSats:        uint64(math.Ceil(float64(vsize) * rate)),
	}, nil
}

// newsPayloadFor encodes the exact bytes the action would put in the OP_RETURN.
// Signatures and ids are zero — only the length matters here.
func newsPayloadFor(req *miscv1.EstimateNewsFeeRequest) ([]byte, error) {
	switch req.Action {
	case miscv1.NewsAction_NEWS_ACTION_COMMENT:
		if strings.TrimSpace(req.Body) == "" && req.Url == "" {
			return nil, errors.New("comment must have a body or url")
		}
		return codec.EncodeComment(codec.Comment{
			TLVs: commentTLVs(&miscv1.CommentNewsRequest{Body: req.Body, Url: req.Url}),
		})

	case miscv1.NewsAction_NEWS_ACTION_STORY:
		if strings.TrimSpace(req.Headline) == "" {
			return nil, errors.New("headline must be set")
		}
		return opreturns.EncodeNewsMessageWithOptions(
			opreturns.TopicID{}, req.Headline, req.Body, opreturns.StoryOptions{URL: req.Url},
		)

	case miscv1.NewsAction_NEWS_ACTION_UNSPECIFIED:
		return nil, errors.New("action must be set")

	default:
		return nil, errors.New("action must be set")
	}
}

// CreateTopic implements miscv1connect.MiscServiceHandler.
func (s *Server) CreateTopic(ctx context.Context, req *miscv1.CreateTopicRequest) (*miscv1.CreateTopicResponse, error) {
	topicID, err := opreturns.ValidNewsTopicID(req.Topic)
	if err != nil {
		return nil, connect.NewError(connect.CodeInvalidArgument, err.Error()).WithCause(err)
	}
	if req.Name == "" {
		err := errors.New("title must be set")
		return nil, connect.NewError(connect.CodeInvalidArgument, err.Error()).WithCause(err)
	}
	if len([]byte(req.Name)) > 64 {
		err := errors.New("title cannot be longer than 64 bytes")
		return nil, connect.NewError(connect.CodeInvalidArgument, err.Error()).WithCause(err)
	}

	exists, err := opreturns.TopicExists(ctx, s.database, topicID)
	if err != nil {
		return nil, err
	}

	if exists {
		err := errors.New("topic already exists")
		return nil, connect.NewError(connect.CodeInvalidArgument, err.Error()).WithCause(err)
	}

	// Calculate retention days (default to 7)
	retentionDays := req.RetentionDays
	if retentionDays == 0 {
		retentionDays = 7 // Default to 7 days
	}

	topicCreationBytes, err := opreturns.EncodeTopicCreationMessageNewFormat(topicID, req.Name, retentionDays)
	if err != nil {
		return nil, connect.NewError(connect.CodeInvalidArgument, err.Error()).WithCause(err)
	}
	txid, err := s.walletEngine.BroadcastOpReturn(ctx, topicCreationBytes, 0, 0)
	if err != nil {
		return nil, fmt.Errorf("broadcast topic creation: %w", err)
	}

	log := zerolog.Ctx(ctx)
	log.Info().
		Stringer("topic", topicID).
		Str("title", req.Name).
		Str("txid", txid).
		Msg("broadcast create topic transaction")

	return &miscv1.CreateTopicResponse{
		Txid: txid,
	}, nil
}

// ListTopics implements miscv1connect.MiscServiceHandler.
func (s *Server) ListTopics(ctx context.Context, req *emptypb.Empty) (*miscv1.ListTopicsResponse, error) {
	topics, err := opreturns.ListTopics(ctx, s.database)
	if err != nil {
		return nil, err
	}

	return &miscv1.ListTopicsResponse{
		Topics: lo.Map(topics, topicToProto),
	}, nil
}

func topicToProto(topic opreturns.Topic, _ int) *miscv1.Topic {
	out := &miscv1.Topic{
		Id:            topic.ID,
		Topic:         topic.Topic.String(),
		Name:          topic.Name,
		Confirmed:     topic.Confirmed,
		Txid:          topic.Txid,
		RetentionDays: topic.RetentionDays,
	}
	if !topic.CreatedAt.IsZero() {
		out.CreateTime = timestamppb.New(topic.CreatedAt)
	}
	return out
}

// coinNewsPerTopic is the number of stories ListCoinNews returns for each topic.
const coinNewsPerTopic = 100

// ListCoinNews implements miscv1connect.MiscServiceHandler.
func (s *Server) ListCoinNews(ctx context.Context, req *miscv1.ListCoinNewsRequest) (*miscv1.ListCoinNewsResponse, error) {
	topics, err := s.coinNewsTopics(ctx, req.Topic)
	if err != nil {
		return nil, err
	}
	pending, err := opreturns.ListPendingCoinNews(ctx, s.database)
	if err != nil {
		return nil, err
	}

	var out []*miscv1.CoinNews
	for _, topic := range topics {
		news, err := s.confirmedCoinNews(ctx, topic)
		if err != nil {
			return nil, err
		}
		confirmed := lo.SliceToMap(news, func(n *miscv1.CoinNews) (string, bool) {
			return fmt.Sprintf("%s:%d", n.Txid, n.Vout), true
		})
		for _, story := range pending {
			if story.Topic == topic && !confirmed[fmt.Sprintf("%s:%d", story.TxID, story.Vout)] {
				news = append(news, coinNewsToProto(story, 0))
			}
		}
		rankCoinNews(news)
		out = append(out, news[:min(len(news), coinNewsPerTopic)]...)
	}
	rankCoinNews(out)
	return &miscv1.ListCoinNewsResponse{CoinNews: out}, nil
}

// coinNewsTopics returns the requested topic, or each topic of this node.
func (s *Server) coinNewsTopics(ctx context.Context, topic *string) ([]opreturns.TopicID, error) {
	if topic != nil {
		topicID, err := opreturns.ValidNewsTopicID(*topic)
		if err != nil {
			return nil, connect.NewError(connect.CodeInvalidArgument, err.Error()).WithCause(err)
		}
		return []opreturns.TopicID{topicID}, nil
	}
	topics, err := opreturns.ListTopics(ctx, s.database)
	if err != nil {
		return nil, err
	}
	return lo.Map(topics, func(t opreturns.Topic, _ int) opreturns.TopicID { return t.Topic }), nil
}

// confirmedCoinNews returns the top stories of one topic, from the network's
// indexer, or from the local index when the network publishes no indexer.
func (s *Server) confirmedCoinNews(ctx context.Context, topic opreturns.TopicID) ([]*miscv1.CoinNews, error) {
	items, err := s.remoteCoinNews.ListFrontPage(ctx, topic.String(), coinNewsPerTopic)
	switch {
	case errors.Is(err, engines.ErrNoIndexer):
	case err != nil:
		return nil, connect.NewError(connect.CodeUnavailable, fmt.Sprintf("read coin news indexer: %s", err)).WithCause(err)
	default:
		return lo.Map(items, remoteCoinNewsToProto), nil
	}

	news, err := opreturns.ListCoinNews(ctx, s.database)
	if err != nil {
		return nil, fmt.Errorf("list coin news: %w", err)
	}
	news = lo.Filter(news, func(n opreturns.CoinNews, _ int) bool { return n.Topic == topic })
	return lo.Map(news[:min(len(news), coinNewsPerTopic)], coinNewsToProto), nil
}

// rankCoinNews orders stories by fee, the newest first on equal fees.
func rankCoinNews(news []*miscv1.CoinNews) {
	slices.SortStableFunc(news, func(a, b *miscv1.CoinNews) int {
		if c := cmp.Compare(b.FeeSats, a.FeeSats); c != 0 {
			return c
		}
		return b.CreateTime.AsTime().Compare(a.CreateTime.AsTime())
	})
}

func remoteCoinNewsToProto(item engines.RemoteItem, _ int) *miscv1.CoinNews {
	return &miscv1.CoinNews{
		Topic:      item.TopicHex,
		Headline:   strings.ToValidUTF8(item.Headline, ""),
		Content:    strings.ToValidUTF8(item.Body, ""),
		CreateTime: timestamppb.New(item.BlockTime),
		ItemId:     item.ItemIDHex,
		FeeSats:    item.FeeSats,
		Url:        item.URL,
		Subtype:    item.Subtype,
		Nsfw:       item.NSFW,
		Txid:       item.TxID,
		Vout:       item.Vout,
	}
}

func coinNewsToProto(coinNews opreturns.CoinNews, _ int) *miscv1.CoinNews {
	// Sanitize strings to valid UTF-8 for protobuf marshalling
	headline := strings.ToValidUTF8(coinNews.Headline, "")
	content := strings.ToValidUTF8(coinNews.Content, "")

	return &miscv1.CoinNews{
		Id:         coinNews.ID,
		Topic:      coinNews.Topic.String(),
		Headline:   headline,
		Content:    content,
		FeeSats:    int64(coinNews.Fee),
		CreateTime: timestamppb.New(lo.FromPtr(coinNews.CreatedAt)),
		ItemId:     coinNews.ItemID,
		Url:        coinNews.URL,
		Subtype:    coinNews.Subtype,
		Nsfw:       coinNews.NSFW,
		Txid:       coinNews.TxID,
		Vout:       coinNews.Vout,
	}
}

// CommentNews implements miscv1connect.MiscServiceHandler. It signs a
// CoinNews Comment (0x03) on the parent Item with this node's identity
// key and broadcasts it as an OP_RETURN. The body and optional url/lang/
// reply_quote ride in the trailing TLV section (spec §7, §10).
func (s *Server) CommentNews(ctx context.Context, req *miscv1.CommentNewsRequest) (*miscv1.CommentNewsResponse, error) {
	parent, err := parseItemID(req.ParentId, "parent_id")
	if err != nil {
		return nil, err
	}

	if strings.TrimSpace(req.Body) == "" && req.Url == "" {
		err := errors.New("comment must have a body or url")
		return nil, connect.NewError(connect.CodeInvalidArgument, err.Error()).WithCause(err)
	}

	priv, xpk, err := cnstore.LoadOrCreateIdentity(ctx, s.database)
	if err != nil {
		return nil, fmt.Errorf("comment news: load identity: %w", err)
	}

	tlvs := commentTLVs(req)
	blob, err := codec.SerialiseTLVs(tlvs)
	if err != nil {
		return nil, fmt.Errorf("comment news: serialise tlvs: %w", err)
	}
	digest := codec.CommentSigHash(parent, blob)
	sig, err := schnorr.Sign(priv, digest[:])
	if err != nil {
		return nil, fmt.Errorf("comment news: sign comment: %w", err)
	}

	comment := codec.Comment{Parent: parent, AuthorXPK: xpk, TLVs: tlvs}
	copy(comment.Sig[:], sig.Serialize())
	commentBytes, err := codec.EncodeComment(comment)
	if err != nil {
		return nil, fmt.Errorf("comment news: encode comment: %w", err)
	}

	txid, err := s.walletEngine.BroadcastOpReturn(ctx, commentBytes, req.FeeSatPerVbyte, req.FeeSats)
	if err != nil {
		return nil, fmt.Errorf("comment news: %w", err)
	}

	zerolog.Ctx(ctx).Info().
		Str("parent_id", req.ParentId).
		Str("txid", txid).
		Msg("broadcast comment transaction")

	return &miscv1.CommentNewsResponse{
		Txid: txid,
	}, nil
}

// commentTLVs builds the trailing TLV section for a comment from the
// request's optional fields, in a stable order (the signature covers
// these exact bytes).
func commentTLVs(req *miscv1.CommentNewsRequest) []codec.TLV {
	var tlvs []codec.TLV
	if body := strings.TrimSpace(req.Body); body != "" {
		tlvs = append(tlvs, codec.TLV{Tag: codec.TLVBody, Value: []byte(body)})
	}
	if req.Url != "" {
		tlvs = append(tlvs, codec.TLV{Tag: codec.TLVURL, Value: []byte(req.Url)})
	}
	if req.Lang != "" {
		tlvs = append(tlvs, codec.TLV{Tag: codec.TLVLang, Value: []byte(req.Lang)})
	}
	if req.ReplyQuote != "" {
		tlvs = append(tlvs, codec.TLV{Tag: codec.TLVReplyQuote, Value: []byte(req.ReplyQuote)})
	}
	return tlvs
}

// ListComments implements miscv1connect.MiscServiceHandler.
func (s *Server) ListComments(ctx context.Context, req *miscv1.ListCommentsRequest) (*miscv1.ListCommentsResponse, error) {
	root, err := parseItemID(req.ItemId, "item_id")
	if err != nil {
		return nil, err
	}

	comments, err := cnstore.ListThread(ctx, s.database, root)
	if err != nil {
		return nil, fmt.Errorf("list comments: %w", err)
	}
	return &miscv1.ListCommentsResponse{
		Comments: lo.Map(comments, commentToProto),
	}, nil
}

func commentToProto(c cnstore.Comment, _ int) *miscv1.Comment {
	return &miscv1.Comment{
		ItemId:     c.ItemID,
		ParentId:   c.ParentID,
		Author:     c.Author,
		Body:       strings.ToValidUTF8(c.Body, ""),
		Url:        c.URL,
		Lang:       c.Lang,
		ReplyQuote: strings.ToValidUTF8(c.ReplyQuote, ""),
		CreateTime: timestamppb.New(c.CreatedAt),
		FeeSats:    c.FeeSats,
	}
}

// TimestampFile implements miscv1connect.MiscServiceHandler.
func (s *Server) TimestampFile(ctx context.Context, req *miscv1.TimestampFileRequest) (*miscv1.TimestampFileResponse, error) {
	if req.Filename == "" {
		return nil, connect.NewError(connect.CodeInvalidArgument, "filename must be set")
	}
	if len(req.FileData) == 0 {
		return nil, connect.NewError(connect.CodeInvalidArgument, "file data must be set")
	}

	ts, err := s.timestampEngine.TimestampFile(ctx, req.Filename, req.FileData)
	if err != nil {
		return nil, fmt.Errorf("timestamp file: %w", err)
	}

	txid := ""
	if ts.TxID != nil {
		txid = *ts.TxID
	}

	return &miscv1.TimestampFileResponse{
		Id:       ts.ID,
		FileHash: ts.FileHash,
		Txid:     txid,
	}, nil
}

// ListTimestamps implements miscv1connect.MiscServiceHandler.
func (s *Server) ListTimestamps(ctx context.Context, req *emptypb.Empty) (*miscv1.ListTimestampsResponse, error) {
	tsList, err := s.timestampEngine.ListTimestamps(ctx)
	if err != nil {
		return nil, fmt.Errorf("list timestamps: %w", err)
	}

	currentBlockHeight, err := s.getCurrentBlockHeight(ctx)
	if err != nil {
		return nil, err
	}

	return &miscv1.ListTimestampsResponse{
		Timestamps: lo.Map(tsList, func(ts timestamps.FileTimestamp, _ int) *miscv1.FileTimestamp {
			return timestampToProto(ts, currentBlockHeight)
		}),
	}, nil
}

func timestampToProto(ts timestamps.FileTimestamp, currentBlockHeight int64) *miscv1.FileTimestamp {
	proto := &miscv1.FileTimestamp{
		Id:        ts.ID,
		Filename:  ts.Filename,
		FileHash:  ts.FileHash,
		Status:    string(ts.Status),
		CreatedAt: timestamppb.New(ts.CreatedAt),
	}

	if ts.TxID != nil {
		proto.Txid = ts.TxID
	}
	if ts.BlockHeight != nil {
		proto.BlockHeight = ts.BlockHeight
		if currentBlockHeight > 0 {
			proto.Confirmations = uint32(currentBlockHeight - *ts.BlockHeight + 1)
		}
	}
	if ts.ConfirmedAt != nil {
		proto.ConfirmedAt = timestamppb.New(*ts.ConfirmedAt)
	}

	return proto
}

// VerifyTimestamp implements miscv1connect.MiscServiceHandler.
func (s *Server) VerifyTimestamp(ctx context.Context, req *miscv1.VerifyTimestampRequest) (*miscv1.VerifyTimestampResponse, error) {
	if len(req.FileData) == 0 {
		return nil, connect.NewError(connect.CodeInvalidArgument, "file data must be set")
	}

	filename := ""
	if req.Filename != nil {
		filename = *req.Filename
	}

	ts, err := s.timestampEngine.VerifyTimestamp(ctx, req.FileData, filename)
	switch {
	case errors.Is(err, engines.ErrTimestampNotFound):
		return nil, connect.NewError(connect.CodeNotFound, err.Error()).WithCause(err)
	case err != nil:
		return nil, connect.NewError(connect.CodeInternal, fmt.Sprintf("verify timestamp: %s", err)).WithCause(err)
	}
	if ts.Status == timestamps.StatusFailed {
		return nil, connect.NewError(connect.CodeFailedPrecondition, "the timestamp transaction failed")
	}
	if ts.Status != timestamps.StatusConfirmed {
		return nil, connect.NewError(connect.CodeFailedPrecondition, "the timestamp is not confirmed yet")
	}

	currentBlockHeight, err := s.getCurrentBlockHeight(ctx)
	if err != nil {
		return nil, err
	}

	return &miscv1.VerifyTimestampResponse{
		Timestamp: timestampToProto(*ts, currentBlockHeight),
		Message:   fmt.Sprintf("File verified! Transaction: %s", *ts.TxID),
	}, nil
}

// getCurrentBlockHeight gives 0 in light mode, which runs no local Bitcoin Core.
func (s *Server) getCurrentBlockHeight(ctx context.Context) (int64, error) {
	if !s.walletEngine.NodeMode().RunsLocalNode(ctx) {
		return 0, nil
	}
	bitcoind, err := s.bitcoind.Get(ctx)
	if err != nil {
		return 0, err
	}
	info, err := bitcoind.GetBlockchainInfo(ctx, &connectv1.Request[corepb.GetBlockchainInfoRequest]{})
	if err != nil {
		return 0, fmt.Errorf("get blockchain info: %w", err)
	}
	return int64(info.Msg.Blocks), nil
}
