package misc_test

import (
	"bytes"
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"
	"strings"
	"testing"
	"time"

	connectv1 "connectrpc.com/connect"
	"connectrpc.com/connect/v2"
	corepb "github.com/barebitcoin/btc-buf/gen/bitcoin/bitcoind/v1alpha"
	"github.com/btcsuite/btcd/btcutil"
	"github.com/samber/lo"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.uber.org/mock/gomock"
	"google.golang.org/protobuf/types/known/emptypb"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/LayerTwo-Labs/sidesail/bitwindow/server/database"
	miscv1 "github.com/LayerTwo-Labs/sidesail/bitwindow/server/gen/misc/v1"
	miscv1connect "github.com/LayerTwo-Labs/sidesail/bitwindow/server/gen/misc/v1/miscv1connect"
	cnstore "github.com/LayerTwo-Labs/sidesail/bitwindow/server/models/coinnews"
	"github.com/LayerTwo-Labs/sidesail/bitwindow/server/models/opreturns"
	"github.com/LayerTwo-Labs/sidesail/bitwindow/server/models/timestamps"
	"github.com/LayerTwo-Labs/sidesail/bitwindow/server/tests/apitests"
	"github.com/LayerTwo-Labs/sidesail/bitwindow/server/tests/mocks"
	coinnews "github.com/LayerTwo-Labs/sidesail/coinnews/codec"
	orchpb "github.com/LayerTwo-Labs/sidesail/sidechain-orchestrator/gen/walletmanager/v1"
)

func TestService_ListOPReturn(t *testing.T) {
	t.Parallel()

	t.Run("list empty op returns", func(t *testing.T) {
		t.Parallel()

		database := database.Test(t)
		cli := miscv1connect.NewMiscServiceClient(apitests.RPC(t, database))

		resp, err := cli.ListOPReturn(t.Context(), &miscv1.ListOPReturnRequest{})
		require.NoError(t, err)
		assert.Empty(t, resp.OpReturns)
	})

	t.Run("list op returns with data", func(t *testing.T) {
		t.Parallel()

		database := database.Test(t)
		// Insert test data using the Persist function
		ctx := t.Context()
		height := uint32(100)
		err := opreturns.Persist(ctx, database, []opreturns.OPReturn{
			{
				Height: &height,
				TxID:   "txid1",
				Vout:   0,
				Data:   []byte("test message"),
				Fee:    624,
			},
		})
		require.NoError(t, err)

		cli := miscv1connect.NewMiscServiceClient(apitests.RPC(t, database))

		resp, err := cli.ListOPReturn(t.Context(), &miscv1.ListOPReturnRequest{})
		require.NoError(t, err)
		require.Len(t, resp.OpReturns, 1)
		assert.Equal(t, "test message", resp.OpReturns[0].Message)
		assert.Equal(t, "txid1", resp.OpReturns[0].Txid)
		assert.EqualValues(t, 0, resp.OpReturns[0].Vout)
		assert.EqualValues(t, 100, lo.FromPtr(resp.OpReturns[0].Height))
		assert.EqualValues(t, 624, resp.OpReturns[0].FeeSats)
	})
}

// seedOPReturns stores count rows. Row i has height 100+i, a create time i
// minutes after start, the fee i+1 and the message "bulk <i>".
func seedOPReturns(t *testing.T, db *sql.DB, start time.Time, count int) {
	t.Helper()
	rows := make([]opreturns.OPReturn, count)
	for i := range rows {
		height := uint32(100 + i)
		rows[i] = opreturns.OPReturn{
			TxID:      fmt.Sprintf("%064x", i),
			Data:      fmt.Appendf(nil, "bulk #%d;", i),
			Fee:       btcutil.Amount(i + 1),
			Height:    &height,
			CreatedAt: lo.ToPtr(start.Add(time.Duration(i) * time.Minute)),
		}
	}
	require.NoError(t, opreturns.Persist(t.Context(), db, rows))
}

func TestService_ListOPReturn_Filter(t *testing.T) {
	t.Parallel()

	start := time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)
	db := database.Test(t)
	seedOPReturns(t, db, start, 1100)
	cli := miscv1connect.NewMiscServiceClient(apitests.RPC(t, db))

	list := func(t *testing.T, req *miscv1.ListOPReturnRequest) []*miscv1.OPReturn {
		t.Helper()
		resp, err := cli.ListOPReturn(t.Context(), req)
		require.NoError(t, err)
		return resp.OpReturns
	}
	messages := func(rows []*miscv1.OPReturn) []string {
		return lo.Map(rows, func(r *miscv1.OPReturn, _ int) string { return r.Message })
	}

	t.Run("no filter gives the newest rows first, at the cap", func(t *testing.T) {
		t.Parallel()
		rows := list(t, &miscv1.ListOPReturnRequest{})
		require.Len(t, rows, 1000)
		assert.Equal(t, "bulk #1099;", rows[0].Message)
		assert.Equal(t, "bulk #100;", rows[999].Message)
	})

	t.Run("search finds a row older than the cap", func(t *testing.T) {
		t.Parallel()
		assert.Equal(t, []string{"bulk #7;"}, messages(list(t, &miscv1.ListOPReturnRequest{Search: "BULK #7;"})))
	})

	t.Run("search matches the txid", func(t *testing.T) {
		t.Parallel()
		rows := list(t, &miscv1.ListOPReturnRequest{Search: strings.ToUpper(fmt.Sprintf("%064x", 3))})
		assert.Equal(t, []string{"bulk #3;"}, messages(rows))
	})

	t.Run("search matches decoded text with no case match", func(t *testing.T) {
		t.Parallel()
		db := database.Test(t)
		require.NoError(t, opreturns.Persist(t.Context(), db, []opreturns.OPReturn{
			{TxID: "aa", Data: []byte("Blåbær ØL")},
			{TxID: "bb", Data: []byte("other")},
		}))
		cli := miscv1connect.NewMiscServiceClient(apitests.RPC(t, db))
		resp, err := cli.ListOPReturn(t.Context(), &miscv1.ListOPReturnRequest{Search: "bær øl"})
		require.NoError(t, err)
		assert.Equal(t, []string{"Blåbær ØL"}, messages(resp.OpReturns))
	})

	t.Run("ascending height starts at the oldest row", func(t *testing.T) {
		t.Parallel()
		rows := list(t, &miscv1.ListOPReturnRequest{Sort: miscv1.OPReturnSort_OP_RETURN_SORT_HEIGHT, Ascending: true})
		require.Len(t, rows, 1000)
		assert.EqualValues(t, 100, lo.FromPtr(rows[0].Height))
	})

	t.Run("descending fee starts at the highest fee", func(t *testing.T) {
		t.Parallel()
		rows := list(t, &miscv1.ListOPReturnRequest{Sort: miscv1.OPReturnSort_OP_RETURN_SORT_FEE})
		assert.EqualValues(t, 1100, rows[0].FeeSats)
	})

	t.Run("date range holds each row in it and none outside", func(t *testing.T) {
		t.Parallel()
		rows := list(t, &miscv1.ListOPReturnRequest{
			From:      timestamppb.New(start.Add(10 * time.Minute)),
			To:        timestamppb.New(start.Add(13 * time.Minute)),
			Ascending: true,
		})
		assert.Equal(t, []string{"bulk #10;", "bulk #11;", "bulk #12;"}, messages(rows))
	})

	t.Run("date range compares rows stored in another zone", func(t *testing.T) {
		t.Parallel()
		db := database.Test(t)
		oslo := time.FixedZone("CET", 3600)
		require.NoError(t, opreturns.Persist(t.Context(), db, []opreturns.OPReturn{
			{TxID: "aa", Data: []byte("in"), CreatedAt: lo.ToPtr(time.Date(2026, 1, 1, 0, 30, 0, 0, oslo))},
			{TxID: "bb", Data: []byte("out"), CreatedAt: lo.ToPtr(time.Date(2026, 1, 1, 1, 30, 0, 0, oslo))},
		}))
		cli := miscv1connect.NewMiscServiceClient(apitests.RPC(t, db))
		resp, err := cli.ListOPReturn(t.Context(), &miscv1.ListOPReturnRequest{
			From: timestamppb.New(time.Date(2025, 12, 31, 23, 0, 0, 0, time.UTC)),
			To:   timestamppb.New(time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)),
		})
		require.NoError(t, err)
		assert.Equal(t, []string{"in"}, messages(resp.OpReturns))
	})

	t.Run("message sort uses the shown text", func(t *testing.T) {
		t.Parallel()
		db := database.Test(t)
		require.NoError(t, opreturns.Persist(t.Context(), db, []opreturns.OPReturn{
			{TxID: "aa", Data: []byte("7a")},
			{TxID: "bb", Data: []byte("b")},
			{TxID: "cc", Data: []byte("c")},
		}))
		cli := miscv1connect.NewMiscServiceClient(apitests.RPC(t, db))
		resp, err := cli.ListOPReturn(t.Context(), &miscv1.ListOPReturnRequest{
			Sort: miscv1.OPReturnSort_OP_RETURN_SORT_MESSAGE, Ascending: true,
		})
		require.NoError(t, err)
		assert.Equal(t, []string{"b", "c", "z"}, messages(resp.OpReturns))
	})

	t.Run("unknown sort is an invalid argument", func(t *testing.T) {
		t.Parallel()
		_, err := cli.ListOPReturn(t.Context(), &miscv1.ListOPReturnRequest{Sort: 99})
		assert.Equal(t, connect.CodeInvalidArgument, connect.CodeOf(err))
	})
}

func TestService_BroadcastNews(t *testing.T) {
	t.Parallel()

	t.Run("broadcast news success", func(t *testing.T) {
		t.Parallel()

		ctrl := gomock.NewController(t)
		mockOrch := mocks.NewMockWalletManagerServiceClient(ctrl)
		apitests.ExpectOrchestratorReads(mockOrch)

		mockOrch.EXPECT().
			SendTransaction(gomock.Any(), gomock.Any()).
			Return(&orchpb.SendTransactionResponse{Txid: "test-txid"}, nil)

		database := database.Test(t)
		ctx := t.Context()
		topicID := validTopicID()
		seedCurrentTopic(t, ctx, database, topicID, "Test Topic", 50)

		cli := miscv1connect.NewMiscServiceClient(apitests.RPC(t, database, apitests.WithOrchestrator(mockOrch)))

		resp, err := cli.BroadcastNews(t.Context(), &miscv1.BroadcastNewsRequest{
			Topic:    topicID.String(),
			Headline: "Test News Headline",
			Content:  "https://example.com/news",
		})
		require.NoError(t, err)
		assert.NotEmpty(t, resp.Txid)
	})

	t.Run("broadcast news with empty topic", func(t *testing.T) {
		t.Parallel()

		database := database.Test(t)
		cli := miscv1connect.NewMiscServiceClient(apitests.RPC(t, database))

		_, err := cli.BroadcastNews(t.Context(), &miscv1.BroadcastNewsRequest{
			Topic:    "",
			Headline: "Test News Headline",
			Content:  "https://example.com/news",
		})
		require.ErrorContains(t, err, "topic must be set")
	})

	t.Run("broadcast news with invalid topic format", func(t *testing.T) {
		t.Parallel()

		database := database.Test(t)
		cli := miscv1connect.NewMiscServiceClient(apitests.RPC(t, database))

		_, err := cli.BroadcastNews(t.Context(), &miscv1.BroadcastNewsRequest{
			Topic:    "123456", // Too short, should be 8 hex characters (4 bytes)
			Headline: "Test News Headline",
			Content:  "https://example.com/news",
		})
		require.ErrorContains(t, err, "is not 4 bytes")
	})

	t.Run("broadcast news with empty headline", func(t *testing.T) {
		t.Parallel()

		database := database.Test(t)
		// First create a topic
		ctx := t.Context()

		topicID := validTopicID()
		seedCurrentTopic(t, ctx, database, topicID, "Test Topic", 50)

		cli := miscv1connect.NewMiscServiceClient(apitests.RPC(t, database))

		_, err := cli.BroadcastNews(t.Context(), &miscv1.BroadcastNewsRequest{
			Topic:    topicID.String(),
			Headline: "",
			Content:  "https://example.com/news",
		})
		require.ErrorContains(t, err, "headline must be set")
	})

	t.Run("broadcast news with whitespace-only headline", func(t *testing.T) {
		t.Parallel()

		database := database.Test(t)
		ctx := t.Context()
		topicID := validTopicID()
		seedCurrentTopic(t, ctx, database, topicID, "Test Topic", 50)

		cli := miscv1connect.NewMiscServiceClient(apitests.RPC(t, database))

		// Whitespace-only headlines previously passed validation, got
		// stored as spaces, and rendered blank in the UI Title column.
		for _, h := range []string{"   ", "\t", "\n", " \t "} {
			t.Run(fmt.Sprintf("%q", h), func(t *testing.T) {
				_, err := cli.BroadcastNews(t.Context(), &miscv1.BroadcastNewsRequest{
					Topic:    topicID.String(),
					Headline: h,
					Content:  "content",
				})
				require.ErrorContains(t, err, "headline must be set")
			})
		}
	})

	t.Run("broadcast news with headline too long", func(t *testing.T) {
		t.Parallel()

		database := database.Test(t)
		// First create a topic
		ctx := t.Context()
		topicID := validTopicID()
		seedCurrentTopic(t, ctx, database, topicID, "Test Topic", 50)

		cli := miscv1connect.NewMiscServiceClient(apitests.RPC(t, database))

		longHeadline := strings.Repeat("a", 65) // 65 characters, exceeds 64 limit
		_, err := cli.BroadcastNews(t.Context(), &miscv1.BroadcastNewsRequest{
			Topic:    topicID.String(),
			Headline: longHeadline,
			Content:  "https://example.com/news",
		})
		require.ErrorContains(t, err, "headline cannot be longer than 64 bytes")
	})

	t.Run("broadcast news with non-existent topic", func(t *testing.T) {
		t.Parallel()

		database := database.Test(t)
		cli := miscv1connect.NewMiscServiceClient(apitests.RPC(t, database))

		_, err := cli.BroadcastNews(t.Context(), &miscv1.BroadcastNewsRequest{
			Topic:    "87654321", // Non-existent topic (4 bytes)
			Headline: "Test News Headline",
			Content:  "https://example.com/news",
		})
		require.ErrorContains(t, err, "topic does not exist")
	})

	t.Run("broadcast news with text content", func(t *testing.T) {
		t.Parallel()

		ctrl := gomock.NewController(t)
		mockOrch := mocks.NewMockWalletManagerServiceClient(ctrl)
		apitests.ExpectOrchestratorReads(mockOrch)

		topicID := validTopicID()

		mockOrch.EXPECT().
			SendTransaction(gomock.Any(), gomock.Any()).
			Return(&orchpb.SendTransactionResponse{Txid: "test-txid"}, nil)

		database := database.Test(t)
		ctx := t.Context()
		seedCurrentTopic(t, ctx, database, topicID, "Test Topic", 50)

		cli := miscv1connect.NewMiscServiceClient(apitests.RPC(t, database, apitests.WithOrchestrator(mockOrch)))

		resp, err := cli.BroadcastNews(t.Context(), &miscv1.BroadcastNewsRequest{
			Topic:    topicID.String(),
			Headline: "Test News Headline",
			Content:  "This is the news content",
		})
		require.NoError(t, err)
		assert.NotEmpty(t, resp.Txid)
	})

	t.Run("broadcast news with hex content", func(t *testing.T) {
		t.Parallel()

		ctrl := gomock.NewController(t)
		mockOrch := mocks.NewMockWalletManagerServiceClient(ctrl)
		apitests.ExpectOrchestratorReads(mockOrch)

		mockOrch.EXPECT().
			SendTransaction(gomock.Any(), gomock.Any()).
			Return(&orchpb.SendTransactionResponse{Txid: "test-txid"}, nil)

		database := database.Test(t)
		ctx := t.Context()
		topicID := validTopicID()
		seedCurrentTopic(t, ctx, database, topicID, "Test Topic", 50)

		cli := miscv1connect.NewMiscServiceClient(apitests.RPC(t, database, apitests.WithOrchestrator(mockOrch)))

		hexContent := hex.EncodeToString([]byte("hex content"))
		resp, err := cli.BroadcastNews(t.Context(), &miscv1.BroadcastNewsRequest{
			Topic:    topicID.String(),
			Headline: "Test News Headline",
			Content:  hexContent,
		})
		require.NoError(t, err)
		assert.NotEmpty(t, resp.Txid)
	})
}

func TestService_Comments(t *testing.T) {
	t.Parallel()

	const validItemID = "0123456789abcdef01234567" // 12-byte hex

	walletReturningTxid := func(t *testing.T) *mocks.MockWalletManagerServiceClient {
		t.Helper()
		mockOrch := mocks.NewMockWalletManagerServiceClient(gomock.NewController(t))
		apitests.ExpectOrchestratorReads(mockOrch)
		mockOrch.EXPECT().
			SendTransaction(gomock.Any(), gomock.Any()).
			Return(&orchpb.SendTransactionResponse{Txid: "test-txid"}, nil).AnyTimes()
		return mockOrch
	}

	t.Run("comment rejects a short parent_id", func(t *testing.T) {
		t.Parallel()
		cli := miscv1connect.NewMiscServiceClient(apitests.RPC(t, database.Test(t)))
		_, err := cli.CommentNews(t.Context(), &miscv1.CommentNewsRequest{ParentId: "abcd", Body: "hi"})
		require.Equal(t, connect.CodeInvalidArgument, connect.CodeOf(err))
		assert.Contains(t, err.Error(), "parent_id must be")
	})

	t.Run("list comments rejects a malformed item_id", func(t *testing.T) {
		t.Parallel()
		cli := miscv1connect.NewMiscServiceClient(apitests.RPC(t, database.Test(t)))
		_, err := cli.ListComments(t.Context(), &miscv1.ListCommentsRequest{ItemId: "nothex"})
		require.Equal(t, connect.CodeInvalidArgument, connect.CodeOf(err))
		assert.Contains(t, err.Error(), "item_id must be")
	})

	t.Run("comment success", func(t *testing.T) {
		t.Parallel()
		cli := miscv1connect.NewMiscServiceClient(apitests.RPC(t, database.Test(t), apitests.WithOrchestrator(walletReturningTxid(t))))
		resp, err := cli.CommentNews(t.Context(), &miscv1.CommentNewsRequest{
			ParentId: validItemID,
			Body:     "great article",
		})
		require.NoError(t, err)
		assert.NotEmpty(t, resp.Txid)
	})

	t.Run("comment rejects empty body and url", func(t *testing.T) {
		t.Parallel()
		cli := miscv1connect.NewMiscServiceClient(apitests.RPC(t, database.Test(t)))
		_, err := cli.CommentNews(t.Context(), &miscv1.CommentNewsRequest{
			ParentId: validItemID,
			Body:     "  ",
		})
		require.ErrorContains(t, err, "body or url")
	})

	t.Run("comment fee estimate counts the url", func(t *testing.T) {
		t.Parallel()
		mockOrch := mocks.NewMockWalletManagerServiceClient(gomock.NewController(t))
		apitests.ExpectOrchestratorReads(mockOrch)
		mockOrch.EXPECT().
			EstimateFee(gomock.Any(), gomock.Any()).
			Return(&orchpb.EstimateFeeResponse{SatPerVbyte: 1}, nil).
			AnyTimes()
		cli := miscv1connect.NewMiscServiceClient(apitests.RPC(t, database.Test(t), apitests.WithOrchestrator(mockOrch)))

		estimate := func(body, url string) (*miscv1.EstimateNewsFeeResponse, error) {
			return cli.EstimateNewsFee(t.Context(), &miscv1.EstimateNewsFeeRequest{
				Action: miscv1.NewsAction_NEWS_ACTION_COMMENT,
				Body:   body,
				Url:    url,
			})
		}

		urlOnly, err := estimate("", "https://example.com/a")
		require.NoError(t, err)
		bodyOnly, err := estimate("hi", "")
		require.NoError(t, err)
		both, err := estimate("hi", "https://example.com/a")
		require.NoError(t, err)
		assert.Greater(t, both.Vsize, bodyOnly.Vsize)
		assert.Greater(t, both.Vsize, urlOnly.Vsize)

		_, err = estimate("  ", "")
		require.Equal(t, connect.CodeInvalidArgument, connect.CodeOf(err))
		assert.Contains(t, err.Error(), "body or url")
	})

	t.Run("list comments empty", func(t *testing.T) {
		t.Parallel()
		cli := miscv1connect.NewMiscServiceClient(apitests.RPC(t, database.Test(t)))
		resp, err := cli.ListComments(t.Context(), &miscv1.ListCommentsRequest{ItemId: validItemID})
		require.NoError(t, err)
		assert.Empty(t, resp.Comments)
	})
}

func TestService_CreateTopic(t *testing.T) {
	t.Parallel()

	t.Run("create topic success", func(t *testing.T) {
		t.Parallel()

		ctrl := gomock.NewController(t)
		mockOrch := mocks.NewMockWalletManagerServiceClient(ctrl)
		apitests.ExpectOrchestratorReads(mockOrch)

		mockOrch.EXPECT().
			SendTransaction(gomock.Any(), gomock.Any()).
			Return(&orchpb.SendTransactionResponse{Txid: "test-txid"}, nil)

		database := database.Test(t)
		cli := miscv1connect.NewMiscServiceClient(apitests.RPC(t, database, apitests.WithOrchestrator(mockOrch)))

		resp, err := cli.CreateTopic(t.Context(), &miscv1.CreateTopicRequest{
			Topic: "deadbeef",
			Name:  "Test Topic",
		})
		require.NoError(t, err)
		assert.NotEmpty(t, resp.Txid)
	})

	t.Run("create topic with empty topic", func(t *testing.T) {
		t.Parallel()

		database := database.Test(t)
		cli := miscv1connect.NewMiscServiceClient(apitests.RPC(t, database))

		_, err := cli.CreateTopic(t.Context(), &miscv1.CreateTopicRequest{
			Topic: "",
			Name:  "Test Topic",
		})
		require.ErrorContains(t, err, "topic ID is empty")
	})

	t.Run("create topic with invalid format", func(t *testing.T) {
		t.Parallel()

		database := database.Test(t)
		cli := miscv1connect.NewMiscServiceClient(apitests.RPC(t, database))

		_, err := cli.CreateTopic(t.Context(), &miscv1.CreateTopicRequest{
			Topic: "123456", // Too short, should be 8 hex characters (4 bytes)
			Name:  "Test Topic",
		})
		require.ErrorContains(t, err, "is not 4 bytes")
	})

	t.Run("create topic with empty name", func(t *testing.T) {
		t.Parallel()

		database := database.Test(t)
		cli := miscv1connect.NewMiscServiceClient(apitests.RPC(t, database))

		_, err := cli.CreateTopic(t.Context(), &miscv1.CreateTopicRequest{
			Topic: validTopicID().String(),
			Name:  "",
		})
		require.ErrorContains(t, err, "title must be set")
	})

	t.Run("create topic with name too long", func(t *testing.T) {
		t.Parallel()

		database := database.Test(t)
		cli := miscv1connect.NewMiscServiceClient(apitests.RPC(t, database))

		longName := bytes.Repeat(make([]byte, 65), 64) // 65 bytes, exceeds 64 limit
		_, err := cli.CreateTopic(t.Context(), &miscv1.CreateTopicRequest{
			Topic: validTopicID().String(),
			Name:  string(longName),
		})
		require.ErrorContains(t, err, "title cannot be longer than 64 bytes")
	})

	t.Run("create duplicate topic", func(t *testing.T) {
		t.Parallel()

		database := database.Test(t)
		ctx := t.Context()
		topicID := validTopicID()
		seedCurrentTopic(t, ctx, database, topicID, "Existing Topic", 50)

		cli := miscv1connect.NewMiscServiceClient(apitests.RPC(t, database))

		_, err := cli.CreateTopic(t.Context(), &miscv1.CreateTopicRequest{
			Topic: topicID.String(),
			Name:  "New Topic",
		})
		require.ErrorContains(t, err, "topic already exists")
	})
}

func TestService_ListTopics(t *testing.T) {
	t.Parallel()

	t.Run("list default topics", func(t *testing.T) {
		t.Parallel()

		database := database.Test(t)
		cli := miscv1connect.NewMiscServiceClient(apitests.RPC(t, database))

		resp, err := cli.ListTopics(t.Context(), &emptypb.Empty{})
		require.NoError(t, err)
		// A fresh DB ships the two bootstrap default topics.
		require.Len(t, resp.Topics, 2)
		assert.True(t, lo.ContainsBy(resp.Topics, func(tp *miscv1.Topic) bool { return tp.Name == "US Weekly" }))
		assert.True(t, lo.ContainsBy(resp.Topics, func(tp *miscv1.Topic) bool { return tp.Name == "Japan Weekly" }))
	})

	t.Run("list topics with data", func(t *testing.T) {
		t.Parallel()

		database := database.Test(t)
		ctx := t.Context()
		topicID1 := validTopicID()
		seedCurrentTopic(t, ctx, database, topicID1, "Norway Weekly", 50)
		topicID2 := validTopicID()
		seedCurrentTopic(t, ctx, database, topicID2, "Bitcoin Weekly", 51)

		cli := miscv1connect.NewMiscServiceClient(apitests.RPC(t, database))

		resp, err := cli.ListTopics(t.Context(), &emptypb.Empty{})
		require.NoError(t, err)
		require.Len(t, resp.Topics, 4) // 2 seeded + 2 bootstrap defaults

		assert.True(t, lo.ContainsBy(resp.Topics, func(topic *miscv1.Topic) bool {
			return topic.Topic == topicID1.String()
		}), "topic 1 not found")
		assert.True(t, lo.ContainsBy(resp.Topics, func(topic *miscv1.Topic) bool {
			return topic.Topic == topicID2.String()
		}), "topic 2 not found")
	})
}

func TestService_ListCoinNews(t *testing.T) {
	t.Parallel()

	t.Run("list empty coin news", func(t *testing.T) {
		t.Parallel()

		database := database.Test(t)
		cli := miscv1connect.NewMiscServiceClient(apitests.RPC(t, database))

		resp, err := cli.ListCoinNews(t.Context(), &miscv1.ListCoinNewsRequest{})
		require.NoError(t, err)
		assert.Empty(t, resp.CoinNews)
	})

	t.Run("list coin news with data", func(t *testing.T) {
		t.Parallel()

		database := database.Test(t)
		ctx := t.Context()
		topicID1 := validTopicID()
		seedCurrentTopic(t, ctx, database, topicID1, "Test Topic 1", 1)
		topicID2 := validTopicID()
		seedCurrentTopic(t, ctx, database, topicID2, "Test Topic 2", 2)

		headline1 := "News Headline 1"
		seedCurrentNews(t, ctx, database, topicID1, headline1, "Content for news 1", 3, time.Now().Add(-2*time.Hour))

		headline2 := "News Headline 2"
		seedCurrentNews(t, ctx, database, topicID2, headline2, "Content for news 2", 4, time.Now().Add(-1*time.Hour))

		cli := miscv1connect.NewMiscServiceClient(apitests.RPC(t, database))

		resp, err := cli.ListCoinNews(t.Context(), &miscv1.ListCoinNewsRequest{})
		require.NoError(t, err)
		require.Len(t, resp.CoinNews, 2)

		// Equal fees list the newest first.
		assert.Equal(t, topicID2.String(), resp.CoinNews[0].Topic)
		assert.Equal(t, "News Headline 2", resp.CoinNews[0].Headline)
		assert.Equal(t, "Content for news 2", resp.CoinNews[0].Content)
		assert.Equal(t, topicID1.String(), resp.CoinNews[1].Topic)
		assert.Equal(t, "News Headline 1", resp.CoinNews[1].Headline)
		assert.Equal(t, "Content for news 1", resp.CoinNews[1].Content)
	})

	t.Run("list coin news filtered by topic", func(t *testing.T) {
		t.Parallel()

		database := database.Test(t)
		ctx := t.Context()

		firstTopicID := validTopicID()
		seedCurrentTopic(t, ctx, database, firstTopicID, "Test Topic 1", 1)

		secondTopicID := validTopicID()
		seedCurrentTopic(t, ctx, database, secondTopicID, "Test Topic 2", 2)

		headline1 := "News Headline 1"
		seedCurrentNews(t, ctx, database, firstTopicID, headline1, "Content for news 1", 3, time.Now())

		headline2 := "News Headline 2"
		seedCurrentNews(t, ctx, database, secondTopicID, headline2, "Content for news 2", 4, time.Now().Add(time.Second))

		cli := miscv1connect.NewMiscServiceClient(apitests.RPC(t, database))

		// Filter by topic
		topic := firstTopicID.String()
		resp, err := cli.ListCoinNews(t.Context(), &miscv1.ListCoinNewsRequest{
			Topic: &topic,
		})
		require.NoError(t, err)
		require.Len(t, resp.CoinNews, 1)
		assert.Equal(t, topic, resp.CoinNews[0].Topic)
		assert.Equal(t, "News Headline 1", resp.CoinNews[0].Headline)
	})

	t.Run("list coin news with equal fees newest first", func(t *testing.T) {
		t.Parallel()

		database := database.Test(t)
		ctx := t.Context()
		firstTopicID := validTopicID()
		seedCurrentTopic(t, ctx, database, firstTopicID, "Test Topic 1", 1)
		secondTopicID := validTopicID()
		seedCurrentTopic(t, ctx, database, secondTopicID, "Test Topic 2", 2)

		headline1 := "Old News"
		seedCurrentNews(t, ctx, database, firstTopicID, headline1, "Content for old news", 3, time.Now().Add(-3*time.Hour))

		headline2 := "Recent News"
		seedCurrentNews(t, ctx, database, secondTopicID, headline2, "Content for recent news", 4, time.Now().Add(-2*time.Hour))

		headline3 := "Latest News"
		seedCurrentNews(t, ctx, database, firstTopicID, headline3, "Content for latest news", 5, time.Now().Add(-1*time.Hour))

		cli := miscv1connect.NewMiscServiceClient(apitests.RPC(t, database))

		resp, err := cli.ListCoinNews(t.Context(), &miscv1.ListCoinNewsRequest{})
		require.NoError(t, err)
		require.Len(t, resp.CoinNews, 3)

		assert.Equal(t, "Latest News", resp.CoinNews[0].Headline)
		assert.Equal(t, "Recent News", resp.CoinNews[1].Headline)
		assert.Equal(t, "Old News", resp.CoinNews[2].Headline)
	})

	t.Run("list coin news limited to 100 entries", func(t *testing.T) {
		t.Parallel()

		database := database.Test(t)
		ctx := t.Context()
		firstTopicID := validTopicID()
		seedCurrentTopic(t, ctx, database, firstTopicID, "Test Topic 1", 1)

		secondTopicID := validTopicID()
		seedCurrentTopic(t, ctx, database, secondTopicID, "Test Topic 2", 2)

		for i := range 105 {
			headline := "News"
			seedCurrentNews(t, ctx, database, firstTopicID, headline, "Content for news", 3+i, time.Now().Add(time.Duration(i)*time.Second))
		}

		cli := miscv1connect.NewMiscServiceClient(apitests.RPC(t, database))

		resp, err := cli.ListCoinNews(t.Context(), &miscv1.ListCoinNewsRequest{})
		require.NoError(t, err)
		// Should be limited to 100 entries
		assert.Len(t, resp.CoinNews, 100)
	})
}

func seedCurrentTopic(
	t *testing.T, ctx context.Context, db *sql.DB,
	topic opreturns.TopicID, name string, height int,
) {
	t.Helper()
	var ct coinnews.Topic
	copy(ct[:], topic[:])
	require.NoError(t, cnstore.Index(ctx, db, cnstore.IndexEnv{
		Pos: cnstore.BlockPos{
			BlockHeight: uint32(height),
			TxIndex:     0,
			VoutIndex:   0,
			BlockTime:   time.Now(),
			TxID:        fmt.Sprintf("%064x", height),
		},
		TypeTag: coinnews.TypeTopicCreation,
		Msg: &coinnews.TopicCreation{
			Topic:         ct,
			RetentionDays: 7,
			Name:          name,
		},
	}))
}

func seedCurrentNews(
	t *testing.T, ctx context.Context, db *sql.DB,
	topic opreturns.TopicID, headline, content string, order int, blockTime time.Time,
) {
	t.Helper()
	var ct coinnews.Topic
	copy(ct[:], topic[:])
	story := &coinnews.Story{Topic: ct, Headline: headline}
	if content != "" {
		story.TLVs = append(story.TLVs, coinnews.TLV{Tag: coinnews.TLVBody, Value: []byte(content)})
	}
	require.NoError(t, cnstore.Index(ctx, db, cnstore.IndexEnv{
		Pos: cnstore.BlockPos{
			BlockHeight: uint32(100 + order),
			TxIndex:     uint32(order),
			VoutIndex:   0,
			BlockTime:   blockTime,
			TxID:        fmt.Sprintf("%064x", 1000+order),
		},
		TypeTag: coinnews.TypeStory,
		Msg:     story,
	}))
}

func validTopicID() opreturns.TopicID {
	buf := make([]byte, opreturns.TopicIdLength)
	if _, err := rand.Read(buf); err != nil {
		panic(err)
	}
	return opreturns.TopicID(buf)
}

func TestService_TimestampFile(t *testing.T) {
	t.Parallel()

	t.Run("timestamp file success", func(t *testing.T) {
		t.Parallel()

		ctrl := gomock.NewController(t)
		mockOrch := mocks.NewMockWalletManagerServiceClient(ctrl)
		apitests.ExpectOrchestratorReads(mockOrch)

		mockOrch.EXPECT().
			SendTransaction(gomock.Any(), gomock.Any()).
			Return(&orchpb.SendTransactionResponse{Txid: "timestamp-txid"}, nil)

		database := database.Test(t)
		cli := miscv1connect.NewMiscServiceClient(apitests.RPC(t, database, apitests.WithOrchestrator(mockOrch)))

		resp, err := cli.TimestampFile(t.Context(), &miscv1.TimestampFileRequest{
			Filename: "test-document.pdf",
			FileData: []byte("This is the content of the test document"),
		})
		require.NoError(t, err)
		assert.NotEmpty(t, resp.Id)
		assert.NotEmpty(t, resp.FileHash)
		assert.NotEmpty(t, resp.Txid)
	})

	t.Run("timestamp file with empty filename", func(t *testing.T) {
		t.Parallel()

		database := database.Test(t)
		cli := miscv1connect.NewMiscServiceClient(apitests.RPC(t, database))

		_, err := cli.TimestampFile(t.Context(), &miscv1.TimestampFileRequest{
			Filename: "",
			FileData: []byte("content"),
		})
		require.ErrorContains(t, err, "filename must be set")
	})

	t.Run("timestamp file with empty file data", func(t *testing.T) {
		t.Parallel()

		database := database.Test(t)
		cli := miscv1connect.NewMiscServiceClient(apitests.RPC(t, database))

		_, err := cli.TimestampFile(t.Context(), &miscv1.TimestampFileRequest{
			Filename: "test.pdf",
			FileData: []byte{},
		})
		require.ErrorContains(t, err, "file data must be set")
	})

	t.Run("timestamp same file twice returns same timestamp", func(t *testing.T) {
		t.Parallel()

		ctrl := gomock.NewController(t)
		mockOrch := mocks.NewMockWalletManagerServiceClient(ctrl)
		apitests.ExpectOrchestratorReads(mockOrch)

		// Only one transaction should be sent
		mockOrch.EXPECT().
			SendTransaction(gomock.Any(), gomock.Any()).
			Return(&orchpb.SendTransactionResponse{Txid: "timestamp-txid"}, nil).
			Times(1)

		database := database.Test(t)
		cli := miscv1connect.NewMiscServiceClient(apitests.RPC(t, database, apitests.WithOrchestrator(mockOrch)))

		fileData := []byte("duplicate content")

		// First timestamp
		resp1, err := cli.TimestampFile(t.Context(), &miscv1.TimestampFileRequest{
			Filename: "first.pdf",
			FileData: fileData,
		})
		require.NoError(t, err)

		// Second timestamp with same content
		resp2, err := cli.TimestampFile(t.Context(), &miscv1.TimestampFileRequest{
			Filename: "second.pdf",
			FileData: fileData,
		})
		require.NoError(t, err)

		// Should return the same timestamp ID and hash
		assert.Equal(t, resp1.Id, resp2.Id)
		assert.Equal(t, resp1.FileHash, resp2.FileHash)
	})
}

func TestService_ListTimestamps(t *testing.T) {
	t.Parallel()

	t.Run("list empty timestamps", func(t *testing.T) {
		t.Parallel()

		ctrl := gomock.NewController(t)
		mockBitcoind := mocks.NewMockBitcoinServiceClient(ctrl)

		// Background operations
		mockBitcoind.EXPECT().
			ListWallets(gomock.Any(), gomock.Any()).
			Return(&connectv1.Response[corepb.ListWalletsResponse]{
				Msg: &corepb.ListWalletsResponse{Wallets: []string{}},
			}, nil).
			AnyTimes()
		mockBitcoind.EXPECT().
			CreateWallet(gomock.Any(), gomock.Any()).
			Return(&connectv1.Response[corepb.CreateWalletResponse]{
				Msg: &corepb.CreateWalletResponse{Name: "test_wallet"},
			}, nil).
			AnyTimes()
		// Required for ListTimestamps to get current block height
		mockBitcoind.EXPECT().
			GetBlockchainInfo(gomock.Any(), gomock.Any()).
			Return(&connectv1.Response[corepb.GetBlockchainInfoResponse]{
				Msg: &corepb.GetBlockchainInfoResponse{
					Chain:  "signet",
					Blocks: 1000,
				},
			}, nil).
			AnyTimes()

		database := database.Test(t)
		cli := miscv1connect.NewMiscServiceClient(apitests.RPC(t, database, apitests.WithBitcoind(mockBitcoind)))

		resp, err := cli.ListTimestamps(t.Context(), &emptypb.Empty{})
		require.NoError(t, err)
		assert.Empty(t, resp.Timestamps)
	})

	t.Run("list timestamps with data", func(t *testing.T) {
		t.Parallel()

		ctrl := gomock.NewController(t)
		mockOrch := mocks.NewMockWalletManagerServiceClient(ctrl)
		apitests.ExpectOrchestratorReads(mockOrch)
		mockBitcoind := mocks.NewMockBitcoinServiceClient(ctrl)

		mockOrch.EXPECT().
			SendTransaction(gomock.Any(), gomock.Any()).
			Return(&orchpb.SendTransactionResponse{Txid: "timestamp-txid-1"}, nil).
			Times(2)

		// Background operations
		mockBitcoind.EXPECT().
			ListWallets(gomock.Any(), gomock.Any()).
			Return(&connectv1.Response[corepb.ListWalletsResponse]{
				Msg: &corepb.ListWalletsResponse{Wallets: []string{}},
			}, nil).
			AnyTimes()
		mockBitcoind.EXPECT().
			CreateWallet(gomock.Any(), gomock.Any()).
			Return(&connectv1.Response[corepb.CreateWalletResponse]{
				Msg: &corepb.CreateWalletResponse{Name: "test_wallet"},
			}, nil).
			AnyTimes()
		// Required for ListTimestamps to get current block height
		mockBitcoind.EXPECT().
			GetBlockchainInfo(gomock.Any(), gomock.Any()).
			Return(&connectv1.Response[corepb.GetBlockchainInfoResponse]{
				Msg: &corepb.GetBlockchainInfoResponse{
					Chain:  "signet",
					Blocks: 1000,
				},
			}, nil).
			AnyTimes()

		database := database.Test(t)
		cli := miscv1connect.NewMiscServiceClient(apitests.RPC(t, database,
			apitests.WithOrchestrator(mockOrch),
			apitests.WithBitcoind(mockBitcoind),
		))

		// Create some timestamps
		_, err := cli.TimestampFile(t.Context(), &miscv1.TimestampFileRequest{
			Filename: "file1.pdf",
			FileData: []byte("content 1"),
		})
		require.NoError(t, err)

		_, err = cli.TimestampFile(t.Context(), &miscv1.TimestampFileRequest{
			Filename: "file2.pdf",
			FileData: []byte("content 2"),
		})
		require.NoError(t, err)

		resp, err := cli.ListTimestamps(t.Context(), &emptypb.Empty{})
		require.NoError(t, err)
		require.Len(t, resp.Timestamps, 2)
	})
}

func TestService_ListTimestampsBlockHeight(t *testing.T) {
	t.Parallel()

	t.Run("a failed Core read returns the error", func(t *testing.T) {
		t.Parallel()

		ctrl := gomock.NewController(t)
		mockBitcoind := mocks.NewMockBitcoinServiceClient(ctrl)
		apitests.ExpectCoreWalletSetup(mockBitcoind)
		mockBitcoind.EXPECT().
			GetBlockchainInfo(gomock.Any(), gomock.Any()).
			Return(nil, connectv1.NewError(connectv1.CodeUnavailable, errors.New("core is down"))).
			AnyTimes()

		cli := miscv1connect.NewMiscServiceClient(apitests.RPC(t, database.Test(t), apitests.WithBitcoind(mockBitcoind)))

		_, err := cli.ListTimestamps(t.Context(), &emptypb.Empty{})
		require.ErrorContains(t, err, "core is down")
	})

	t.Run("light mode reads no Core", func(t *testing.T) {
		t.Parallel()

		ctrl := gomock.NewController(t)
		mockOrch := mocks.NewMockWalletManagerServiceClient(ctrl)
		mockOrch.EXPECT().
			GetNodeMode(gomock.Any(), gomock.Any()).
			Return(&orchpb.GetNodeModeResponse{Mode: orchpb.NodeMode_NODE_MODE_LIGHT}, nil).
			AnyTimes()
		apitests.ExpectOrchestratorReads(mockOrch)
		mockBitcoind := mocks.NewMockBitcoinServiceClient(ctrl)
		apitests.ExpectCoreWalletSetup(mockBitcoind)

		cli := miscv1connect.NewMiscServiceClient(apitests.RPC(t, database.Test(t),
			apitests.WithOrchestrator(mockOrch),
			apitests.WithBitcoind(mockBitcoind),
		))

		resp, err := cli.ListTimestamps(t.Context(), &emptypb.Empty{})
		require.NoError(t, err)
		assert.Empty(t, resp.Timestamps)
	})
}

func TestService_VerifyTimestamp(t *testing.T) {
	t.Parallel()

	t.Run("verify non-existent timestamp", func(t *testing.T) {
		t.Parallel()

		database := database.Test(t)
		cli := miscv1connect.NewMiscServiceClient(apitests.RPC(t, database))

		_, err := cli.VerifyTimestamp(t.Context(), &miscv1.VerifyTimestampRequest{
			FileData: []byte("unknown content"),
		})
		require.Equal(t, connect.CodeNotFound, connect.CodeOf(err))
	})

	t.Run("verify with empty file data", func(t *testing.T) {
		t.Parallel()

		database := database.Test(t)
		cli := miscv1connect.NewMiscServiceClient(apitests.RPC(t, database))

		_, err := cli.VerifyTimestamp(t.Context(), &miscv1.VerifyTimestampRequest{
			FileData: []byte{},
		})
		require.ErrorContains(t, err, "file data must be set")
	})

	t.Run("verify accepts only a confirmed timestamp", func(t *testing.T) {
		t.Parallel()

		ctrl := gomock.NewController(t)
		mockOrch := mocks.NewMockWalletManagerServiceClient(ctrl)
		apitests.ExpectOrchestratorReads(mockOrch)
		mockBitcoind := mocks.NewMockBitcoinServiceClient(ctrl)

		mockOrch.EXPECT().
			SendTransaction(gomock.Any(), gomock.Any()).
			Return(&orchpb.SendTransactionResponse{Txid: "timestamp-txid"}, nil)

		// Background operations
		mockBitcoind.EXPECT().
			ListWallets(gomock.Any(), gomock.Any()).
			Return(&connectv1.Response[corepb.ListWalletsResponse]{
				Msg: &corepb.ListWalletsResponse{Wallets: []string{}},
			}, nil).
			AnyTimes()
		mockBitcoind.EXPECT().
			CreateWallet(gomock.Any(), gomock.Any()).
			Return(&connectv1.Response[corepb.CreateWalletResponse]{
				Msg: &corepb.CreateWalletResponse{Name: "test_wallet"},
			}, nil).
			AnyTimes()
		// Required for VerifyTimestamp to get current block height
		mockBitcoind.EXPECT().
			GetBlockchainInfo(gomock.Any(), gomock.Any()).
			Return(&connectv1.Response[corepb.GetBlockchainInfoResponse]{
				Msg: &corepb.GetBlockchainInfoResponse{
					Chain:  "signet",
					Blocks: 1000,
				},
			}, nil).
			AnyTimes()

		database := database.Test(t)
		cli := miscv1connect.NewMiscServiceClient(apitests.RPC(t, database,
			apitests.WithOrchestrator(mockOrch),
			apitests.WithBitcoind(mockBitcoind),
		))

		fileData := []byte("content to verify")

		// First create the timestamp
		_, err := cli.TimestampFile(t.Context(), &miscv1.TimestampFileRequest{
			Filename: "verify-test.pdf",
			FileData: fileData,
		})
		require.NoError(t, err)

		verify := func() (*miscv1.VerifyTimestampResponse, error) {
			return cli.VerifyTimestamp(t.Context(), &miscv1.VerifyTimestampRequest{
				FileData: fileData,
			})
		}

		_, err = verify()
		require.ErrorContains(t, err, "the timestamp is not confirmed yet")
		assert.Equal(t, connect.CodeFailedPrecondition, connect.CodeOf(err))

		rows, err := timestamps.List(t.Context(), database)
		require.NoError(t, err)
		require.Len(t, rows, 1)

		require.NoError(t, timestamps.Update(t.Context(), database, rows[0].ID, nil, nil, timestamps.StatusFailed, nil))
		_, err = verify()
		require.ErrorContains(t, err, "the timestamp transaction failed")
		assert.Equal(t, connect.CodeFailedPrecondition, connect.CodeOf(err))

		confirmedAt := time.Now()
		height := int64(990)
		require.NoError(t, timestamps.Update(t.Context(), database, rows[0].ID, nil, &height, timestamps.StatusConfirmed, &confirmedAt))
		resp, err := verify()
		require.NoError(t, err)
		assert.NotNil(t, resp.Timestamp)
		assert.Contains(t, resp.Message, "verified")
	})
}
