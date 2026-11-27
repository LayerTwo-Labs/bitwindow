package misc

import (
	"cmp"
	"context"
	"database/sql"
	"errors"
	"fmt"
	"slices"
	"strings"
	"time"

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

// listOPReturnLimit is the cap for the gRPC ListOPReturn handler.
const listOPReturnLimit = 1000

var opReturnSorts = map[miscv1.OPReturnSort]opreturns.SortColumn{
	miscv1.OPReturnSort_OP_RETURN_SORT_UNSPECIFIED: opreturns.SortByTime,
	miscv1.OPReturnSort_OP_RETURN_SORT_TIME:        opreturns.SortByTime,
	miscv1.OPReturnSort_OP_RETURN_SORT_HEIGHT:      opreturns.SortByHeight,
	miscv1.OPReturnSort_OP_RETURN_SORT_FEE:         opreturns.SortByFee,
	miscv1.OPReturnSort_OP_RETURN_SORT_TXID:        opreturns.SortByTxID,
	miscv1.OPReturnSort_OP_RETURN_SORT_MESSAGE:     opreturns.SortByMessage,
}

// ListOPReturn implements miscv1connect.MiscServiceHandler.
func (s *Server) ListOPReturn(ctx context.Context, req *miscv1.ListOPReturnRequest) (*miscv1.ListOPReturnResponse, error) {
	sort, ok := opReturnSorts[req.Sort]
	if !ok {
		return nil, connect.NewError(connect.CodeInvalidArgument, fmt.Sprintf("unknown sort %d", req.Sort))
	}
	filter := opreturns.Filter{
		Search:    strings.TrimSpace(req.Search),
		Sort:      sort,
		Ascending: req.Ascending,
	}
	if req.From != nil {
		filter.From = req.From.AsTime()
	}
	if req.To != nil {
		filter.To = req.To.AsTime()
	}

	opReturns, err := opreturns.Query(ctx, s.database, filter, listOPReturnLimit)
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
		Message:    opReturn.Message(),
		Txid:       opReturn.TxID,
		Vout:       opReturn.Vout,
		Height:     height,
		CreateTime: timestamppb.New(lo.FromPtr(opReturn.CreatedAt)),
		FeeSats:    int64(opReturn.Fee),
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

	storyBytes, err := storyPayload(topicID, req.Headline, req.Content, opreturns.StoryOptions{
		URL:     req.Url,
		Lang:    req.Lang,
		Subtype: req.Subtype,
		NSFW:    req.Nsfw,
	})
	if err != nil {
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

// storyPayload checks the headline and encodes the bytes that a story puts in
// the OP_RETURN.
func storyPayload(topic opreturns.TopicID, headline, content string, opts opreturns.StoryOptions) ([]byte, error) {
	if strings.TrimSpace(headline) == "" {
		return nil, errors.New("headline must be set")
	}
	if len([]byte(headline)) > 64 {
		return nil, errors.New("headline cannot be longer than 64 bytes")
	}
	return opreturns.EncodeNewsMessageWithOptions(topic, headline, content, opts)
}

// EstimateNewsFee implements miscv1connect.MiscServiceHandler. It encodes the
// payload of the action, and the active wallet prices the send as it builds it.
func (s *Server) EstimateNewsFee(ctx context.Context, req *miscv1.EstimateNewsFeeRequest) (*miscv1.EstimateNewsFeeResponse, error) {
	payload, err := newsPayloadFor(req)
	if err != nil {
		return nil, connect.NewError(connect.CodeInvalidArgument, err.Error()).WithCause(err)
	}

	feeSats, vsize, err := s.walletEngine.PreviewOpReturn(ctx, payload)
	if err != nil {
		return nil, fmt.Errorf("estimate news fee: %w", err)
	}
	if feeSats <= 0 || vsize <= 0 {
		return nil, fmt.Errorf("estimate news fee: the wallet gave fee %d sats and size %d vB", feeSats, vsize)
	}

	return &miscv1.EstimateNewsFeeResponse{
		Vsize:          uint64(vsize),
		FeeSatPerVbyte: float64(feeSats) / float64(vsize),
		FeeSats:        uint64(feeSats),
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
			TLVs: commentTLVs(&miscv1.CommentNewsRequest{Body: req.Body, Url: req.Url, Lang: req.Lang}),
		})

	case miscv1.NewsAction_NEWS_ACTION_STORY:
		return storyPayload(opreturns.TopicID{}, req.Headline, req.Body, opreturns.StoryOptions{
			URL:     req.Url,
			Lang:    req.Lang,
			Subtype: req.Subtype,
			NSFW:    req.Nsfw,
		})

	case miscv1.NewsAction_NEWS_ACTION_TOPIC:
		return topicPayload(opreturns.TopicID{}, req.TopicName, req.RetentionDays)

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
	topicCreationBytes, err := topicPayload(topicID, req.Name, req.RetentionDays)
	if err != nil {
		return nil, connect.NewError(connect.CodeInvalidArgument, err.Error()).WithCause(err)
	}

	exists, err := opreturns.TopicExists(ctx, s.database, topicID)
	if err != nil {
		return nil, err
	}
	if exists {
		err := errors.New("topic already exists")
		return nil, connect.NewError(connect.CodeAlreadyExists, err.Error()).WithCause(err)
	}

	txid, err := s.walletEngine.BroadcastOpReturn(ctx, topicCreationBytes, 0, 0)
	if err != nil {
		return nil, fmt.Errorf("broadcast topic creation: %w", err)
	}
	if err := opreturns.SetTopicSubscribed(ctx, s.database, topicID, true); err != nil {
		return nil, fmt.Errorf("subscribe to topic %s of txid %s: %w", topicID, txid, err)
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

// topicPayload checks the title and the retention, and encodes the bytes that
// a topic creation puts in the OP_RETURN.
func topicPayload(topic opreturns.TopicID, name string, retentionDays int32) ([]byte, error) {
	if retentionDays < 0 || retentionDays > 255 {
		return nil, errors.New("retention days must be between 0 and 255")
	}
	if strings.TrimSpace(name) == "" {
		return nil, errors.New("title must be set")
	}
	if len([]byte(name)) > 64 {
		return nil, errors.New("title cannot be longer than 64 bytes")
	}
	return opreturns.EncodeTopicCreationMessageNewFormat(topic, name, retentionDays)
}

// ListTopics implements miscv1connect.MiscServiceHandler.
func (s *Server) ListTopics(ctx context.Context, req *emptypb.Empty) (*miscv1.ListTopicsResponse, error) {
	topics, err := subscribedTopics(ctx, s.database)
	if err != nil {
		return nil, err
	}

	return &miscv1.ListTopicsResponse{
		Topics: lo.Map(topics, topicToProto),
	}, nil
}

// ListChainTopics implements miscv1connect.MiscServiceHandler.
func (s *Server) ListChainTopics(ctx context.Context, req *emptypb.Empty) (*miscv1.ListTopicsResponse, error) {
	topics, err := opreturns.ListTopics(ctx, s.database)
	if err != nil {
		return nil, err
	}

	return &miscv1.ListTopicsResponse{
		Topics: lo.Map(topics, topicToProto),
	}, nil
}

// SetTopicSubscribed implements miscv1connect.MiscServiceHandler.
func (s *Server) SetTopicSubscribed(ctx context.Context, req *miscv1.SetTopicSubscribedRequest) (*emptypb.Empty, error) {
	topicID, err := opreturns.ValidNewsTopicID(req.Topic)
	if err != nil {
		return nil, connect.NewError(connect.CodeInvalidArgument, err.Error()).WithCause(err)
	}
	if req.Subscribed {
		exists, err := opreturns.TopicExists(ctx, s.database, topicID)
		if err != nil {
			return nil, err
		}
		if !exists {
			err := fmt.Errorf("no topic %s is in a block or in the mempool", topicID)
			return nil, connect.NewError(connect.CodeNotFound, err.Error()).WithCause(err)
		}
	}
	if err := opreturns.SetTopicSubscribed(ctx, s.database, topicID, req.Subscribed); err != nil {
		return nil, err
	}
	return &emptypb.Empty{}, nil
}

func subscribedTopics(ctx context.Context, db *sql.DB) ([]opreturns.Topic, error) {
	topics, err := opreturns.ListTopics(ctx, db)
	if err != nil {
		return nil, err
	}
	return lo.Filter(topics, func(t opreturns.Topic, _ int) bool { return t.Subscribed }), nil
}

func topicToProto(topic opreturns.Topic, _ int) *miscv1.Topic {
	out := &miscv1.Topic{
		Id:            topic.ID,
		Topic:         topic.Topic.String(),
		Name:          topic.Name,
		Confirmed:     topic.Confirmed,
		Txid:          topic.Txid,
		RetentionDays: topic.RetentionDays,
		Subscribed:    topic.Subscribed,
	}
	if !topic.CreatedAt.IsZero() {
		out.CreateTime = timestamppb.New(topic.CreatedAt)
	}
	return out
}

// coinNewsPerTopic is the number of current stories ListCoinNews returns for
// each topic. It returns the same number of outdated stories.
const coinNewsPerTopic = 100

// ListCoinNews implements miscv1connect.MiscServiceHandler.
func (s *Server) ListCoinNews(ctx context.Context, req *miscv1.ListCoinNewsRequest) (*miscv1.ListCoinNewsResponse, error) {
	known, err := opreturns.ListTopics(ctx, s.database)
	if err != nil {
		return nil, err
	}
	subscribed := lo.Filter(known, func(t opreturns.Topic, _ int) bool { return t.Subscribed })
	topics := lo.Map(subscribed, func(t opreturns.Topic, _ int) opreturns.TopicID { return t.Topic })
	if req.Topic != nil {
		topicID, err := opreturns.ValidNewsTopicID(*req.Topic)
		if err != nil {
			return nil, connect.NewError(connect.CodeInvalidArgument, err.Error()).WithCause(err)
		}
		topics = []opreturns.TopicID{topicID}
	}
	retention := lo.SliceToMap(known, func(t opreturns.Topic) (opreturns.TopicID, int32) { return t.Topic, t.RetentionDays })
	pending, err := opreturns.ListPendingCoinNews(ctx, s.database)
	if err != nil {
		return nil, err
	}

	var out []*miscv1.CoinNews
	for _, topic := range topics {
		news, err := s.confirmedCoinNews(ctx, topic, retention[topic])
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
		outdated, current := lo.FilterReject(news, func(n *miscv1.CoinNews, _ int) bool { return n.Outdated })
		out = append(out, current[:min(len(current), coinNewsPerTopic)]...)
		out = append(out, outdated[:min(len(outdated), coinNewsPerTopic)]...)
	}
	rankCoinNews(out)
	return &miscv1.ListCoinNewsResponse{CoinNews: out}, nil
}

// remoteCoinNewsPages is the number of indexer pages that one topic can take.
const remoteCoinNewsPages = 10

// confirmedCoinNews returns the stories of one topic, from the network's
// indexer, or from the local index when the network publishes no indexer.
func (s *Server) confirmedCoinNews(ctx context.Context, topic opreturns.TopicID, retentionDays int32) ([]*miscv1.CoinNews, error) {
	news, err := s.remoteCoinNewsOf(ctx, topic, retentionDays)
	switch {
	case errors.Is(err, engines.ErrNoIndexer):
	case err != nil:
		return nil, connect.NewError(connect.CodeUnavailable, fmt.Sprintf("read coin news indexer: %s", err)).WithCause(err)
	default:
		return news, nil
	}

	local, err := opreturns.ListCoinNews(ctx, s.database)
	if err != nil {
		return nil, fmt.Errorf("list coin news: %w", err)
	}
	local = lo.Filter(local, func(n opreturns.CoinNews, _ int) bool { return n.Topic == topic })
	return lo.Map(local, coinNewsToProto), nil
}

// remoteCoinNewsOf reads the indexer by fee, page after page, until it holds
// coinNewsPerTopic current stories. The indexer does not know the retention,
// so outdated stories with a high fee come before the current ones.
func (s *Server) remoteCoinNewsOf(ctx context.Context, topic opreturns.TopicID, retentionDays int32) ([]*miscv1.CoinNews, error) {
	now := time.Now()
	var news []*miscv1.CoinNews
	current := 0
	for page := range uint32(remoteCoinNewsPages) {
		items, err := s.remoteCoinNews.ListFrontPage(ctx, topic.String(), coinNewsPerTopic, page*coinNewsPerTopic)
		if err != nil {
			return nil, err
		}
		for i, item := range items {
			story := remoteCoinNewsToProto(item, i)
			story.Outdated = opreturns.Outdated(item.BlockTime, retentionDays, now)
			if !story.Outdated {
				current++
			}
			news = append(news, story)
		}
		if current >= coinNewsPerTopic || len(items) < coinNewsPerTopic {
			break
		}
	}
	return news, nil
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
		Outdated:   coinNews.Outdated,
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
	pending, err := opreturns.ListPendingComments(ctx, s.database)
	if err != nil {
		return nil, fmt.Errorf("list comments: %w", err)
	}
	return &miscv1.ListCommentsResponse{
		Comments: lo.Map(cnstore.WithPending(root, comments, pending), commentToProto),
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
		Pending:    c.Pending,
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
